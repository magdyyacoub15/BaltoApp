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
    final newId = ID.unique();
    final newTransaction = AppTransaction(
      id: newId,
      amount: transaction.amount,
      description: transaction.description,
      type: transaction.type,
      date: transaction.date,
      clinicId: transaction.clinicId,
      appointmentId: transaction.appointmentId,
    );

    // Optimistic Cache Update
    final cached = _cache.getCachedTransactions(transaction.clinicId) ?? [];
    cached.add({...newTransaction.toMap(), 'id': newId});
    _cache.cacheTransactions(transaction.clinicId, cached);

    try {
      await _databases.createDocument(
        databaseId: appwriteDatabaseId,
        collectionId: 'transactions',
        documentId: newId,
        data: newTransaction.toMap(),
      );
    } catch (_) {}
    _refreshInBackground(transaction.clinicId);
  }

  Future<void> deleteTransaction(String id, String clinicId) async {
    // Optimistic Cache Update
    final cached = _cache.getCachedTransactions(clinicId) ?? [];
    cached.removeWhere((m) => m['id'] == id);
    _cache.cacheTransactions(clinicId, cached);

    try {
      await _databases.deleteDocument(
        databaseId: appwriteDatabaseId,
        collectionId: 'transactions',
        documentId: id,
      );
    } catch (_) {}
    _refreshInBackground(clinicId);
  }

  Future<void> deleteTransactionByAppointmentId(
    String appointmentId,
    String clinicId,
  ) async {
    // Optimistic Cache Update
    final cached = _cache.getCachedTransactions(clinicId) ?? [];
    cached.removeWhere((m) => m['appointmentId'] == appointmentId);
    _cache.cacheTransactions(clinicId, cached);

    // Network Request without creating index in Appwrite
    try {
      final res = await _databases.listDocuments(
        databaseId: appwriteDatabaseId,
        collectionId: 'transactions',
        queries: [Query.equal('clinicId', clinicId), Query.limit(500)],
      );

      final docsToDelete = res.documents
          .where((d) => d.data['appointmentId'] == appointmentId)
          .toList();

      final futures = <Future>[];
      for (final doc in docsToDelete) {
        futures.add(
          _databases.deleteDocument(
            databaseId: appwriteDatabaseId,
            collectionId: 'transactions',
            documentId: doc.$id,
          ),
        );
      }
      await Future.wait(futures);
    } catch (_) {}

    _refreshInBackground(clinicId);
  }
}
