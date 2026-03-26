// ignore_for_file: deprecated_member_use
import 'package:appwrite/appwrite.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../domain/transaction.dart';
import '../../../core/services/appwrite_client.dart';
import '../../../core/services/hive_cache_service.dart';
import '../../../core/services/connectivity_service.dart';
import '../../../core/services/offline_queue_service.dart';

final transactionRepositoryProvider = Provider(
  (ref) => TransactionRepository(
    ref.read(appwriteTablesDBProvider),
    ref.read(hiveCacheServiceProvider),
    ref.read(offlineQueueServiceProvider),
  ),
);

class TransactionRepository {
  final TablesDB _databases;
  final HiveCacheService _cache;
  final OfflineQueueService _queue;

  TransactionRepository(this._databases, this._cache, this._queue);

  /// Cache-First: returns cached transactions instantly, refreshes in background.
  Future<List<AppTransaction>> getTransactions(String clinicId) async {
    final cached = _cache.getCachedTransactions(clinicId);
    if (cached != null) {
      _refreshInBackground(clinicId);
      final list = cached
          .map((m) => AppTransaction.fromMap(m, m['id'] ?? ''))
          .toList();
      list.sort((a, b) => b.date.compareTo(a.date));
      return list;
    }
    return _fetchAndCache(clinicId);
  }

  /// Network-only: always fetches from server, ignores cache check.
  /// Used by the dashboard for real-time accuracy.
  Future<List<AppTransaction>> fetchLiveTransactions(String clinicId) async {
    try {
      final List<AppTransaction> all = [];
      int offset = 0;
      const int batchSize = 100;

      while (true) {
        final res = await _databases.listRows(
          databaseId: appwriteDatabaseId,
          tableId: 'transactions',
          queries: [
            Query.equal('clinicId', clinicId),
            Query.limit(batchSize),
            Query.offset(offset),
          ],
        );
        final batch = res.rows
            .map((doc) => AppTransaction.fromMap(doc.data, doc.$id));
        all.addAll(batch);
        if (res.rows.length < batchSize) break;
        offset += batchSize;
      }

      // Update cache with fresh data
      _cache.cacheTransactions(
        clinicId,
        all.map((t) => {...t.toMap(), 'id': t.id}).toList(),
      );

      all.sort((a, b) => b.date.compareTo(a.date));
      return all;
    } catch (e, st) {
      debugPrint('❌ [TransactionRepository] fetchLive error: $e\n$st');
      if (e is AppwriteException || e.toString().contains('SocketException')) {
        throw Exception('لا يوجد اتصال بالإنترنت. الصفحة الرئيسية تعمل فقط عند الاتصال بالشبكة.');
      }
      rethrow;
    }
  }

  Future<List<AppTransaction>> refreshTransactions(String clinicId) async {
    return _fetchAndCache(clinicId);
  }

  void _refreshInBackground(String clinicId) {
    _fetchAndCache(clinicId).catchError((e) {
      debugPrint('TransactionRepository: bg error: $e');
      return <AppTransaction>[];
    });
  }

  Future<List<AppTransaction>> _fetchAndCache(String clinicId) async {
    try {
      final isOnline = await checkIsOnline();
      if (!isOnline) {
        final cached = _cache.getCachedTransactions(clinicId);
        final list =
            cached
                ?.map((m) => AppTransaction.fromMap(m, m['id'] ?? ''))
                .toList() ??
            [];
        list.sort((a, b) => b.date.compareTo(a.date));
        return list;
      }

      // Paginated fetch — no hard limit
      final List<AppTransaction> all = [];
      int offset = 0;
      const int batchSize = 100;

      while (true) {
        final res = await _databases.listRows(
          databaseId: appwriteDatabaseId,
          tableId: 'transactions',
          queries: [
            Query.equal('clinicId', clinicId),
            Query.limit(batchSize),
            Query.offset(offset),
          ],
        );
        final batch = res.rows
            .map((doc) => AppTransaction.fromMap(doc.data, doc.$id));
        all.addAll(batch);
        if (res.rows.length < batchSize) break;
        offset += batchSize;
      }

      _cache.cacheTransactions(
        clinicId,
        all.map((t) => {...t.toMap(), 'id': t.id}).toList(),
      );

      all.sort((a, b) => b.date.compareTo(a.date));
      return all;
    } catch (_) {
      final cached = _cache.getCachedTransactions(clinicId);
      final list =
          cached
              ?.map((m) => AppTransaction.fromMap(m, m['id'] ?? ''))
              .toList() ??
          [];
      list.sort((a, b) => b.date.compareTo(a.date));
      return list;
    }
  }

