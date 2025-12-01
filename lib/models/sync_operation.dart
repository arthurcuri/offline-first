import 'dart:convert';

import 'package:uuid/uuid.dart';

/// Operação de sincronização pendente
class SyncOperation {
  final String id;
  final OperationType type;
  final String taskId;
  final Map<String, dynamic> data;
  final DateTime timestamp;
  final int retries;
  final SyncOperationStatus status;
  final String? error;

  SyncOperation({
    String? id,
    required this.type,
    required this.taskId,
    required this.data,
    DateTime? timestamp,
    this.retries = 0,
    this.status = SyncOperationStatus.pending,
    this.error,
  })  : id = id ?? const Uuid().v4(),
        timestamp = timestamp ?? DateTime.now();

  /// Criar cópia com modificações
  SyncOperation copyWith({
    OperationType? type,
    String? taskId,
    Map<String, dynamic>? data,
    DateTime? timestamp,
    int? retries,
    SyncOperationStatus? status,
    String? error,
  }) {
    return SyncOperation(
      id: id,
      type: type ?? this.type,
      taskId: taskId ?? this.taskId,
      data: data ?? this.data,
      timestamp: timestamp ?? this.timestamp,
      retries: retries ?? this.retries,
      status: status ?? this.status,
      error: error ?? this.error,
    );
  }

  /// Converter para Map
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'type': type.toString(),
      'taskId': taskId,
      'data': json.encode(data),
      'timestamp': timestamp.millisecondsSinceEpoch,
      'retries': retries,
      'status': status.toString(),
      'error': error,
    };
  }

  /// Criar a partir de Map
  factory SyncOperation.fromMap(Map<String, dynamic> map) {
    return SyncOperation(
      id: map['id'],
      type: OperationType.values.firstWhere(
        (e) => e.toString() == map['type'],
      ),
      taskId: map['taskId'],
      data: _parseData(map['data']),
      timestamp: DateTime.fromMillisecondsSinceEpoch(map['timestamp']),
      retries: map['retries'],
      status: SyncOperationStatus.values.firstWhere(
        (e) => e.toString() == map['status'],
      ),
      error: map['error'],
    );
  }

  static Map<String, dynamic> _parseData(dynamic rawData) {
    if (rawData == null) {
      return {};
    }

    if (rawData is Map<String, dynamic>) {
      return Map<String, dynamic>.from(rawData);
    }

    final dataStr = rawData.toString().trim();
    if (dataStr.isEmpty) {
      return {};
    }

    try {
      final decoded = json.decode(dataStr);
      if (decoded is Map<String, dynamic>) {
        return Map<String, dynamic>.from(decoded);
      }
    } catch (_) {
      // Continua para tentar parser legado
    }

    return _parseLegacyMap(dataStr);
  }

  static Map<String, dynamic> _parseLegacyMap(String dataStr) {
    final sanitized = dataStr.trim();
    if (!sanitized.startsWith('{') || !sanitized.endsWith('}')) {
      return {};
    }

    final content = sanitized.substring(1, sanitized.length - 1);
    final Map<String, dynamic> result = {};

    for (final pair in content.split(',')) {
      final separatorIndex = pair.indexOf(':');
      if (separatorIndex == -1) continue;

      final key = pair.substring(0, separatorIndex).trim();
      final value = pair.substring(separatorIndex + 1).trim();
      result[key] = value;
    }

    return result;
  }

  @override
  String toString() {
    return 'SyncOperation(type: $type, taskId: $taskId, status: $status)';
  }
}

/// Tipo de operação
enum OperationType {
  create,
  update,
  delete,
}

/// Status da operação de sincronização
enum SyncOperationStatus {
  pending,
  processing,
  completed,
  failed,
}
