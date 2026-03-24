// ignore_for_file: deprecated_member_use
import 'package:appwrite/appwrite.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../domain/appointment.dart';
import '../../../core/services/appwrite_client.dart';
import '../../../core/services/hive_cache_service.dart';
import '../../../core/services/connectivity_service.dart';
import '../../../core/services/offline_queue_service.dart';

final appointmentRepositoryProvider = Provider(
  (ref) => AppointmentRepository(
    ref.read(appwriteTablesDBProvider),
    ref.read(hiveCacheServiceProvider),
    ref.read(offlineQueueServiceProvider),
  ),
);

class AppointmentRepository {
  final TablesDB _databases;
  final HiveCacheService _cache;
  final OfflineQueueService _queue;

  AppointmentRepository(this._databases, this._cache, this._queue);

  /// Cache-First: returns cached appointments instantly, refreshes in background.
  Future<List<Appointment>> getAppointments(
    String clinicId, {
    DateTime? date,
    DateTime? startAfter,
  }) async {
    final cached = _cache.getCachedAppointments(clinicId);

    if (cached != null) {
      _refreshAppointmentsInBackground(clinicId);
      final all = cached
          .map((m) => Appointment.fromMap(m, m['id'] ?? ''))
          .toList();
      return _filterAndSort(all, date: date, startAfter: startAfter);
    }
    return _fetchAndCache(clinicId, date: date, startAfter: startAfter);
  }

  /// Network-only: always fetches from server, ignores cache check.
  /// Used by the dashboard for real-time accuracy.
  Future<List<Appointment>> fetchLiveAppointments(String clinicId) async {
    try {
      final List<Appointment> all = [];
      int offset = 0;
      const int batchSize = 100;

      while (true) {
        final res = await _databases.listRows(
          databaseId: appwriteDatabaseId,
          tableId: 'appointments',
          queries: [
            Query.equal('clinicId', clinicId),
            Query.limit(batchSize),
            Query.offset(offset),
          ],
        );
        final batch =
            res.rows.map((doc) => Appointment.fromMap(doc.data, doc.$id));
        all.addAll(batch);
        if (res.rows.length < batchSize) break;
        offset += batchSize;
      }

      // Update cache with fresh data
      _cache.cacheAppointments(
        clinicId,
        all.map((a) => {...a.toMap(), 'id': a.id}).toList(),
      );

      return all;
    } catch (e) {
      throw Exception('لا يوجد اتصال بالإنترنت. الصفحة الرئيسية تعمل فقط عند الاتصال بالشبكة.');
    }
  }

  Future<List<Appointment>> refreshAppointments(String clinicId) async {
    return _fetchAndCache(clinicId);
  }

  void _refreshAppointmentsInBackground(String clinicId) {
    _fetchAndCache(clinicId).catchError((e) {
      debugPrint('AppointmentRepository: bg refresh error: $e');
      return <Appointment>[];
    });
  }

  Future<List<Appointment>> _fetchAndCache(
    String clinicId, {
    DateTime? date,
    DateTime? startAfter,
  }) async {
    try {
      final isOnline = await checkIsOnline();
      if (!isOnline) {
        final cached = _cache.getCachedAppointments(clinicId);
        final all =
            cached
                ?.map((m) => Appointment.fromMap(m, m['id'] ?? ''))
                .toList() ??
            [];
        return _filterAndSort(all, date: date, startAfter: startAfter);
      }

      // Paginated fetch — no hard limit
      final List<Appointment> all = [];
      int offset = 0;
      const int batchSize = 100;

      while (true) {
        final res = await _databases.listRows(
          databaseId: appwriteDatabaseId,
          tableId: 'appointments',
          queries: [
            Query.equal('clinicId', clinicId),
            Query.limit(batchSize),
            Query.offset(offset),
          ],
        );
        final batch =
            res.rows.map((doc) => Appointment.fromMap(doc.data, doc.$id));
        all.addAll(batch);
        if (res.rows.length < batchSize) break;
        offset += batchSize;
      }

      _cache.cacheAppointments(
        clinicId,
        all.map((a) => {...a.toMap(), 'id': a.id}).toList(),
      );

      return _filterAndSort(all, date: date, startAfter: startAfter);
    } catch (_) {
      final cached = _cache.getCachedAppointments(clinicId);
      final all =
          cached?.map((m) => Appointment.fromMap(m, m['id'] ?? '')).toList() ??
          [];
      return _filterAndSort(all, date: date, startAfter: startAfter);
    }
  }

