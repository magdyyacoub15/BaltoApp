// ignore_for_file: deprecated_member_use
import 'package:appwrite/appwrite.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../domain/appointment.dart';
import '../../../core/services/appwrite_client.dart';
import '../../../core/services/hive_cache_service.dart';
import '../../../core/services/connectivity_service.dart';
import '../../../core/services/offline_queue_service.dart';

// Tracks recently modified document IDs to prevent stale server data from overwriting local optimistic cache due to Appwrite eventual consistency.
// We ignore server data for these IDs for 15 seconds after a local write.
final Map<String, DateTime> _recentAppointmentsWrites = {};

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
        final batch = res.rows.map(
          (doc) => Appointment.fromMap(doc.data, doc.$id),
        );
        all.addAll(batch);
        if (res.rows.length < batchSize) break;
        offset += batchSize;
      }

      // Fetch current cache to preserve any optimistic inserts that haven't been indexed by server yet
      final currentCache = _cache.getCachedAppointments(clinicId) ?? [];
      final serverIds = all.map((a) => a.id).toSet();

      final now = DateTime.now();
      final recentlyWrittenIds = _recentAppointmentsWrites.keys
          .where(
            (id) =>
                now.difference(_recentAppointmentsWrites[id]!).inSeconds < 15,
          )
          .toSet();

      final missingOptimistics = currentCache.where(
        (m) =>
            (m['isOptimistic'] == true && !serverIds.contains(m['id'])) ||
            recentlyWrittenIds.contains(m['id']),
      ).toList();

      // Append optimistics and recent writes that the server hasn't returned (or returned stale)
      if (missingOptimistics.isNotEmpty) {
        // Remove potentially stale ones from server response
        final missingIds = missingOptimistics.map((m) => m['id']).toSet();
        all.removeWhere((a) => missingIds.contains(a.id));
        all.addAll(
          missingOptimistics.map((m) => Appointment.fromMap(m, m['id'] ?? '')),
        );
      }

      // Update cache with fresh data
      _cache.cacheAppointments(
        clinicId,
        all.map((a) {
          final mapped = {...a.toMap(), 'id': a.id};
          if (missingOptimistics.any((m) => m['id'] == a.id)) {
            mapped['isOptimistic'] = true;
          }
          return mapped;
        }).toList(),
      );

      return all;
    } catch (e) {
      throw Exception(
        'لا يوجد اتصال بالإنترنت. الصفحة الرئيسية تعمل فقط عند الاتصال بالشبكة.',
      );
    }
  }

  Future<List<Appointment>> refreshAppointments(String clinicId) async {
    return _fetchAndCache(clinicId);
  }

  void _refreshAppointmentsInBackground(String clinicId) {
    _fetchAndCache(clinicId).then((_) {}).catchError((e) {
      debugPrint('AppointmentRepository: bg refresh error: $e');
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
        final batch = res.rows.map(
          (doc) => Appointment.fromMap(doc.data, doc.$id),
        );
        all.addAll(batch);
        if (res.rows.length < batchSize) break;
        offset += batchSize;
      }

      // Fetch current cache to preserve any optimistic inserts that haven't been indexed by server yet
      final currentCache = _cache.getCachedAppointments(clinicId) ?? [];
      final serverIds = all.map((a) => a.id).toSet();

      final now = DateTime.now();
      final recentlyWrittenIds = _recentAppointmentsWrites.keys
          .where(
            (id) =>
                now.difference(_recentAppointmentsWrites[id]!).inSeconds < 15,
          )
          .toSet();

      final missingOptimistics = currentCache.where(
        (m) =>
            (m['isOptimistic'] == true && !serverIds.contains(m['id'])) ||
            recentlyWrittenIds.contains(m['id']),
      );

      // Merge optimistics and recent writes into the list
      if (missingOptimistics.isNotEmpty) {
        all.removeWhere((a) => recentlyWrittenIds.contains(a.id));
        all.addAll(
          missingOptimistics.map((m) => Appointment.fromMap(m, m['id'] ?? '')),
        );
      }

      _cache.cacheAppointments(
        clinicId,
        all.map((a) {
          final mapped = {...a.toMap(), 'id': a.id};
          if (missingOptimistics.any((m) => m['id'] == a.id)) {
            mapped['isOptimistic'] = true;
          }
          return mapped;
        }).toList(),
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
      // Build start/end in UTC from local date components to avoid timezone shift
      startThreshold = DateTime.utc(date.year, date.month, date.day);
      endThreshold = DateTime.utc(date.year, date.month, date.day, 23, 59, 59, 999);
    } else {
      startThreshold =
          startAfter ?? DateTime.now().subtract(const Duration(hours: 24));
      endThreshold = null;
    }

    final docs = all.where((appt) {
      final apptUtc = appt.date.toUtc();
      // Use !isBefore (>=) for start so midnight-UTC appointments are included
      final isAfterOrEqual = !apptUtc.isBefore(startThreshold.toUtc());
      final isBefore = endThreshold == null || apptUtc.isBefore(endThreshold.toUtc());
      return isAfterOrEqual && isBefore;
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
    final appointmentWithId = appointment.copyWith(id: docId);
    final data = appointmentWithId.toMap();

    debugPrint('🔵 [TRACE][addAppointment] START — docId=$docId, patientId=${appointment.patientId}, clinicId=${appointment.clinicId}');
    debugPrint('🔵 [TRACE][addAppointment] isManual=${appointment.isManual}, date=${appointment.date.toUtc().toIso8601String()}');

    // 1. Optimistic cache update — IMMEDIATE
    _applyToCache(appointmentWithId, appointment.clinicId, operation: 'create');
    debugPrint('🔵 [TRACE][addAppointment] ✅ Optimistic cache applied for docId=$docId');

    // 2. Network in background
    checkIsOnline().then((isOnline) {
      debugPrint('🔵 [TRACE][addAppointment] isOnline=$isOnline for docId=$docId');
      if (isOnline) {
        _databases
            .createRow(
              databaseId: appwriteDatabaseId,
              tableId: 'appointments',
              rowId: docId,
              data: data,
            )
            .then((_) {
              debugPrint('🔵 [TRACE][addAppointment] ✅ SERVER write SUCCESS for docId=$docId, patientId=${appointment.patientId}');
              _refreshAppointmentsInBackground(appointment.clinicId);
            })
            .catchError((e) {
              debugPrint('🔵 [TRACE][addAppointment] ❌ SERVER write FAILED for docId=$docId: $e');
              _queue.enqueue(
                table: 'appointments',
                operation: 'create',
                rowId: docId,
                data: data,
                clinicId: appointment.clinicId,
              );
              debugPrint(
                '📳 [AppointmentRepo] addAppointment queued offline: $docId',
              );
            });
      } else {
        _queue.enqueue(
          table: 'appointments',
          operation: 'create',
          rowId: docId,
          data: data,
          clinicId: appointment.clinicId,
        );
        debugPrint(
          '📳 [AppointmentRepo] addAppointment queued offline: $docId',
        );
      }
    });
  }

  Future<void> updateAppointment(Appointment appointment) async {
    final data = appointment.toMap();

    // 1. Optimistic cache update — IMMEDIATE
    _applyToCache(appointment, appointment.clinicId, operation: 'update');

    // 2. Network in background
    checkIsOnline().then((isOnline) {
      if (isOnline) {
        _databases
            .updateRow(
              databaseId: appwriteDatabaseId,
              tableId: 'appointments',
              rowId: appointment.id,
              data: data,
            )
            .then((_) {
              _refreshAppointmentsInBackground(appointment.clinicId);
            })
            .catchError((_) {
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
            });
      } else {
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
    });
  }

  Future<void> updateQueueOrder(List<Appointment> appointments) async {
    if (appointments.isEmpty) return;

    final clinicId = appointments.first.clinicId;

    // 1. Single Bulk Optimistic Update — IMMEDIATE
    final cached = _cache.getCachedAppointments(clinicId) ?? [];
    final updatedCache = List<Map<String, dynamic>>.from(cached);

    final now = DateTime.now();
    for (final appt in appointments) {
      final index = updatedCache.indexWhere((m) => m['id'] == appt.id);
      if (index != -1) {
        updatedCache[index] = {...appt.toMap(), 'id': appt.id};
      }
      _recentAppointmentsWrites[appt.id] = now;
    }

    _cache.cacheAppointments(clinicId, updatedCache);

    // 2. Parallel Network Writes in background
    checkIsOnline().then((isOnline) {
      if (isOnline) {
        Future.wait(
          appointments.map((appt) async {
            try {
              await _databases.updateRow(
                databaseId: appwriteDatabaseId,
                tableId: 'appointments',
                rowId: appt.id,
                data: appt.toMap(),
              );
            } catch (e) {
              debugPrint(
                '⚠️ [AppointmentRepo] reorder failed for ${appt.id}: $e',
              );
              _queue.enqueue(
                table: 'appointments',
                operation: 'update',
                rowId: appt.id,
                data: appt.toMap(),
                clinicId: clinicId,
              );
            }
          }),
        ).then((_) => _refreshAppointmentsInBackground(clinicId));
      } else {
        for (final appt in appointments) {
          _queue.enqueue(
            table: 'appointments',
            operation: 'update',
            rowId: appt.id,
            data: appt.toMap(),
            clinicId: clinicId,
          );
        }
      }
    });
  }

  Future<void> deleteAppointment(String id, String clinicId) async {
    // 1. Optimistic UI Update — IMMEDIATE
    final cached = _cache.getCachedAppointments(clinicId) ?? [];
    _cache.cacheAppointments(
      clinicId,
      cached.where((m) => m['id'] != id).toList(),
    );

    // 2. Network in background
    checkIsOnline().then((isOnline) {
      if (isOnline) {
        _databases
            .deleteRow(
              databaseId: appwriteDatabaseId,
              tableId: 'appointments',
              rowId: id,
            )
            .then((_) {
              _refreshAppointmentsInBackground(clinicId);
            })
            .catchError((_) {
              _queue.enqueue(
                table: 'appointments',
                operation: 'delete',
                rowId: id,
                data: {},
                clinicId: clinicId,
              );
            });
      } else {
        _queue.enqueue(
          table: 'appointments',
          operation: 'delete',
          rowId: id,
          data: {},
          clinicId: clinicId,
        );
        debugPrint(
          '📥 [AppointmentRepo] deleteAppointment queued offline: $id',
        );
      }
    });
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
      updated = [
        ...cached,
        {...appt.toMap(), 'id': appt.id, 'isOptimistic': true},
      ];
    } else {
      updated = cached.map((m) {
        if (m['id'] == appt.id) return {...appt.toMap(), 'id': appt.id};
        return m;
      }).toList();
    }
    // Record write timestamp to prevent stale data overwrite during next 15s
    _recentAppointmentsWrites[appt.id] = DateTime.now();

    _cache.cacheAppointments(clinicId, updated);
  }
}
