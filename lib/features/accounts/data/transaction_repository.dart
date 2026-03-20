// ignore_for_file: deprecated_member_use
import 'package:appwrite/appwrite.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../domain/transaction.dart';
import '../../../core/services/appwrite_client.dart';
import '../../../core/services/hive_cache_service.dart';
import '../../../core/services/connectivity_service.dart';

final transactionRepositoryProvider = Provider(
  (ref) => TransactionRepository(
    ref.read(appwriteDatabasesProvider),
    ref.read(hiveCacheServiceProvider),
  ),
);

class TransactionRepository {
  final Databases _databases;
  final HiveCacheService _cache;

  TransactionRepository(this._databases, this._cache);

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

      final res = await _databases.listDocuments(
        databaseId: appwriteDatabaseId,
        collectionId: 'transactions',
        queries: [Query.equal('clinicId', clinicId), Query.limit(500)],
      );

      final list = res.documents
          .map((doc) => AppTransaction.fromMap(doc.data, doc.$id))
          .toList();

      _cache.cacheTransactions(
        clinicId,
        list.map((t) => {...t.toMap(), 'id': t.id}).toList(),
      );

      list.sort((a, b) => b.date.compareTo(a.date));
      return list;
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

  Future<void> addTransaction(AppTransaction transaction) async {
    await _databases.createDocument(
      databaseId: appwriteDatabaseId,
      collectionId: 'transactions',
      documentId: ID.unique(),
      data: transaction.toMap(),
    );
    _refreshInBackground(transaction.clinicId);
  }

  Future<void> deleteTransaction(String id, String clinicId) async {
    await _databases.deleteDocument(
      databaseId: appwriteDatabaseId,
      collectionId: 'transactions',
      documentId: id,
    );
    _refreshInBackground(clinicId);
  }
}
