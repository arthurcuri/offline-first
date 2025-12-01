import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:provider/provider.dart';
import '../providers/task_provider.dart';
import '../models/task.dart';
import '../services/connectivity_service.dart';
import 'task_form_screen.dart';
import '../providers/theme_provider.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _connectivity = ConnectivityService.instance;
  bool _isOnline = true;

  @override
  void initState() {
    super.initState();
    _initializeConnectivity();
  }

  Future<void> _initializeConnectivity() async {
    await _connectivity.initialize();
    setState(() => _isOnline = _connectivity.isOnline);
    _connectivity.connectivityStream.listen((isOnline) {
      setState(() => _isOnline = isOnline);
    });
  }

  // Removido: não mostrar snackbars de status

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final titleStyle = Theme.of(context).textTheme.titleMedium;

    return Scaffold(
      extendBody: true,
      appBar: AppBar(
        title: const Text('Task Mannager Offline First'),
        actions: [
          _buildConnectivityIndicator(context),
          IconButton(
            icon: const Icon(Icons.sync),
            tooltip: 'Sincronizar agora',
            onPressed: () async {
              final taskProvider = Provider.of<TaskProvider>(context, listen: false);
              final result = await taskProvider.sync();
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(result.success ? 'Sincronização concluída!' : 'Falha na sincronização'),
                  backgroundColor: result.success ? Colors.green : Colors.red,
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.brightness_6),
            tooltip: 'Alternar tema',
            onPressed: () {
              final themeProvider = Provider.of<ThemeProvider>(context, listen: false);
              themeProvider.setTheme(
                themeProvider.themeMode == ThemeMode.light
                  ? ThemeMode.dark
                  : ThemeMode.light,
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            color: _isOnline ? Colors.green[50] : Colors.orange[50],
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                  // ...ícone de nuvem removido...
                  //const SizedBox(width: 8),
                Text(
                  _isOnline ? 'Modo Online' : 'Modo Offline',
                  style: TextStyle(
                    color: _isOnline ? Colors.green : Colors.orange,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Container(
              color: colorScheme.background,
              child: Consumer<TaskProvider>(
                builder: (context, taskProvider, child) {
                  print('[HomeScreen] Tarefas recebidas: ${taskProvider.tasks.length}');
                  if (taskProvider.isLoading) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  if (taskProvider.error != null) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.error_outline, size: 64, color: Colors.red[300]),
                          const SizedBox(height: 16),
                          Text('Erro: ${taskProvider.error}'),
                          const SizedBox(height: 16),
                          ElevatedButton(
                            onPressed: () => taskProvider.loadTasks(),
                            child: const Text('Tentar Novamente'),
                          ),
                        ],
                      ),
                    );
                  }

                  final incompleteTasks = taskProvider.pendingTasks;
                  final completedTasks = taskProvider.completedTasks;

                  print('[HomeScreen] Incompletas: ${incompleteTasks.length}, Completas: ${completedTasks.length}');

                  if (incompleteTasks.isEmpty && completedTasks.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.terminal,
                            size: 64,
                            color: Colors.grey[500],
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Nenhuma tarefa',
                            style: titleStyle?.copyWith(color: Colors.grey[300]),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Use o + para compilar a primeira missão.',
                            style: TextStyle(color: Colors.grey[500]),
                          ),
                        ],
                      ),
                    );
                  }

                  return RefreshIndicator(
                    color: colorScheme.primary,
                    onRefresh: () => taskProvider.sync(),
                    child: ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        if (incompleteTasks.isNotEmpty) ...[
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8.0),
                            child: Text(
                              'Tarefas Incompletas',
                              style: titleStyle?.copyWith(fontWeight: FontWeight.bold, fontSize: 18),
                            ),
                          ),
                          ...List.generate(
                            incompleteTasks.length,
                            (index) => Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: _buildTaskCard(context, incompleteTasks[index], taskProvider),
                            ),
                          ),
                        ],
                        if (completedTasks.isNotEmpty) ...[
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8.0),
                            child: Text(
                              'Tarefas Completas',
                              style: titleStyle?.copyWith(fontWeight: FontWeight.bold, fontSize: 18),
                            ),
                          ),
                          ...List.generate(
                            completedTasks.length,
                            (index) => Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: _buildTaskCard(context, completedTasks[index], taskProvider),
                            ),
                          ),
                        ],
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _navigateToTaskForm,
        child: const Icon(Icons.add),
        tooltip: 'Nova Tarefa',
        backgroundColor: colorScheme.primary,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: Colors.pinkAccent, width: 2),
        ),
      ),
    );
  }

  Widget _buildConnectivityIndicator(BuildContext context) {
    // Ícone de nuvem: verde (online), vermelha/laranja (offline)
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          Icon(
            _isOnline ? Icons.cloud_done : Icons.cloud_off,
            color: _isOnline ? Colors.green : Colors.orange,
            size: 28,
          ),
          const SizedBox(width: 4),
          Text(
            _isOnline ? 'Online' : 'Offline',
            style: TextStyle(
              color: _isOnline ? Colors.green : Colors.orange,
              fontWeight: FontWeight.bold,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTaskCard(
      BuildContext context, Task task, TaskProvider provider) {
    final colorScheme = Theme.of(context).colorScheme;
    Icon syncIcon;
    switch (task.syncStatus) {
      case SyncStatus.synced:
        syncIcon = const Icon(Icons.cloud_done, color: Colors.green, size: 20);
        break;
      case SyncStatus.pending:
        syncIcon = const Icon(Icons.cloud_off, color: Colors.orange, size: 20);
        break;
      case SyncStatus.conflict:
        syncIcon = const Icon(Icons.cloud_sync, color: Colors.red, size: 20);
        break;
      case SyncStatus.error:
        syncIcon = const Icon(Icons.cloud_off, color: Colors.red, size: 20);
        break;
    }
    return Card(
      margin: EdgeInsets.zero,
      child: Container(
        decoration: BoxDecoration(
          border: Border(
            left: BorderSide(
              color: colorScheme.primary,
              width: 4,
            ),
          ),
        ),
        child: Slidable(
          key: ValueKey(task.id),
          startActionPane: ActionPane(
            motion: const DrawerMotion(),
            extentRatio: 0.25,
            children: [
              SlidableAction(
                onPressed: (_) => provider.toggleCompleted(task),
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
                icon: Icons.check,
                label: 'Concluir',
              ),
            ],
          ),
          endActionPane: ActionPane(
            motion: const DrawerMotion(),
            extentRatio: 0.5,
            children: [
              SlidableAction(
                onPressed: (_) => _navigateToTaskForm(task: task),
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
                icon: Icons.edit,
                label: 'Editar',
              ),
              SlidableAction(
                onPressed: (_) => _confirmDelete(task, provider),
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
                icon: Icons.delete,
                label: 'Apagar',
              ),
            ],
          ),
          child: ListTile(
            leading: SizedBox(
              width: 32,
              child: Center(child: syncIcon),
            ),
            title: Text(
              task.title,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    decoration:
                        task.completed ? TextDecoration.lineThrough : null,
                    fontWeight: FontWeight.w600,
                  ),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (task.description.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      task.description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    _buildPriorityBadge(context, task.priority),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPriorityBadge(BuildContext context, String priority) {
    final colorScheme = Theme.of(context).colorScheme;
    Color color;
    switch (priority) {
      case 'urgent':
        color = Colors.pinkAccent;
        break;
      case 'high':
        color = Colors.pink;
        break;
      case 'medium':
        color = colorScheme.primary;
        break;
      case 'low':
        color = Colors.pink.shade100;
        break;
      default:
        color = Colors.pink.shade200;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.7)),
        color: color.withOpacity(0.12),
      ),
      child: Text(
        priority.toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.1,
          color: color,
        ),
      ),
    );
  }


  // Removido: botão e função de sincronização manual

  void _navigateToTaskForm({Task? task}) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => TaskFormScreen(task: task),
      ),
    );
  }

  // Removido: navegação para tela de status de sincronização

  Future<void> _confirmDelete(Task task, TaskProvider provider) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirmar exclusão'),
        content: Text('Deseja deletar "${task.title}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Deletar'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await provider.deleteTask(task.id);
    }
  }
}