  // ─── Offline-aware Writes ──────────────────────────────────────────────────

  Future<String> addTransaction(AppTransaction transaction) async {
    final docId = ID.unique();
    final data = transaction.toMap();
    final isOnline = await checkIsOnline();

    if (isOnline) {
      try {
        await _databases.createRow(
          databaseId: appwriteDatabaseId,
          tableId: 'transactions',
          rowId: docId,
          data: data,
          permissions: [
            Permission.read(Role.team(transaction.clinicId)),
            Permission.update(Role.team(transaction.clinicId)),
            Permission.delete(Role.team(transaction.clinicId, 'admin')),
          ],
        );
        _refreshInBackground(transaction.clinicId);
        return docId;
      } catch (_) {
        // fall through to offline path
      }
    }

    // Offline: apply to cache optimistically + enqueue
    final cached = _cache.getCachedTransactions(transaction.clinicId) ?? [];
    _cache.cacheTransactions(transaction.clinicId, [
      ...cached,
      {...data, 'id': docId},
    ]);
    _queue.enqueue(
      table: 'transactions',
      operation: 'create',
      rowId: docId,
      data: data,
      clinicId: transaction.clinicId,
    );
    debugPrint('📥 [TransactionRepo] addTransaction queued offline: $docId');
    return docId;
  }

  Future<void> updateTransaction(String id, AppTransaction transaction) async {
    final data = transaction.toMap();
    final isOnline = await checkIsOnline();

    if (isOnline) {
      try {
        await _databases.updateRow(
          databaseId: appwriteDatabaseId,
          tableId: 'transactions',
          rowId: id,
          data: data,
        );
        _refreshInBackground(transaction.clinicId);
        return;
      } catch (_) {
        // fall through to offline path
      }
    }

    // Offline: apply to cache optimistically + enqueue
    final cached = _cache.getCachedTransactions(transaction.clinicId) ?? [];
    final index = cached.indexWhere((m) => m['id'] == id);
    if (index != -1) {
      cached[index] = {...data, 'id': id};
      _cache.cacheTransactions(transaction.clinicId, cached);
    }
    
    _queue.enqueue(
      table: 'transactions',
      operation: 'update',
      rowId: id,
      data: data,
      clinicId: transaction.clinicId,
    );
    debugPrint('📥 [TransactionRepo] updateTransaction queued offline: $id');
  }

  Future<void> deleteTransaction(String id, String clinicId) async {
    // 1. Optimistic UI update: remove from local cache immediately
    final cached = _cache.getCachedTransactions(clinicId) ?? [];
    if (cached.isNotEmpty) {
      _cache.cacheTransactions(
        clinicId,
        cached.where((m) => m['id'] != id).toList(),
      );
    }

    final isOnline = await checkIsOnline();

    if (isOnline) {
      try {
        await _databases.deleteRow(
          databaseId: appwriteDatabaseId,
          tableId: 'transactions',
          rowId: id,
        );
        _refreshInBackground(clinicId);
        return;
      } catch (_) {
        // fall through to offline path
      }
    }

    // Offline: enqueue
    _queue.enqueue(
      table: 'transactions',
      operation: 'delete',
      rowId: id,
      data: {},
      clinicId: clinicId,
    );
    debugPrint('📥 [TransactionRepo] deleteTransaction queued offline: $id');
  }
}
