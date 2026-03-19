import 'package:cloud_firestore/cloud_firestore.dart';
import 'models/medical_record.dart';
import 'models/prescription.dart';

class Patient {
  final String id;
  final String name;
  final String phone;
  final DateTime dateOfBirth;
  final String medicalHistory;
  final String chronicDiseases;
  final String address;
  final DateTime lastVisit;
  final List<MedicalRecord> records;
  final List<Prescription> prescriptions;
  final String clinicId;
  final String diagnosis;
  final double paidAmount;
  final double remainingAmount;
  final String? prescriptionImageUrl;

  Patient({
    required this.id,
    required this.name,
    required this.phone,
    required this.dateOfBirth,
    required this.clinicId,
    this.medicalHistory = '',
    this.chronicDiseases = '',
    this.address = '',
    required this.lastVisit,
    this.records = const [],
    this.prescriptions = const [],
    this.diagnosis = '',
    this.paidAmount = 0.0,
    this.remainingAmount = 0.0,
    this.prescriptionImageUrl,
  });

  int get age {
    final now = DateTime.now();
    int age = now.year - dateOfBirth.year;
    if (now.month < dateOfBirth.month ||
        (now.month == dateOfBirth.month && now.day < dateOfBirth.day)) {
      age--;
    }
    return age;
  }

  factory Patient.fromMap(Map<String, dynamic> data, String id) {
    // Migration: handle old 'age' field if 'dateOfBirth' is missing
    DateTime dob;
    if (data['dateOfBirth'] != null) {
      dob = (data['dateOfBirth'] as Timestamp).toDate();
    } else {
      // Approximate DOB from age if missing
      final age = data['age'] ?? 0;
      dob = DateTime(DateTime.now().year - (age as int));
    }

    return Patient(
      id: id,
      name: data['name'] ?? '',
      phone: data['phone'] ?? '',
      dateOfBirth: dob,
      clinicId: data['clinicId'] ?? '',
      medicalHistory: data['medicalHistory'] ?? '',
      chronicDiseases: data['chronicDiseases'] ?? '',
      address: data['address'] ?? '',
      lastVisit: (data['lastVisit'] as Timestamp?)?.toDate() ?? DateTime.now(),
      records:
          (data['records'] as List<dynamic>?)
              ?.map((e) => MedicalRecord.fromMap(e as Map<String, dynamic>))
              .toList() ??
          const [],
      prescriptions:
          (data['prescriptions'] as List<dynamic>?)
              ?.map((e) => Prescription.fromMap(e as Map<String, dynamic>))
              .toList() ??
          const [],
      diagnosis: data['diagnosis'] ?? '',
      paidAmount: (data['paidAmount'] as num?)?.toDouble() ?? 0.0,
      remainingAmount: (data['remainingAmount'] as num?)?.toDouble() ?? 0.0,
      prescriptionImageUrl: data['prescriptionImageUrl'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'phone': phone,
      'dateOfBirth': Timestamp.fromDate(dateOfBirth),
      'clinicId': clinicId,
      'medicalHistory': medicalHistory,
      'chronicDiseases': chronicDiseases,
      'address': address,
      'lastVisit': Timestamp.fromDate(lastVisit),
      'records': records.map((e) => e.toMap()).toList(),
      'prescriptions': prescriptions.map((e) => e.toMap()).toList(),
      'diagnosis': diagnosis,
      'paidAmount': paidAmount,
      'remainingAmount': remainingAmount,
      'prescriptionImageUrl': prescriptionImageUrl,
    };
  }

  Patient copyWith({
    String? id,
    String? name,
    String? phone,
    DateTime? dateOfBirth,
    String? medicalHistory,
    String? chronicDiseases,
    String? address,
    DateTime? lastVisit,
    List<MedicalRecord>? records,
    List<Prescription>? prescriptions,
    String? clinicId,
    String? diagnosis,
    double? paidAmount,
    double? remainingAmount,
    String? prescriptionImageUrl,
  }) {
    return Patient(
      id: id ?? this.id,
      name: name ?? this.name,
      phone: phone ?? this.phone,
      dateOfBirth: dateOfBirth ?? this.dateOfBirth,
      medicalHistory: medicalHistory ?? this.medicalHistory,
      chronicDiseases: chronicDiseases ?? this.chronicDiseases,
      address: address ?? this.address,
      lastVisit: lastVisit ?? this.lastVisit,
      records: records ?? this.records,
      prescriptions: prescriptions ?? this.prescriptions,
      clinicId: clinicId ?? this.clinicId,
      diagnosis: diagnosis ?? this.diagnosis,
      paidAmount: paidAmount ?? this.paidAmount,
      remainingAmount: remainingAmount ?? this.remainingAmount,
      prescriptionImageUrl: prescriptionImageUrl ?? this.prescriptionImageUrl,
    );
  }
}
