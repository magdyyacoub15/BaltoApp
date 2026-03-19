import 'package:cloud_firestore/cloud_firestore.dart';

class Medication {
  final String name;
  final String dosage;
  final String frequency;
  final String duration;
  final String instructions;

  Medication({
    required this.name,
    required this.dosage,
    required this.frequency,
    required this.duration,
    this.instructions = '',
  });

  factory Medication.fromMap(Map<String, dynamic> map) {
    return Medication(
      name: map['name'] ?? '',
      dosage: map['dosage'] ?? '',
      frequency: map['frequency'] ?? '',
      duration: map['duration'] ?? '',
      instructions: map['instructions'] ?? '',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'dosage': dosage,
      'frequency': frequency,
      'duration': duration,
      'instructions': instructions,
    };
  }
}

class Prescription {
  final String id;
  final DateTime date;
  final List<Medication> medications;
  final String doctorNotes;

  Prescription({
    required this.id,
    required this.date,
    required this.medications,
    this.doctorNotes = '',
  });

  factory Prescription.fromMap(Map<String, dynamic> map) {
    return Prescription(
      id: map['id'] ?? '',
      date: (map['date'] as Timestamp?)?.toDate() ?? DateTime.now(),
      medications:
          (map['medications'] as List<dynamic>?)
              ?.map((e) => Medication.fromMap(e as Map<String, dynamic>))
              .toList() ??
          [],
      doctorNotes: map['doctorNotes'] ?? '',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'date': Timestamp.fromDate(date),
      'medications': medications.map((e) => e.toMap()).toList(),
      'doctorNotes': doctorNotes,
    };
  }
}
