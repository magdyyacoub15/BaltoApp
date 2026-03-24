import 'dart:async';
import 'package:appwrite/appwrite.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'appwrite_client.dart';
import 'offline_queue_service.dart';

final syncServiceProvider = Provider<SyncService>((ref) {
  return SyncService(
    ref.read(appwriteTablesDBProvider),
    ref.read(offlineQueueServiceProvider),
  );
});

/// Listens to connectivity changes and replays offline operations
/// against Appwrite as soon as the device is back online.
class SyncService {
  final TablesDB _databases;
  final OfflineQueueService _queue;

  StreamSubscription? _sub;
  bool _syncing = false;

  SyncService(this._databases, this._queue);

  /// Call once from main() after ProviderScope is set up.
  void startListening() {
    _sub = Connectivity().onConnectivityChanged.listen((results) async {
      final hasNet = results.any((r) => r != ConnectivityResult.none);
      if (hasNet && _queue.hasPending && !_syncing) {
        await processQueue();
      }
    });

    // Also try to sync immediately on startup (in case we come up online
    // with pending items from a previous session).
    _trySyncOnStartup();
  }

  void _trySyncOnStartup() async {
    await Future.delayed(const Duration(seconds: 3));
    if (_queue.hasPending && !_syncing) {
      await processQueue();
    }
  }

  void dispose() {
    _sub?.cancel();
  }

  // ─── Queue Processing ──────────────────────────────────────────────────────

  /// Replays all queued operations in chronological order.
  /// Removes each entry on success; leaves it if it fails.
  Future<void> processQueue() async {
    if (_syncing) return;
    _syncing = true;

    debugPrint(
      '🔄 [SyncService] Processing ${_queue.pendingCount} pending operation(s)',
    );

    final entries = _queue.getAll();

    for (final entry in entries) {
      try {
        switch (entry.operation) {
          case 'create':
            await _databases.createRow(
              databaseId: appwriteDatabaseId,
              tableId: entry.table,
              rowId: entry.rowId,
              data: entry.data,
            );
            break;

          case 'update':
            await _databases.updateRow(
              databaseId: appwriteDatabaseId,
              tableId: entry.table,
              rowId: entry.rowId,
              data: entry.data,
            );
            break;

          case 'delete':
            await _databases.deleteRow(
              databaseId: appwriteDatabaseId,
              tableId: entry.table,
              rowId: entry.rowId,
            );
            break;
        }

        _queue.remove(entry.id);
        debugPrint(
          '✅ [SyncService] ${entry.operation} ${entry.table}/${entry.rowId}',
        );
      } catch (e) {
        // If the document was already deleted/not found, consider it done.
        if (e is AppwriteException &&
            (e.code == 404 || e.code == 409)) {
          _queue.remove(entry.id);
          debugPrint(
            'ℹ️ [SyncService] ${entry.operation} ${entry.table}/${entry.rowId} — skipped (${e.code})',
          );
        } else {
          debugPrint(
            '⚠️ [SyncService] Failed to sync ${entry.operation} ${entry.table}/${entry.rowId}: $e',
          );
          // Leave in queue for next attempt
        }
      }
    }

    _syncing = false;
    debugPrint('✅ [SyncService] Sync pass complete. Remaining: ${_queue.pendingCount}');
  }
}
