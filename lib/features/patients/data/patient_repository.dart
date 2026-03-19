import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/services/cleanup_service.dart';
import '../domain/patient.dart';
import '../domain/models/medical_record.dart';

final patientRepositoryProvider = Provider((ref) {
  return PatientRepository(ref.read(cleanupServiceProvider));
});

class PatientRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final CleanupService _cleanupService;

  PatientRepository(this._cleanupService);

  // Stream of patients for a specific clinic
  Stream<List<Patient>> getPatients(String clinicId) {
    return _firestore
        .collection('patients')
        .where('clinicId', isEqualTo: clinicId)
        .snapshots()
        .map((snapshot) {
          return snapshot.docs
              .map((doc) => Patient.fromMap(doc.data(), doc.id))
              .toList();
        });
  }

  Future<String> addPatient(Patient patient) async {
    final docRef = await _firestore.collection('patients').add(patient.toMap());
    return docRef.id;
  }

  Future<void> updatePatient(Patient patient) async {
    await _firestore
        .collection('patients')
        .doc(patient.id)
        .update(patient.toMap());
  }

  Future<void> deletePatient(Patient patient) async {
    // 1. Delete all attachments in all medical records
    for (var record in patient.records) {
      for (var url in record.attachmentUrls) {
        await _cleanupService.deleteCloudFile(url);
      }
    }

    // 2. Delete prescription image if exists
    if (patient.prescriptionImageUrl != null) {
      await _cleanupService.deleteCloudFile(patient.prescriptionImageUrl);
    }

    // 3. Delete from Firestore
    await _firestore.collection('patients').doc(patient.id).delete();
  }

  Future<void> deleteMedicalRecord(Patient patient, String recordId) async {
    final record = patient.records.firstWhere((r) => r.id == recordId);

    // 1. Delete attachments for this specific record
    for (var url in record.attachmentUrls) {
      await _cleanupService.deleteCloudFile(url);
    }

    // 2. Update patient document to remove this record
    final updatedRecords = patient.records
        .where((r) => r.id != recordId)
        .toList();
    await updatePatient(patient.copyWith(records: updatedRecords));
  }

  Future<void> addMedicalRecord(String patientId, MedicalRecord record) async {
    final patient = await getPatientById(patientId);
    if (patient == null) return;

    final updatedRecords = [...patient.records, record];
    await updatePatient(patient.copyWith(records: updatedRecords));
  }

  Future<Patient?> getPatientByName(String name, String clinicId) async {
    final snapshot = await _firestore
        .collection('patients')
        .where('clinicId', isEqualTo: clinicId)
        .where('name', isEqualTo: name)
        .limit(1)
        .get();

    if (snapshot.docs.isEmpty) return null;
    return Patient.fromMap(snapshot.docs.first.data(), snapshot.docs.first.id);
  }

  Future<Patient?> getPatientById(String id) async {
    final doc = await _firestore.collection('patients').doc(id).get();
    if (!doc.exists) return null;
    return Patient.fromMap(doc.data()!, doc.id);
  }

  Future<void> finalizeAllPendingRecords(
    String clinicId, {
    String? excludePatientId,
  }) async {
    final snapshot = await _firestore
        .collection('patients')
        .where('clinicId', isEqualTo: clinicId)
        .get();

    final batch = _firestore.batch();
    bool hasUpdates = false;

    for (final doc in snapshot.docs) {
      if (excludePatientId != null && doc.id == excludePatientId) continue;

      final data = doc.data();
      final recordsList = data['records'] as List?;
      if (recordsList == null) continue;

      bool patientUpdated = false;
      final updatedRecords = recordsList.map((r) {
        if (r['isFinalized'] == false) {
          patientUpdated = true;
          return {...r, 'isFinalized': true};
        }
        return r;
      }).toList();

      if (patientUpdated) {
        batch.update(doc.reference, {'records': updatedRecords});
        hasUpdates = true;
      }
    }

    if (hasUpdates) {
      await batch.commit();
    }
  }
}
