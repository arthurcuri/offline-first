import 'dart:async';
import 'dart:io';
import '../models/task.dart';
import '../models/sync_operation.dart';
import 'database_service.dart';
import 'api_service.dart';
import 'connectivity_service.dart';

/// Motor de Sincronização Offline-First
///
/// Implementa sincronização simples usando estratégia Last-Write-Wins (LWW)
class SyncService {
  final DatabaseService _db = DatabaseService.instance;
  final ApiService _api;
  final ConnectivityService _connectivity = ConnectivityService.instance;

  bool _isSyncing = false;
  Timer? _autoSyncTimer;

  final _syncStatusController = StreamController<SyncEvent>.broadcast();
  Stream<SyncEvent> get syncStatusStream => _syncStatusController.stream;

  SyncService({String userId = 'user1'}) : _api = ApiService(userId: userId);

  // ==================== SINCRONIZAÇÃO PRINCIPAL ====================

  /// Executar sincronização completa
  Future<SyncResult> sync({bool fullSync = false}) async {
    if (_isSyncing) {
      return SyncResult(
        success: false,
        message: 'Sincronização já em andamento',
      );
    }
    if (!_connectivity.isOnline) {
      return SyncResult(
        success: false,
        message: 'Sem conexão com internet',
      );
    }
    _isSyncing = true;
    _notifyStatus(SyncEvent.syncStarted());
    try {
      final pushResult = await _pushPendingOperations();
      final pullResult = await _pullFromServer(fullSync: fullSync);
      await _db.setMetadata(
        'lastSyncTimestamp',
        DateTime.now().millisecondsSinceEpoch.toString(),
      );
      _notifyStatus(SyncEvent.syncCompleted(
        pushedCount: pushResult,
        pulledCount: pullResult,
      ));
      return SyncResult(
        success: true,
        message: 'Sincronização concluída com sucesso',
        pushedOperations: pushResult,
        pulledTasks: pullResult,
      );
    } catch (e) {
      final isNetworkIssue = _isNetworkError(e);
      final errorMessage = isNetworkIssue
          ? 'Servidor indisponível - operações continuarão na fila'
          : 'Erro na sincronização: $e';
      _notifyStatus(SyncEvent.syncError(errorMessage));
      return SyncResult(
        success: false,
        message: errorMessage,
      );
    } finally {
      _isSyncing = false;
    }
  }

  // ==================== PUSH (Cliente → Servidor) ====================

  /// Enviar operações pendentes para o servidor
  Future<int> _pushPendingOperations() async {
    final operations = await _db.getPendingSyncOperations();

    int successCount = 0;

    for (final operation in operations) {
      try {
        await _processOperation(operation);
        await _db.removeSyncOperation(operation.id);
        successCount++;
      } catch (e) {
        await _handleOperationError(operation, e);

        if (_isNetworkError(e)) {
          rethrow;
        }
      }
    }

    return successCount;
  }

  /// Processar operação individual
  Future<void> _processOperation(SyncOperation operation) async {
    switch (operation.type) {
      case OperationType.create:
        await _pushCreate(operation);
        break;
      case OperationType.update:
        await _pushUpdate(operation);
        break;
      case OperationType.delete:
        await _pushDelete(operation);
        break;
    }
  }

  Future<void> _pushCreate(SyncOperation operation) async {
    Task? task = await _db.getTask(operation.taskId);
    task ??= _taskFromOperation(operation);

    if (task == null) {
      throw Exception(
        'Dados indisponíveis para criar tarefa ${operation.taskId}',
      );
    }

    // Só tenta sincronizar se online
    if (_connectivity.isOnline) {
      final serverTask = await _api.createTask(task);
      // Atualizar tarefa local com dados do servidor
      await _db.upsertTask(
        task.copyWith(
          version: serverTask.version,
          updatedAt: serverTask.updatedAt,
          syncStatus: SyncStatus.synced,
        ),
      );
    } else {
      // Offline: mantém como pending
      await _db.upsertTask(
        task.copyWith(
          syncStatus: SyncStatus.pending,
        ),
      );
    }
  }

  Future<void> _pushUpdate(SyncOperation operation) async {
    Task? task = await _db.getTask(operation.taskId);
    task ??= _taskFromOperation(operation);

    if (task == null) {
      throw Exception(
        'Dados indisponíveis para atualizar tarefa ${operation.taskId}',
      );
    }

    final result = await _api.updateTask(task);

    if (result['conflict'] == true) {
      // Conflito detectado - aplicar Last-Write-Wins
      final serverTask = result['serverTask'] as Task;
      await _resolveConflict(task, serverTask);
    } else {
      // Sucesso - atualizar local
      final updatedTask = result['task'] as Task;
      await _db.upsertTask(
        task.copyWith(
          version: updatedTask.version,
          updatedAt: updatedTask.updatedAt,
          syncStatus: SyncStatus.synced,
        ),
      );
    }
  }

