import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../domain/transaction.dart';

final transactionRepositoryProvider = Provider(
  (ref) => TransactionRepository(),
);

class TransactionRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Stream<List<AppTransaction>> getTransactions(String clinicId) {
    return _firestore
        .collection('transactions')
        .where('clinicId', isEqualTo: clinicId)
        .snapshots()
        .map((snapshot) {
          final transactions = snapshot.docs
              .map((doc) => AppTransaction.fromMap(doc.data(), doc.id))
              .toList();
          transactions.sort((a, b) => b.date.compareTo(a.date));
          return transactions;
        });
  }

  Future<void> addTransaction(AppTransaction transaction) async {
    await _firestore.collection('transactions').add(transaction.toMap());
  }

  Future<void> deleteTransaction(String id) async {
    await _firestore.collection('transactions').doc(id).delete();
  }
}
