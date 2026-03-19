import 'package:cloud_firestore/cloud_firestore.dart';

enum TransactionType { revenue, expense }

class AppTransaction {
  final String id;
  final double amount;
  final String description;
  final TransactionType type;
  final DateTime date;
  final String clinicId;

  AppTransaction({
    required this.id,
    required this.amount,
    required this.description,
    required this.type,
    required this.date,
    required this.clinicId,
  });

  Map<String, dynamic> toMap() {
    return {
      'amount': amount,
      'description': description,
      'type': type.name,
      'date': Timestamp.fromDate(date),
      'clinicId': clinicId,
    };
  }

  factory AppTransaction.fromMap(Map<String, dynamic> map, String id) {
    return AppTransaction(
      id: id,
      amount: (map['amount'] as num).toDouble(),
      description: map['description'] ?? '',
      type: TransactionType.values.byName(map['type']),
      date: (map['date'] as Timestamp).toDate(),
      clinicId: map['clinicId'] ?? '',
    );
  }
}
