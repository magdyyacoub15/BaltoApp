import '../../patients/domain/patient.dart';

class Appointment {
  final String id;
  final String
  patientId; // Store ID instead of full object for easier Firestore mapping
  final Patient? patient; // Optional for UI convenience
  final DateTime date;
  final String type;
  final bool isWaiting;
  final bool isCompleted;
  final bool isManual;
  final String clinicId;
  final int queueOrder;

  Appointment({
    required this.id,
    required this.patientId,
    this.patient,
    required this.date,
    required this.type,
    required this.clinicId,
    this.isWaiting = false,
    this.isCompleted = false,
    this.isManual = false,
    this.queueOrder = 0,
  });

  factory Appointment.fromMap(
    Map<String, dynamic> data,
    String id, {
    Patient? patient,
  }) {
    return Appointment(
      id: id,
      patientId: data['patientId'] ?? '',
      patient: patient,
      date: data['date'] != null
          ? DateTime.tryParse(data['date'].toString())?.toUtc() ?? DateTime.now().toUtc()
          : DateTime.now().toUtc(),
      type: data['type'] ?? '',
      clinicId: data['clinicId'] ?? '',
      isWaiting: data['isWaiting'] ?? false,
      isCompleted: data['isCompleted'] ?? false,
      isManual: data['isManual'] ?? false,
      queueOrder: data['queueOrder'] ?? 0,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'patientId': patientId,
      'date': date.toUtc().toIso8601String(),
      'type': type,
      'clinicId': clinicId,
      'isWaiting': isWaiting,
      'isCompleted': isCompleted,
      'isManual': isManual,
      'queueOrder': queueOrder,
    };
  }

  Appointment copyWith({
    String? id,
    String? patientId,
    Patient? patient,
    DateTime? date,
    String? type,
    bool? isWaiting,
    bool? isCompleted,
    bool? isManual,
    String? clinicId,
    int? queueOrder,
  }) {
    return Appointment(
      id: id ?? this.id,
      patientId: patientId ?? this.patientId,
      patient: patient ?? this.patient,
      date: date ?? this.date,
      type: type ?? this.type,
      isWaiting: isWaiting ?? this.isWaiting,
      isCompleted: isCompleted ?? this.isCompleted,
      isManual: isManual ?? this.isManual,
      clinicId: clinicId ?? this.clinicId,
      queueOrder: queueOrder ?? this.queueOrder,
    );
  }
}
