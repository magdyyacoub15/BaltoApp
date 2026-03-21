// ignore_for_file: deprecated_member_use
import 'package:appwrite/appwrite.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../domain/appointment.dart';
import '../../../core/services/appwrite_client.dart';
import '../../../core/services/hive_cache_service.dart';
import '../../../core/services/connectivity_service.dart';

final appointmentRepositoryProvider = Provider(
  (ref) => AppointmentRepository(
    ref.read(appwriteDatabasesProvider),
    ref.read(hiveCacheServiceProvider),
  ),
);

class AppointmentRepository {
  final Databases _databases;
  final HiveCacheService _cache;

  AppointmentRepository(this._databases, this._cache);

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

      final res = await _databases.listDocuments(
        databaseId: appwriteDatabaseId,
        collectionId: 'appointments',
        queries: [Query.equal('clinicId', clinicId), Query.limit(250)],
      );

      final all = res.documents
          .map((doc) => Appointment.fromMap(doc.data, doc.$id))
          .toList();

      // Store in cache with ID
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

  Future<String> addAppointment(Appointment appointment) async {
    final newId = ID.unique();
    final newAppt = appointment.copyWith(id: newId);

    // 1. Optimistic Cache Update
    final cached = _cache.getCachedAppointments(appointment.clinicId) ?? [];
    cached.add({...newAppt.toMap(), 'id': newId});
    _cache.cacheAppointments(appointment.clinicId, cached);

    // 2. Network Request
    try {
      await _databases.createDocument(
        databaseId: appwriteDatabaseId,
        collectionId: 'appointments',
        documentId: newId,
        data: newAppt.toMap(),
      );
    } catch (_) {
      // Offline fallback: The background sync will eventually handle this
    }

    // 3. Keep cache in sync in the background
    _refreshAppointmentsInBackground(appointment.clinicId);
    return newId;
  }

  Future<void> updateAppointment(Appointment appointment) async {
    // 1. Optimistic Cache Update
    final cached = _cache.getCachedAppointments(appointment.clinicId) ?? [];
    final index = cached.indexWhere((m) => m['id'] == appointment.id);
    if (index != -1) {
      cached[index] = {...appointment.toMap(), 'id': appointment.id};
      _cache.cacheAppointments(appointment.clinicId, cached);
    }

    // 2. Network Request
    try {
      await _databases.updateDocument(
        databaseId: appwriteDatabaseId,
        collectionId: 'appointments',
        documentId: appointment.id,
        data: appointment.toMap(),
      );
    } catch (_) {}

    _refreshAppointmentsInBackground(appointment.clinicId);
  }

  Future<void> updateQueueOrder(List<Appointment> appointments) async {
    final futures = <Future>[];
    for (final appt in appointments) {
      futures.add(
        _databases.updateDocument(
          databaseId: appwriteDatabaseId,
          collectionId: 'appointments',
          documentId: appt.id,
          data: {'queueOrder': appt.queueOrder},
        ),
      );
    }
    await Future.wait(futures);
    if (appointments.isNotEmpty) {
      _refreshAppointmentsInBackground(appointments.first.clinicId);
    }
  }

  Future<void> deleteAppointment(String id, String clinicId) async {
    // 1. Optimistic Cache Update
    final cached = _cache.getCachedAppointments(clinicId) ?? [];
    cached.removeWhere((m) => m['id'] == id);
    _cache.cacheAppointments(clinicId, cached);

    // 2. Network Request
    try {
      await _databases.deleteDocument(
        databaseId: appwriteDatabaseId,
        collectionId: 'appointments',
        documentId: id,
      );
    } catch (_) {}

    _refreshAppointmentsInBackground(clinicId);
  }
}