  Future<void> _pushDelete(SyncOperation operation) async {
    final task = await _db.getTask(operation.taskId);
    final operationVersion = _extractVersion(operation.data);
    final version = task?.version ?? operationVersion ?? 1;

    await _api.deleteTask(operation.taskId, version);
    await _db.deleteTask(operation.taskId);
  }

  // ==================== PULL (Servidor → Cliente) ====================

  /// Buscar atualizações do servidor
  Future<int> _pullFromServer({bool fullSync = false}) async {
    final lastSyncStr = await _db.getMetadata('lastSyncTimestamp');
    // Se nunca sincronizou, busca tudo (modifiedSince=0)
    final lastSync = lastSyncStr != null ? int.parse(lastSyncStr) : 0;

    final result = (lastSync == 0 || fullSync)
        ? await _api.getTasks()
        : await _api.getTasks(modifiedSince: lastSync);
    final serverTasks = result['tasks'] as List<Task>;

    print('Recebidas ${serverTasks.length} tarefas do servidor');
    for (final t in serverTasks) {
      print('Tarefa recebida: id=${t.id}, title=${t.title}, userId=${t.userId}, completed=${t.completed}, version=${t.version}, updatedAt=${t.updatedAt}');
    }

    // Só remove todas as tarefas locais se for um pull completo
    if (lastSync == 0 || fullSync) {
      final localTasks = await _db.getAllTasks(userId: _api.userId);
      for (final localTask in localTasks) {
        await _db.deleteTask(localTask.id);
      }
    }

    // FILA LWW: agrupa operações por id e aplica só a última
    final Map<String, Task> lwwQueue = {};
    for (final serverTask in serverTasks) {
      final existing = lwwQueue[serverTask.id];
      if (existing == null ||
          serverTask.version > existing.version ||
          (serverTask.version == existing.version && serverTask.updatedAt.isAfter(existing.updatedAt))) {
        lwwQueue[serverTask.id] = serverTask;
      }
    }

    for (final serverTask in lwwQueue.values) {
      final localTask = await _db.getTask(serverTask.id);
      bool shouldUpdate = false;
      if (localTask == null) {
        shouldUpdate = true;
      } else {
        if (serverTask.version > localTask.version) {
          shouldUpdate = true;
        } else if (serverTask.version == localTask.version && serverTask.updatedAt.isAfter(localTask.updatedAt)) {
          shouldUpdate = true;
        }
      }
      if (shouldUpdate) {
        await _db.upsertTask(
          serverTask.copyWith(syncStatus: SyncStatus.synced),
        );
      }
    }

    return serverTasks.length;
  }

  // ==================== RESOLUÇÃO DE CONFLITOS (LWW) ====================

  /// Resolver conflito usando Last-Write-Wins
  Future<void> _resolveConflict(Task localTask, Task serverTask) async {
    print('⚠️ Conflito detectado: ${localTask.id}');

    final localTime = localTask.localUpdatedAt ?? localTask.updatedAt;
    final serverTime = serverTask.updatedAt;

    Task winningTask;
    String reason;

    if (localTime.isAfter(serverTime)) {
      // Versão local vence
      reason = 'Modificação local é mais recente';
      print('🏆 LWW: Versão local vence');

      final result = await _api.updateTask(localTask);
      if (result['conflict'] == true) {
        winningTask = localTask;
      } else {
        winningTask = result['task'] as Task;
      }
    } else {
      // Versão servidor vence
      winningTask = serverTask;
      reason = 'Modificação do servidor é mais recente';
      print('🏆 LWW: Versão servidor vence');
    }

    // Atualizar banco local com versão vencedora
    await _db.upsertTask(
      winningTask.copyWith(syncStatus: SyncStatus.synced),
    );

    _notifyStatus(SyncEvent.conflictResolved(
      taskId: localTask.id,
      resolution: reason,
    ));
  }

  // ==================== OPERAÇÕES COM FILA ====================

  /// Criar tarefa (com suporte offline)
  Future<Task> createTask(Task task) async {
    // Salvar localmente
    final savedTask = await _db.upsertTask(
      task.copyWith(
        syncStatus: SyncStatus.pending,
        localUpdatedAt: DateTime.now(),
      ),
    );

    // Adicionar à fila de sincronização
    await _db.addToSyncQueue(
      SyncOperation(
        type: OperationType.create,
        taskId: savedTask.id,
        data: savedTask.toMap(),
      ),
    );

    // Tentar sincronizar imediatamente se online
    if (_connectivity.isOnline) {
      sync();
    }

    return savedTask;
  }

  /// Atualizar tarefa (com suporte offline)
  Future<Task> updateTask(Task task) async {
    // Salvar localmente
    final updatedTask = await _db.upsertTask(
      task.copyWith(
        syncStatus: SyncStatus.pending,
        localUpdatedAt: DateTime.now(),
      ),
    );

    // Adicionar à fila de sincronização
    await _db.addToSyncQueue(
      SyncOperation(
        type: OperationType.update,
        taskId: updatedTask.id,
        data: updatedTask.toMap(),
      ),
    );

    // Tentar sincronizar imediatamente se online
    if (_connectivity.isOnline) {
      sync();
    }

    return updatedTask;
  }

