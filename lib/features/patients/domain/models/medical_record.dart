import 'prescription.dart';

class VitalSigns {
  // ... existing VitalSigns code ...
  final String bloodPressure;
  final double weight;
  final double temperature;
  final double sugarLevel;

  VitalSigns({
    required this.bloodPressure,
    required this.weight,
    required this.temperature,
    required this.sugarLevel,
  });

  factory VitalSigns.fromMap(Map<String, dynamic> map) {
    return VitalSigns(
      bloodPressure: map['bloodPressure'] ?? '',
      weight: (map['weight'] as num?)?.toDouble() ?? 0.0,
      temperature: (map['temperature'] as num?)?.toDouble() ?? 0.0,
      sugarLevel: (map['sugarLevel'] as num?)?.toDouble() ?? 0.0,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'bloodPressure': bloodPressure,
      'weight': weight,
      'temperature': temperature,
      'sugarLevel': sugarLevel,
    };
  }
}

class MedicalRecord {
  final String id;
  final DateTime date;
  final String diagnosis;
  final String doctorNotes;
  final VitalSigns? vitalSigns;
  final List<String> attachmentUrls;
  final List<Medication> medications;
  final double paidAmount;
  final double remainingAmount;
  final String? parentRecordId;
  final bool isFinalized;

  MedicalRecord({
    required this.id,
    required this.date,
    required this.diagnosis,
    required this.doctorNotes,
    this.vitalSigns,
    this.attachmentUrls = const [],
    this.medications = const [],
    this.paidAmount = 0.0,
    this.remainingAmount = 0.0,
    this.parentRecordId,
    this.isFinalized = false,
  });

  factory MedicalRecord.fromMap(Map<String, dynamic> map) {
    return MedicalRecord(
      id: map['id'] ?? '',
      date: map['date'] != null
          ? DateTime.tryParse(map['date'].toString()) ?? DateTime.now()
          : DateTime.now(),
      diagnosis: map['diagnosis'] ?? '',
      doctorNotes: map['doctorNotes'] ?? '',
      vitalSigns: map['vitalSigns'] != null
          ? VitalSigns.fromMap(map['vitalSigns'] as Map<String, dynamic>)
          : null,
      attachmentUrls: List<String>.from(map['attachmentUrls'] ?? []),
      medications:
          (map['medications'] as List<dynamic>?)
              ?.map((e) => Medication.fromMap(e as Map<String, dynamic>))
              .toList() ??
          const [],
      paidAmount: (map['paidAmount'] as num?)?.toDouble() ?? 0.0,
      remainingAmount: (map['remainingAmount'] as num?)?.toDouble() ?? 0.0,
      parentRecordId: map['parentRecordId'],
      isFinalized: map['isFinalized'] ?? false,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'date': date.toIso8601String(),
      'diagnosis': diagnosis,
      'doctorNotes': doctorNotes,
      'vitalSigns': vitalSigns?.toMap(),
      'attachmentUrls': attachmentUrls,
      'medications': medications.map((e) => e.toMap()).toList(),
      'paidAmount': paidAmount,
      'remainingAmount': remainingAmount,
      'parentRecordId': parentRecordId,
      'isFinalized': isFinalized,
    };
  }

  MedicalRecord copyWith({
    String? id,
    DateTime? date,
    String? diagnosis,
    String? doctorNotes,
    VitalSigns? vitalSigns,
    List<String>? attachmentUrls,
    List<Medication>? medications,
    double? paidAmount,
    double? remainingAmount,
    String? parentRecordId,
    bool? isFinalized,
  }) {
    return MedicalRecord(
      id: id ?? this.id,
      date: date ?? this.date,
      diagnosis: diagnosis ?? this.diagnosis,
      doctorNotes: doctorNotes ?? this.doctorNotes,
      vitalSigns: vitalSigns ?? this.vitalSigns,
      attachmentUrls: attachmentUrls ?? this.attachmentUrls,
      medications: medications ?? this.medications,
      paidAmount: paidAmount ?? this.paidAmount,
      remainingAmount: remainingAmount ?? this.remainingAmount,
      parentRecordId: parentRecordId ?? this.parentRecordId,
      isFinalized: isFinalized ?? this.isFinalized,
    );
  }
}
