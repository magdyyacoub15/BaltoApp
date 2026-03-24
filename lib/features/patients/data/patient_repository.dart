// ignore_for_file: deprecated_member_use
import 'dart:convert';
import 'package:appwrite/appwrite.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../../../core/services/cleanup_service.dart';
import '../../../core/services/hive_cache_service.dart';
import '../../../core/services/connectivity_service.dart';
import '../../../core/services/offline_queue_service.dart';
import '../domain/patient.dart';
import '../domain/models/medical_record.dart';
import '../../../core/services/appwrite_client.dart';

final patientRepositoryProvider = Provider((ref) {
  return PatientRepository(
    ref.read(cleanupServiceProvider),
    ref.read(appwriteTablesDBProvider),
    ref.read(hiveCacheServiceProvider),
    ref.read(offlineQueueServiceProvider),
  );
});

class PatientRepository {
  final CleanupService _cleanupService;
  final TablesDB _databases;
  final HiveCacheService _cache;
  final OfflineQueueService _queue;

  PatientRepository(
    this._cleanupService,
    this._databases,
    this._cache,
    this._queue,
  );

  /// Returns patients immediately from cache (offline-first).
  /// Fetches fresh data in background and updates cache if online.
  Future<List<Patient>> getPatients(String clinicId) async {
    final cached = _cache.getCachedPatients(clinicId);
    if (cached != null) {
      _refreshPatientsInBackground(clinicId);
      return cached.map((m) => Patient.fromMap(m, m['id'] ?? '')).toList();
    }
    return _fetchAndCachePatients(clinicId);
  }