  List<Appointment> _filterAndSort(
    List<Appointment> all, {
    DateTime? date,
    DateTime? startAfter,
  }) {
    final DateTime startThreshold;
    final DateTime? endThreshold;

    if (date != null) {
      startThreshold = DateTime(date.year, date.month, date.day);
      endThreshold = startThreshold.add(const Duration(days: 1));
    } else {
      startThreshold =
          startAfter ?? DateTime.now().subtract(const Duration(hours: 24));
      endThreshold = null;
    }

    final docs = all.where((appt) {
      final isAfter =
          appt.date.isAfter(startThreshold) ||
          appt.date.isAtSameMomentAs(startThreshold);
      final isBefore = endThreshold == null || appt.date.isBefore(endThreshold);
      return isAfter && isBefore;
    }).toList();

    docs.sort((a, b) {
      if (a.isCompleted && !b.isCompleted) return 1;
      if (!a.isCompleted && b.isCompleted) return -1;
      if (a.queueOrder != b.queueOrder) {
        return a.queueOrder.compareTo(b.queueOrder);
      }
      return a.date.compareTo(b.date);
    });

    return docs;
  }

  Future<List<Appointment>> getUpcomingAppointments(String clinicId) async {
    final now = DateTime.now();
    final all = await getAppointments(clinicId);
    final upcoming = all.where((appt) => appt.date.isAfter(now)).toList();
    upcoming.sort((a, b) {
      if (a.isCompleted && !b.isCompleted) return 1;
      if (!a.isCompleted && b.isCompleted) return -1;
      if (a.queueOrder != b.queueOrder) {
        return a.queueOrder.compareTo(b.queueOrder);
      }
      return a.date.compareTo(b.date);
    });
    return upcoming;
  }

  // ─── Offline-aware Writes ──────────────────────────────────────────────────

  Future<void> addAppointment(Appointment appointment) async {
    final docId = ID.unique();
    final data = appointment.toMap();
    final isOnline = await checkIsOnline();

    if (isOnline) {
      try {
        await _databases.createRow(
          databaseId: appwriteDatabaseId,
          tableId: 'appointments',
          rowId: docId,
          data: data,
        );
        _refreshAppointmentsInBackground(appointment.clinicId);
        return;
      } catch (_) {
        // fall through to offline path
      }
    }

    _applyToCache(appointment.copyWith(id: docId), appointment.clinicId,
        operation: 'create');
    _queue.enqueue(
      table: 'appointments',
      operation: 'create',
      rowId: docId,
      data: data,
      clinicId: appointment.clinicId,
    );
    debugPrint('📥 [AppointmentRepo] addAppointment queued offline: $docId');
  }

  Future<void> updateAppointment(Appointment appointment) async {
    final data = appointment.toMap();
    final isOnline = await checkIsOnline();

    if (isOnline) {
      try {
        await _databases.updateRow(
          databaseId: appwriteDatabaseId,
          tableId: 'appointments',
          rowId: appointment.id,
          data: data,
        );
        _refreshAppointmentsInBackground(appointment.clinicId);
        return;
      } catch (_) {
        // fall through to offline path
      }
    }

    _applyToCache(appointment, appointment.clinicId, operation: 'update');
    _queue.enqueue(
      table: 'appointments',
      operation: 'update',
      rowId: appointment.id,
      data: data,
      clinicId: appointment.clinicId,
    );
    debugPrint(
      '📥 [AppointmentRepo] updateAppointment queued offline: ${appointment.id}',
    );
  }

  Future<void> updateQueueOrder(List<Appointment> appointments) async {
    // Each reorder is an update — batch them
    for (final appt in appointments) {
      await updateAppointment(appt);
    }
  }

  Future<void> deleteAppointment(String id, String clinicId) async {
    final isOnline = await checkIsOnline();

    if (isOnline) {
      try {
        await _databases.deleteRow(
          databaseId: appwriteDatabaseId,
          tableId: 'appointments',
          rowId: id,
        );
        _refreshAppointmentsInBackground(clinicId);
        return;
      } catch (_) {
        // fall through to offline path
      }
    }

    final cached = _cache.getCachedAppointments(clinicId) ?? [];
    _cache.cacheAppointments(
      clinicId,
      cached.where((m) => m['id'] != id).toList(),
    );
    _queue.enqueue(
      table: 'appointments',
      operation: 'delete',
      rowId: id,
      data: {},
      clinicId: clinicId,
    );
    debugPrint('📥 [AppointmentRepo] deleteAppointment queued offline: $id');
  }

  // ─── Cache Helpers ─────────────────────────────────────────────────────────

  void _applyToCache(
    Appointment appt,
    String clinicId, {
    required String operation,
  }) {
    final cached = _cache.getCachedAppointments(clinicId) ?? [];
    List<Map<String, dynamic>> updated;

    if (operation == 'create') {
      updated = [...cached, {...appt.toMap(), 'id': appt.id}];
    } else {
      updated = cached.map((m) {
        if (m['id'] == appt.id) return {...appt.toMap(), 'id': appt.id};
        return m;
      }).toList();
    }
    _cache.cacheAppointments(clinicId, updated);
  }
}