  /// Deletar tarefa (com suporte offline)
  Future<void> deleteTask(String taskId) async {
    final task = await _db.getTask(taskId);
    if (task == null) return;

    // Adicionar à fila de sincronização antes de deletar
    await _db.addToSyncQueue(
      SyncOperation(
        type: OperationType.delete,
        taskId: taskId,
        data: {'version': task.version},
      ),
    );

    // Deletar localmente
    await _db.deleteTask(taskId);

    // Tentar sincronizar imediatamente se online
    if (_connectivity.isOnline) {
      sync();
    }
  }

  // ==================== SINCRONIZAÇÃO AUTOMÁTICA ====================

  /// Iniciar sincronização automática
  void startAutoSync({Duration interval = const Duration(seconds: 30)}) {
    stopAutoSync(); // Parar timer anterior se existir

    _autoSyncTimer = Timer.periodic(interval, (timer) {
      if (_connectivity.isOnline && !_isSyncing) {
        sync();
      }
    });

  }

  /// Parar sincronização automática
  void stopAutoSync() {
    _autoSyncTimer?.cancel();
    _autoSyncTimer = null;
  }

  // ==================== NOTIFICAÇÕES ====================

  void _notifyStatus(SyncEvent event) {
    _syncStatusController.add(event);
  }

  // ==================== ESTATÍSTICAS ====================

  Future<SyncStats> getStats() async {
    final dbStats = await _db.getStats();
    final lastSyncStr = await _db.getMetadata('lastSyncTimestamp');
    final lastSync = lastSyncStr != null
        ? DateTime.fromMillisecondsSinceEpoch(int.parse(lastSyncStr))
        : null;

    return SyncStats(
      totalTasks: dbStats['totalTasks'],
      unsyncedTasks: dbStats['unsyncedTasks'],
      queuedOperations: dbStats['queuedOperations'],
      lastSync: lastSync,
      isOnline: _connectivity.isOnline,
      isSyncing: _isSyncing,
    );
  }

  // ==================== SUPORTE INTERNO ====================

  Future<void> _handleOperationError(
    SyncOperation operation,
    Object error,
  ) async {
    print('❌ Erro ao processar operação ${operation.id}: $error');

    final updatedOperation = operation.copyWith(
      retries: operation.retries + 1,
      error: error.toString(),
    );

    await _db.updateSyncOperation(updatedOperation);

    if (updatedOperation.retries >= 3) {
      await _db.updateSyncOperation(
        updatedOperation.copyWith(status: SyncOperationStatus.failed),
      );
    }
  }

  bool _isNetworkError(Object error) {
    return error is TimeoutException || error is SocketException;
  }

  Task? _taskFromOperation(SyncOperation operation) {
    if (operation.data.isEmpty) return null;

    try {
      return Task.fromMap(operation.data);
    } catch (e) {
      print('❌ Erro ao reconstruir tarefa ${operation.taskId}: $e');
      return null;
    }
  }

  int? _extractVersion(Map<String, dynamic> data) {
    final rawVersion = data['version'];

    if (rawVersion is int) return rawVersion;
    if (rawVersion is String) {
      return int.tryParse(rawVersion);
    }

    return null;
  }

  // ==================== LIMPEZA ====================

  void dispose() {
    stopAutoSync();
    _syncStatusController.close();
  }
}

// ==================== MODELOS DE SUPORTE ====================

/// Resultado de sincronização
class SyncResult {
  final bool success;
  final String message;
  final int? pushedOperations;
  final int? pulledTasks;

  SyncResult({
    required this.success,
    required this.message,
    this.pushedOperations,
    this.pulledTasks,
  });
}

/// Evento de sincronização
class SyncEvent {
  final SyncEventType type;
  final String? message;
  final Map<String, dynamic>? data;

  SyncEvent({
    required this.type,
    this.message,
    this.data,
  });

  factory SyncEvent.syncStarted() => SyncEvent(type: SyncEventType.started);

  factory SyncEvent.syncCompleted({int? pushedCount, int? pulledCount}) =>
      SyncEvent(
        type: SyncEventType.completed,
        data: {'pushed': pushedCount, 'pulled': pulledCount},
      );

  factory SyncEvent.syncError(String error) => SyncEvent(
        type: SyncEventType.error,
        message: error,
      );

  factory SyncEvent.conflictResolved({
    required String taskId,
    required String resolution,
  }) =>
      SyncEvent(
        type: SyncEventType.conflictResolved,
        message: resolution,
        data: {'taskId': taskId},
      );
}

enum SyncEventType {
  started,
  completed,
  error,
  conflictResolved,
}

/// Estatísticas de sincronização
class SyncStats {
  final int totalTasks;
  final int unsyncedTasks;
  final int queuedOperations;
  final DateTime? lastSync;
  final bool isOnline;
  final bool isSyncing;

  SyncStats({
    required this.totalTasks,
    required this.unsyncedTasks,
    required this.queuedOperations,
    this.lastSync,
    required this.isOnline,
    required this.isSyncing,
  });
}
