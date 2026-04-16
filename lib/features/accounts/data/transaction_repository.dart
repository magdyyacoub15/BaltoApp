// ignore_for_file: deprecated_member_use
import 'package:appwrite/appwrite.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../domain/transaction.dart';
import '../../../core/services/appwrite_client.dart';
import '../../../core/services/hive_cache_service.dart';
import '../../../core/services/connectivity_service.dart';
import '../../../core/services/offline_queue_service.dart';

// Tracks recently modified document IDs to prevent stale server data from overwriting local optimistic cache due to Appwrite eventual consistency.
final Map<String, DateTime> _recentTransactionWrites = {};

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
    debugPrint("🔄 [Tracer] TransactionRepo.getTransactions: cache found = ${cached != null}, length = ${cached?.length}");
    if (cached != null) {
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
      final Set<String> serverIds = {};
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
        for (var doc in res.rows) {
          final trans = AppTransaction.fromMap(doc.data, doc.$id);
          all.add(trans);
          serverIds.add(trans.id);
        }
        if (res.rows.length < batchSize) break;
        offset += batchSize;
      }

      final currentCache = _cache.getCachedTransactions(clinicId) ?? [];
      final now = DateTime.now();
      final recentlyWrittenIds = _recentTransactionWrites.keys
          .where((id) => now.difference(_recentTransactionWrites[id]!).inSeconds < 15)
          .toSet();

      final missingOptimistics = currentCache.where(
        (m) =>
            (m['isOptimistic'] == true && !serverIds.contains(m['id'])) ||
            recentlyWrittenIds.contains(m['id']),
      ).toList();

      debugPrint("🔄 [Tracer] fetchLiveTransactions: all from server length=${all.length}");
      debugPrint("🔄 [Tracer] fetchLiveTransactions: missingOptimistics length=${missingOptimistics.length}");

      if (missingOptimistics.isNotEmpty) {
        final missingIds = missingOptimistics.map((m) => m['id']).toSet();
        all.removeWhere((t) => missingIds.contains(t.id));
        all.addAll(missingOptimistics.map((m) => AppTransaction.fromMap(m, m['id'] ?? '')));
      }

      _cache.cacheTransactions(
        clinicId,
        all.map((t) {
          final mapped = {...t.toMap(), 'id': t.id};
          if (missingOptimistics.any((m) => m['id'] == t.id)) {
            mapped['isOptimistic'] = true;
          }
          return mapped;
        }).toList(),
      );
      debugPrint("🔄 [Tracer] fetchLiveTransactions: cached length=${all.length}");

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
    _fetchAndCache(clinicId).then((_) {}).catchError((e) {
      debugPrint('TransactionRepository: bg error: $e');
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
      final Set<String> serverIds = {};
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
        for (var doc in res.rows) {
          serverIds.add(doc.$id);
        }
        if (res.rows.length < batchSize) break;
        offset += batchSize;
      }

      final currentCache = _cache.getCachedTransactions(clinicId) ?? [];
      final now = DateTime.now();
      final recentlyWrittenIds = _recentTransactionWrites.keys
          .where((id) => now.difference(_recentTransactionWrites[id]!).inSeconds < 15)
          .toSet();

      final missingOptimistics = currentCache.where(
        (m) =>
            (m['isOptimistic'] == true && !serverIds.contains(m['id'])) ||
            recentlyWrittenIds.contains(m['id']),
      ).toList();

      debugPrint("🔄 [Tracer] fetchLiveTransactions: all from server length=${all.length}");
      debugPrint("🔄 [Tracer] fetchLiveTransactions: missingOptimistics length=${missingOptimistics.length}");

      if (missingOptimistics.isNotEmpty) {
        // Remove stale ones from server response
        final missingIds = missingOptimistics.map((m) => m['id']).toSet();
        all.removeWhere((t) => missingIds.contains(t.id));
        all.addAll(missingOptimistics.map((m) => AppTransaction.fromMap(m, m['id'] ?? '')));
      }

      _cache.cacheTransactions(
        clinicId,
        all.map((t) {
          final mapped = {...t.toMap(), 'id': t.id};
          if (missingOptimistics.any((m) => m['id'] == t.id)) {
            mapped['isOptimistic'] = true;
          }
          return mapped;
        }).toList(),
      );
      debugPrint("🔄 [Tracer] fetchLiveTransactions: cached length=${all.length}");

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

    // 1. Optimistic cache update — IMMEDIATE
    _recentTransactionWrites[docId] = DateTime.now();
    debugPrint("🔄 [Tracer] addTransaction: docId=$docId, amount=${transaction.amount}");
    final cached = _cache.getCachedTransactions(transaction.clinicId) ?? [];
    _cache.cacheTransactions(transaction.clinicId, [
      ...cached,
      {...data, 'id': docId, 'isOptimistic': true},
    ]);
    debugPrint("🔄 [Tracer] addTransaction: cache updated to length ${cached.length + 1}");

    // 2. Network sync in background (fire-and-forget)
    checkIsOnline().then((isOnline) {
      if (isOnline) {
        _tryCreateTransactionWithPermissions(docId, data, transaction.clinicId, useTeam: true);
      } else {
        _queue.enqueue(
          table: 'transactions',
          operation: 'create',
          rowId: docId,
          data: data,
          clinicId: transaction.clinicId,
        );
        debugPrint('📥 [TransactionRepo] addTransaction queued offline: $docId');
      }
    });

    return docId; // returns INSTANTLY
  }

  void _tryCreateTransactionWithPermissions(String docId, Map<String, dynamic> data, String clinicId, {required bool useTeam}) {
    final permissions = useTeam
        ? [
            Permission.read(Role.team(clinicId)),
            Permission.update(Role.team(clinicId)),
            Permission.delete(Role.team(clinicId, 'admin')),
          ]
        : [
            Permission.read(Role.users()),
            Permission.update(Role.users()),
            Permission.delete(Role.users()),
          ];

    _databases.createRow(
      databaseId: appwriteDatabaseId,
      tableId: 'transactions',
      rowId: docId,
      data: data,
      permissions: permissions,
    ).then((_) {
      _refreshInBackground(clinicId);
    }).catchError((e) {
      final errStr = e.toString();
      if (useTeam && errStr.contains('user_unauthorized')) {
        debugPrint('⚠️ [TransactionRepo] team perm denied, retrying with users() for docId=$docId');
        _tryCreateTransactionWithPermissions(docId, data, clinicId, useTeam: false);
      } else {
        _queue.enqueue(
          table: 'transactions',
          operation: 'create',
          rowId: docId,
          data: data,
          clinicId: clinicId,
        );
        debugPrint('📥 [TransactionRepo] addTransaction queued offline: $docId');
      }
    });
  }


  Future<void> updateTransaction(String id, AppTransaction transaction) async {
    final data = transaction.toMap();

    // 1. Optimistic cache update — IMMEDIATE
    _recentTransactionWrites[id] = DateTime.now();
    final cached = _cache.getCachedTransactions(transaction.clinicId) ?? [];
    final index = cached.indexWhere((m) => m['id'] == id);
    if (index != -1) {
      cached[index] = {...data, 'id': id, 'isOptimistic': true};
      _cache.cacheTransactions(transaction.clinicId, cached);
    }

    // 2. Network sync in background (fire-and-forget)
    checkIsOnline().then((isOnline) {
      if (isOnline) {
        _databases
            .updateRow(
          databaseId: appwriteDatabaseId,
          tableId: 'transactions',
          rowId: id,
          data: data,
        )
            .then((_) {
          _refreshInBackground(transaction.clinicId);
        }).catchError((_) {
          _queue.enqueue(
            table: 'transactions',
            operation: 'update',
            rowId: id,
            data: data,
            clinicId: transaction.clinicId,
          );
          debugPrint('📥 [TransactionRepo] updateTransaction queued offline: $id');
        });
      } else {
        _queue.enqueue(
          table: 'transactions',
          operation: 'update',
          rowId: id,
          data: data,
          clinicId: transaction.clinicId,
        );
        debugPrint('📥 [TransactionRepo] updateTransaction queued offline: $id');
      }
    });
  }

  Future<void> deleteTransaction(String id, String clinicId) async {
    // 1. Optimistic UI update — IMMEDIATE
    final cached = _cache.getCachedTransactions(clinicId) ?? [];
    if (cached.isNotEmpty) {
      _cache.cacheTransactions(
        clinicId,
        cached.where((m) => m['id'] != id).toList(),
      );
    }

    // 2. Network sync in background (fire-and-forget)
    checkIsOnline().then((isOnline) {
      if (isOnline) {
        _databases
            .deleteRow(
          databaseId: appwriteDatabaseId,
          tableId: 'transactions',
          rowId: id,
        )
            .then((_) {
          _refreshInBackground(clinicId);
        }).catchError((_) {
          _queue.enqueue(
            table: 'transactions',
            operation: 'delete',
            rowId: id,
            data: {},
            clinicId: clinicId,
          );
        });
      } else {
        _queue.enqueue(
          table: 'transactions',
          operation: 'delete',
          rowId: id,
          data: {},
          clinicId: clinicId,
        );
        debugPrint('📥 [TransactionRepo] deleteTransaction queued offline: $id');
      }
    });
  }
}