  /// Network-only: always fetches from server, ignores cache check.
  /// Used for real-time accuracy after adds/updates.
  Future<List<Patient>> fetchLivePatients(String clinicId) async {
    try {
      final List<Patient> all = [];
      int offset = 0;
      const int batchSize = 100;

      while (true) {
        final res = await _databases.listRows(
          databaseId: appwriteDatabaseId,
          tableId: 'patients',
          queries: [
            Query.equal('clinicId', clinicId),
            Query.limit(batchSize),
            Query.offset(offset),
          ],
        );
        final batch = res.rows.map((d) => Patient.fromMap(d.data, d.$id));
        all.addAll(batch);
        if (res.rows.length < batchSize) break;
        offset += batchSize;
      }

      // Update cache with fresh data
      _cache.cachePatients(
        clinicId,
        all.map((p) => {...p.toMap(), 'id': p.id}).toList(),
      );

      return all;
    } catch (e) {
      throw Exception('لا يوجد اتصال بالإنترنت. الصفحة الرئيسية تعمل فقط عند الاتصال بالشبكة.');
    }
  }

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
        final res = await _databases.listRows(
          databaseId: appwriteDatabaseId,
          tableId: 'patients',
          queries: [
            Query.equal('clinicId', clinicId),
            Query.limit(batchSize),
            Query.offset(offset),
          ],
        );
        final batch = res.rows.map((d) => Patient.fromMap(d.data, d.$id));
        all.addAll(batch);
        if (res.rows.length < batchSize) break;
        offset += batchSize;
      }

      _cache.cachePatients(
        clinicId,
        all.map((p) => {...p.toMap(), 'id': p.id}).toList(),
      );
      return all;
    } catch (_) {
      final cached = _cache.getCachedPatients(clinicId);
      return cached?.map((m) => Patient.fromMap(m, m['id'] ?? '')).toList() ??
          [];
    }
  }

  // ─── Offline-aware Writes ──────────────────────────────────────────────────

  Future<String> addPatient(Patient patient) async {
    final docId = ID.unique(); // generate ID upfront (needed offline too)
    final data = patient.toMap();
    final isOnline = await checkIsOnline();

    if (isOnline) {
      try {
        await _databases.createRow(
          databaseId: appwriteDatabaseId,
          tableId: 'patients',
          rowId: docId,
          data: data,
        );
        await _fetchAndCachePatients(patient.clinicId);
        return docId;
      } catch (_) {
        // fall through to offline path
      }
    }

    // Offline path: apply optimistically to cache + enqueue
    _applyPatientToCache(
      patient.copyWith(id: docId),
      patient.clinicId,
      operation: 'create',
    );
    _queue.enqueue(
      table: 'patients',
      operation: 'create',
      rowId: docId,
      data: data,
      clinicId: patient.clinicId,
    );
    debugPrint('📥 [PatientRepo] addPatient queued offline: $docId');
    return docId;
  }

  Future<void> updatePatient(Patient patient) async {
    final data = patient.toMap();
    final isOnline = await checkIsOnline();

    if (isOnline) {
      try {
        await _databases.updateRow(
          databaseId: appwriteDatabaseId,
          tableId: 'patients',
          rowId: patient.id,
          data: data,
        );
        _fetchAndCachePatients(patient.clinicId).catchError((_) => <Patient>[]);
        return;
      } catch (_) {
        // fall through to offline path
      }
    }

    _applyPatientToCache(patient, patient.clinicId, operation: 'update');
    _queue.enqueue(
      table: 'patients',
      operation: 'update',
      rowId: patient.id,
      data: data,
      clinicId: patient.clinicId,
    );
    debugPrint('📥 [PatientRepo] updatePatient queued offline: ${patient.id}');
  }

  Future<void> deletePatient(Patient patient) async {
    // Always delete cloud files if accessible
    for (var record in patient.records) {
      for (var url in record.attachmentUrls) {
        await _cleanupService.deleteCloudFile(url);
      }
    }
    if (patient.prescriptionImageUrl != null) {
      await _cleanupService.deleteCloudFile(patient.prescriptionImageUrl);
    }

    final isOnline = await checkIsOnline();

    if (isOnline) {
      try {
        await _databases.deleteRow(
          databaseId: appwriteDatabaseId,
          tableId: 'patients',
          rowId: patient.id,
        );
        _fetchAndCachePatients(patient.clinicId).catchError((_) => <Patient>[]);
        return;
      } catch (_) {
        // fall through to offline path
      }
    }

    _removePatientFromCache(patient.id, patient.clinicId);
    _queue.enqueue(
      table: 'patients',
      operation: 'delete',
      rowId: patient.id,
      data: {},
      clinicId: patient.clinicId,
    );
    debugPrint('📥 [PatientRepo] deletePatient queued offline: ${patient.id}');
  }

  // ─── Medical Records (delegate to updatePatient) ──────────────────────────

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

  // ─── Queries ───────────────────────────────────────────────────────────────

  Future<Patient?> getPatientByName(String name, String clinicId) async {
    final cached = _cache.getCachedPatients(clinicId);
    if (cached != null) {
      final found = cached.cast<Map<String, dynamic>>().firstWhere(
        (m) => (m['name'] ?? '').toString().toLowerCase() == name.toLowerCase(),
        orElse: () => {},
      );
      if (found.isNotEmpty) return Patient.fromMap(found, found['id'] ?? '');
    }

    try {
      final snapshot = await _databases.listRows(
        databaseId: appwriteDatabaseId,
        tableId: 'patients',
        queries: [
          Query.equal('clinicId', clinicId),
          Query.equal('name', name),
          Query.limit(1),
        ],
      );
      if (snapshot.rows.isEmpty) return null;
      return Patient.fromMap(
        snapshot.rows.first.data,
        snapshot.rows.first.$id,
      );
    } catch (_) {
      return null;
    }
  }

  Future<Patient?> getPatientById(String id) async {
    // Check cache first — boxes store TTL-wrapped JSON
    final boxes = Hive.box<String>('patients_cache');
    for (final key in boxes.keys) {
      final raw = boxes.get(key.toString());
      if (raw == null) continue;
      try {
        final wrapper = json.decode(raw) as Map<String, dynamic>;
        // Support both new wrapped format {ts, data:[...]} and legacy plain list
        final dynamic payload = wrapper.containsKey('data')
            ? wrapper['data']
            : wrapper;
        if (payload is! List) continue;
        final list = payload.cast<Map<String, dynamic>>();
        final found = list.firstWhere(
          (m) => (m['id'] ?? '') == id,
          orElse: () => {},
        );
        if (found.isNotEmpty) return Patient.fromMap(found, found['id'] ?? '');
      } catch (_) {}
    }
    // Fallback to network
    try {
      final doc = await _databases.getRow(
        databaseId: appwriteDatabaseId,
        tableId: 'patients',
        rowId: id,
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

  // ─── Cache Helpers ─────────────────────────────────────────────────────────

  void _applyPatientToCache(
    Patient patient,
    String clinicId, {
    required String operation,
  }) {
    final cached = _cache.getCachedPatients(clinicId) ?? [];
    List<Map<String, dynamic>> updated;

    if (operation == 'create') {
      updated = [...cached, {...patient.toMap(), 'id': patient.id}];
    } else {
      updated = cached.map((m) {
        if (m['id'] == patient.id) {
          return {...patient.toMap(), 'id': patient.id};
        }
        return m;
      }).toList();
    }
    _cache.cachePatients(clinicId, updated);
  }

  void _removePatientFromCache(String patientId, String clinicId) {
    final cached = _cache.getCachedPatients(clinicId) ?? [];
    final updated = cached.where((m) => m['id'] != patientId).toList();
    _cache.cachePatients(clinicId, updated);
  }
}
