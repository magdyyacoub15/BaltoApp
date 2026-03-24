import 'dart:convert';
import 'package:appwrite/appwrite.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

const _queueBoxName = 'offline_queue';

final offlineQueueServiceProvider = Provider<OfflineQueueService>((ref) {
  return OfflineQueueService();
});

/// Represents a single pending write operation.
class QueueEntry {
  final String id;          // unique op ID
  final String table;      // Appwrite table name
  final String operation;   // 'create' | 'update' | 'delete'
  final String rowId;       // Appwrite row ID
  final Map<String, dynamic> data; // payload (empty for delete)
  final String clinicId;
  final int timestamp;      // epoch ms

  QueueEntry({
    required this.id,
    required this.table,
    required this.operation,
    required this.rowId,
    required this.data,
    required this.clinicId,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'table': table,
        'operation': operation,
        'rowId': rowId,
        'data': data,
        'clinicId': clinicId,
        'timestamp': timestamp,
      };

  factory QueueEntry.fromJson(Map<String, dynamic> j) => QueueEntry(
        id: j['id'],
        table: j['table'] ?? j['collection'] ?? '',
        operation: j['operation'],
        rowId: j['rowId'] ?? j['documentId'] ?? '',
        data: Map<String, dynamic>.from(j['data'] ?? {}),
        clinicId: j['clinicId'] ?? '',
        timestamp: j['timestamp'] ?? 0,
      );
}

/// Stores pending write operations when offline.
/// Each entry is identified by its QueueEntry.id as the Hive key.
class OfflineQueueService {
  Box<String> get _box => Hive.box<String>(_queueBoxName);

  /// Opens the Hive box. Called once from initHive().
  static Future<void> openBox() async {
    if (!Hive.isBoxOpen(_queueBoxName)) {
      await Hive.openBox<String>(_queueBoxName);
    }
  }

  // ─── Write ──────────────────────────────────────────────────────────────────

  void enqueue({
    required String table,
    required String operation,
    required String rowId,
    required Map<String, dynamic> data,
    required String clinicId,
  }) {
    final entry = QueueEntry(
      id: ID.unique(),
      table: table,
      operation: operation,
      rowId: rowId,
      data: data,
      clinicId: clinicId,
      timestamp: DateTime.now().millisecondsSinceEpoch,
    );
    _box.put(entry.id, json.encode(entry.toJson()));
    debugPrint(
      '📥 [OfflineQueue] enqueued $operation on $table/$rowId',
    );
  }

  void remove(String entryId) {
    _box.delete(entryId);
  }

  // ─── Read ──────────────────────────────────────────────────────────────────

  bool get hasPending => _box.isNotEmpty;

  int get pendingCount => _box.length;

  /// Returns all entries sorted by timestamp (oldest first).
  List<QueueEntry> getAll() {
    final entries = _box.values.map((raw) {
      try {
        return QueueEntry.fromJson(
          Map<String, dynamic>.from(json.decode(raw)),
        );
      } catch (e) {
        return null;
      }
    }).whereType<QueueEntry>().toList();

    entries.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    return entries;
  }
}
