enum TransactionType { revenue, expense }

class AppTransaction {
  final String id;
  final double amount;
  final String description;
  final TransactionType type;
  final DateTime date;
  final String clinicId;
  final String? appointmentId;

  AppTransaction({
    required this.id,
    required this.amount,
    required this.description,
    required this.type,
    required this.date,
    required this.clinicId,
    this.appointmentId,
  });

  Map<String, dynamic> toMap() {
    return {
      'amount': amount,
      'description': description,
      'type': type.name,
      'date': date.toIso8601String(),
      'clinicId': clinicId,
      if (appointmentId != null) 'appointmentId': appointmentId,
    };
  }

  factory AppTransaction.fromMap(Map<String, dynamic> map, String id) {
    return AppTransaction(
      id: id,
      amount: (map['amount'] as num).toDouble(),
      description: map['description'] ?? '',
      type: TransactionType.values.byName(map['type']),
      date: map['date'] != null
          ? DateTime.tryParse(map['date'].toString()) ?? DateTime.now()
          : DateTime.now(),
      clinicId: map['clinicId'] ?? '',
      appointmentId: map['appointmentId'],
    );
  }
}
