// ignore_for_file: deprecated_member_use
import 'package:appwrite/appwrite.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/services/cleanup_service.dart';
import '../../../core/services/hive_cache_service.dart';
import '../domain/patient.dart';
import '../domain/models/medical_record.dart';
import '../../../core/services/appwrite_client.dart';

final patientRepositoryProvider = Provider((ref) {
  return PatientRepository(
    ref.read(cleanupServiceProvider),
    ref.read(appwriteDatabasesProvider),
    ref.read(hiveCacheServiceProvider),
  );
});

class PatientRepository {
  final CleanupService _cleanupService;
  final Databases _databases;
  final HiveCacheService _cache;

  PatientRepository(this._cleanupService, this._databases, this._cache);

  /// Returns patients immediately from cache (offline-first).
  /// Fetches fresh data in background and updates cache if online.
  Future<List<Patient>> getPatients(String clinicId) async {
    // 1. Serve from cache immediately
    final cached = _cache.getCachedPatients(clinicId);
    if (cached != null) {
      _refreshPatientsInBackground(clinicId); // fire-and-forget
      return cached.map((m) => Patient.fromMap(m, m['id'] ?? '')).toList();
    }

    // 2. No cache → must fetch from network
    return _fetchAndCachePatients(clinicId);
  }

  /// Only called from UI when user explicitly requests a refresh.
  Future<List<Patient>> refreshPatients(String clinicId) async {
    return _fetchAndCachePatients(clinicId);
  }

  void _refreshPatientsInBackground(String clinicId) {
    _fetchAndCachePatients(clinicId).catchError((e) {
      debugPrint('PatientRepository: background refresh error: $e');
      return <Patient>[];
    });
  }

  Future<List<Patient>> _fetchAndCachePatients(String clinicId) async {
    try {
      final List<Patient> all = [];
      int offset = 0;
      const int batchSize = 100;

      while (true) {
        final res = await _databases.listDocuments(
          databaseId: appwriteDatabaseId,
          collectionId: 'patients',
          queries: [
            Query.equal('clinicId', clinicId),
            Query.limit(batchSize),
            Query.offset(offset),
          ],
        );
        final batch = res.documents.map((d) => Patient.fromMap(d.data, d.$id));
        all.addAll(batch);
        if (res.documents.length < batchSize) break;
        offset += batchSize;
      }

      // Update cache
      _cache.cachePatients(
        clinicId,
        all.map((p) => {...p.toMap(), 'id': p.id}).toList(),
      );
      return all;
    } catch (_) {
      // Network failed — return stale cache
      final cached = _cache.getCachedPatients(clinicId);
      return cached?.map((m) => Patient.fromMap(m, m['id'] ?? '')).toList() ??
          [];
    }
  }

  Future<String> addPatient(Patient patient) async {
    final newId = ID.unique();
    final newPatient = patient.copyWith(id: newId);

    // Optimistic Cache Update
    final cached = _cache.getCachedPatients(patient.clinicId) ?? [];
    cached.add({...newPatient.toMap(), 'id': newId});
    _cache.cachePatients(patient.clinicId, cached);

    try {
      await _databases.createDocument(
        databaseId: appwriteDatabaseId,
        collectionId: 'patients',
        documentId: newId,
        data: newPatient.toMap(),
        permissions: [
          Permission.read(Role.users()),
          Permission.write(Role.users()),
        ],
      );
    } catch (_) {}

    // Invalidate cache so next load fetches fresh in background
    _fetchAndCachePatients(patient.clinicId).catchError((_) => <Patient>[]);
    return newId;
  }

  Future<void> updatePatient(Patient patient) async {
    // Optimistic Cache Update
    final cached = _cache.getCachedPatients(patient.clinicId) ?? [];
    final index = cached.indexWhere((m) => m['id'] == patient.id);
    if (index != -1) {
      cached[index] = {...patient.toMap(), 'id': patient.id};
      _cache.cachePatients(patient.clinicId, cached);
    }

    try {
      await _databases.updateDocument(
        databaseId: appwriteDatabaseId,
        collectionId: 'patients',
        documentId: patient.id,
        data: patient.toMap(),
      );
    } catch (_) {}

    // Update cache in background
    _fetchAndCachePatients(patient.clinicId).catchError((_) => <Patient>[]);
  }

  Future<void> deletePatient(Patient patient) async {
    // 1. Optimistic Cache Update — remove patient, appointments, and transactions
    final cached = _cache.getCachedPatients(patient.clinicId) ?? [];
    cached.removeWhere((m) => m['id'] == patient.id);
    _cache.cachePatients(patient.clinicId, cached);

    // Remove related appointments from cache
    final cachedAppts = _cache.getCachedAppointments(patient.clinicId) ?? [];
    cachedAppts.removeWhere((m) => m['patientId'] == patient.id);
    _cache.cacheAppointments(patient.clinicId, cachedAppts);

    // Remove related transactions from cache
    final cachedTxns = _cache.getCachedTransactions(patient.clinicId) ?? [];
    cachedTxns.removeWhere((m) => m['patientId'] == patient.id);
    _cache.cacheTransactions(patient.clinicId, cachedTxns);

    // 2. Delete cloud-stored files (attachments, prescription image)
    for (var record in patient.records) {
      for (var url in record.attachmentUrls) {
        await _cleanupService.deleteCloudFile(url);
      }
    }
    if (patient.prescriptionImageUrl != null) {
      await _cleanupService.deleteCloudFile(patient.prescriptionImageUrl);
    }

    // 3. Delete related appointments from server
    try {
      final apptDocs = await _databases.listDocuments(
        databaseId: appwriteDatabaseId,
        collectionId: 'appointments',
        queries: [Query.equal('patientId', patient.id), Query.limit(500)],
      );
      final apptFutures = apptDocs.documents
          .map(
            (d) => _databases.deleteDocument(
              databaseId: appwriteDatabaseId,
              collectionId: 'appointments',
              documentId: d.$id,
            ),
          )
          .toList();
      await Future.wait(apptFutures);
    } catch (_) {}

    // 4. Delete related transactions from server
    // Transactions are linked by appointmentId – fetch all clinic transactions
    // and delete those whose patientId matches (if stored) OR whose
    // appointmentId belongs to the patient via the appointments we just deleted.
    // Simplest reliable approach: query by clinicId and filter in-memory.
    try {
      final txnDocs = await _databases.listDocuments(
        databaseId: appwriteDatabaseId,
        collectionId: 'transactions',
        queries: [Query.equal('clinicId', patient.clinicId), Query.limit(500)],
      );
      // Find transaction IDs that belong to appointments of this patient.
      // Since transactions store appointmentId (not patientId directly),
      // collect all appointment IDs we deleted above, then match.
      // Refetch appointment IDs from deleted docs is not possible here,
      // so we match by description pattern OR by appointmentId in cache.
      // The safest approach: delete transactions where description contains
      // the patient name AND they are recent — but that is fragile.
      // Better: re-query appointments that still exist (none after step 3)
      // and use the cachedAppts we already had before removal.
      final deletedApptIds = cachedAppts
          .map((m) => m['id']?.toString() ?? '')
          .toSet();

      final txnFutures = txnDocs.documents
          .where((d) => deletedApptIds.contains(d.data['appointmentId'] ?? ''))
          .map(
            (d) => _databases.deleteDocument(
              databaseId: appwriteDatabaseId,
              collectionId: 'transactions',
              documentId: d.$id,
            ),
          )
          .toList();
      await Future.wait(txnFutures);
    } catch (_) {}

    // 5. Delete the patient document itself
    try {
      await _databases.deleteDocument(
        databaseId: appwriteDatabaseId,
        collectionId: 'patients',
        documentId: patient.id,
      );
    } catch (_) {}

    // 6. Refresh caches in background
    _fetchAndCachePatients(patient.clinicId).catchError((_) => <Patient>[]);
  }

  Future<void> deleteMedicalRecord(Patient patient, String recordId) async {
    final record = patient.records.firstWhere((r) => r.id == recordId);
    for (var url in record.attachmentUrls) {
      await _cleanupService.deleteCloudFile(url);
    }
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
    // Try cache first
    final cached = _cache.getCachedPatients(clinicId);
    if (cached != null) {
      final found = cached.cast<Map<String, dynamic>>().firstWhere(
        (m) => (m['name'] ?? '').toString().toLowerCase() == name.toLowerCase(),
        orElse: () => {},
      );
      if (found.isNotEmpty) return Patient.fromMap(found, found['id'] ?? '');
    }

    // Fallback to network
    try {
      final snapshot = await _databases.listDocuments(
        databaseId: appwriteDatabaseId,
        collectionId: 'patients',
        queries: [
          Query.equal('clinicId', clinicId),
          Query.equal('name', name),
          Query.limit(1),
        ],
      );
      if (snapshot.documents.isEmpty) return null;
      return Patient.fromMap(
        snapshot.documents.first.data,
        snapshot.documents.first.$id,
      );
    } catch (_) {
      return null;
    }
  }

  Future<Patient?> getPatientById(String id) async {
    try {
      final doc = await _databases.getDocument(
        databaseId: appwriteDatabaseId,
        collectionId: 'patients',
        documentId: id,
      );
      return Patient.fromMap(doc.data, doc.$id);
    } catch (_) {
      return null;
    }
  }

  Future<void> finalizeAllPendingRecords(List<Patient> patients) async {
    final futures = <Future>[];
    for (final patient in patients) {
      if (patient.records.any((r) => !r.isFinalized)) {
        final patientCopy = patient.copyWith(
          records: patient.records
              .map((r) => r.isFinalized ? r : r.copyWith(isFinalized: true))
              .toList(),
        );
        futures.add(updatePatient(patientCopy));
        if (futures.length >= 490) break;
      }
    }
    if (futures.isNotEmpty) await Future.wait(futures);
  }
}
