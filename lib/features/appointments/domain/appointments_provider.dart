import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/appointment_repository.dart';
import '../../auth/presentation/auth_providers.dart';
import 'appointment.dart';
import '../../patients/domain/patients_provider.dart';
import '../../patients/data/patient_repository.dart';
import '../../../core/services/polling_service.dart';

// ─── Manual Refresh Trigger ──────────────────────────────────────────────────
class AppointmentsRefreshNotifier extends Notifier<int> {
  @override
  int build() => 0;
  void refresh() => state++;
}

final appointmentsRefreshProvider =
    NotifierProvider<AppointmentsRefreshNotifier, int>(
      AppointmentsRefreshNotifier.new,
    );

// ─── Appointments Stream Provider ────────────────────────────────────────────
final appointmentsStreamProvider = StreamProvider<List<Appointment>>((
  ref,
) async* {
  final user = await ref.watch(currentUserProvider.future);
  if (user == null) {
    debugPrint('🔴 [TRACE][appointmentsStream] user is NULL → yielding empty');
    yield [];
    return;
  }

  final clinicId = user.clinicId;
  debugPrint(
    '🔵 [TRACE][appointmentsStream] START — userId=${user.id}, clinicId=$clinicId',
  );
  final repo = ref.watch(appointmentRepositoryProvider);
  final threshold = ref.watch(clinicVisibilityThresholdProvider);
  debugPrint(
    '🔵 [TRACE][appointmentsStream] threshold=${threshold.toIso8601String()}',
  );

  // Watch triggers that force a rebuild
  final refreshTick = ref.watch(appointmentsRefreshProvider);
  final pollTick = ref.watch(pollingTickProvider).value ?? -1;
  final pageTick = ref.watch(pageRefreshProvider);
  debugPrint(
    '🔵 [TRACE][appointmentsStream] triggers → refresh=$refreshTick, poll=$pollTick, page=$pageTick',
  );

  // 1. Yield cached data immediately
  final cached = await repo.getAppointments(clinicId);
  debugPrint('🔵 [TRACE][appointmentsStream] CACHED: total=${cached.length}');
  final cachedFiltered = _filterAndSort(cached, threshold);
  debugPrint(
    '🔵 [TRACE][appointmentsStream] CACHED after filter: showing=${cachedFiltered.length}',
  );
  for (final a in cachedFiltered) {
    debugPrint(
      '  📋 [TRACE] appt id=${a.id}, patientId=${a.patientId}, isManual=${a.isManual}, date=${a.date.toUtc().toIso8601String()}',
    );
  }
  yield cachedFiltered;

  // 2. Fetch fresh from network in background
  try {
    debugPrint('🌐 [TRACE][appointmentsStream] Fetching LIVE from server...');
    final fresh = await repo.fetchLiveAppointments(clinicId);
    debugPrint('🌐 [TRACE][appointmentsStream] LIVE: total=${fresh.length}');
    final freshFiltered = _filterAndSort(fresh, threshold);
    debugPrint(
      '🌐 [TRACE][appointmentsStream] LIVE after filter: showing=${freshFiltered.length}',
    );
    for (final a in freshFiltered) {
      debugPrint(
        '  📋 [TRACE] live appt id=${a.id}, patientId=${a.patientId}, isManual=${a.isManual}',
      );
    }
    yield freshFiltered;
  } catch (e) {
    debugPrint('🔴 [TRACE][appointmentsStream] LIVE fetch error: $e');
    // Silently ignore network errors if cache is already shown
  }
});

List<Appointment> _filterAndSort(List<Appointment> all, DateTime threshold) {
  // Show manual appointments that are after the manual shift reset (threshold)
  final filtered = all.where((a) {
    bool isAfterThresh = a.date.toUtc().isAfter(threshold);
    if (!isAfterThresh && a.isManual) {
      // debugPrint("⚠️ [Tracer] Appointment filtered out: ${a.id} date=${a.date.toIso8601String()} threshold=$threshold");
    }
    if (isAfterThresh && a.isManual) {
      debugPrint(
        "✅ [Tracer] Appointment PASS filter: ${a.id} date=${a.date.toUtc().toIso8601String()} threshold=$threshold",
      );
    }
    return a.isManual && isAfterThresh;
  }).toList();

  filtered.sort((a, b) {
    // Completed items always go to the bottom
    if (a.isCompleted && !b.isCompleted) return 1;
    if (!a.isCompleted && b.isCompleted) return -1;

    // Sort by queue order or date (isWaiting state does NOT affect position)
    if (a.queueOrder != b.queueOrder) {
      return a.queueOrder.compareTo(b.queueOrder);
    }
    return a.date.compareTo(b.date);
  });

  debugPrint(
    "🔄 [Tracer] appointmentsStream: showing=${filtered.length}, total=${all.length} (Threshold: $threshold)",
  );
  return filtered;
}

// ─── Enriched appointments with patient data ─────────────────────────────────
final enrichedAppointmentsProvider = StreamProvider<List<Appointment>>((
  ref,
) async* {
  final appointmentsAsync = ref.watch(appointmentsStreamProvider);
  final patientsAsync = ref.watch(patientsStreamProvider);

  final appointments = appointmentsAsync.value;
  final patients = patientsAsync.value;

  debugPrint(
    '🟡 [TRACE][enrichedAppointments] appts=${appointments?.length ?? 'null'}, patients=${patients?.length ?? 'null'}',
  );
  debugPrint(
    '🟡 [TRACE][enrichedAppointments] apptState=${appointmentsAsync.runtimeType}, patientState=${patientsAsync.runtimeType}',
  );

  if (appointments == null || patients == null) {
    debugPrint(
      '🔴 [TRACE][enrichedAppointments] One is null → yielding empty. appts=${appointments == null ? 'NULL' : 'ok'}, patients=${patients == null ? 'NULL' : 'ok'}',
    );
    yield [];
    return;
  }

  final patientMap = {for (final p in patients) p.id: p};
  debugPrint(
    '🟡 [TRACE][enrichedAppointments] available patientIds: ${patientMap.length}',
  );

  // --- FIX: Detect missing patients and fetch them directly from server ---
  final missingPatientIds = appointments
      .map((a) => a.patientId)
      .where((id) => id.isNotEmpty && !patientMap.containsKey(id))
      .toSet();

  if (missingPatientIds.isNotEmpty) {
    debugPrint(
      '🔴 [TRACE][enriched] Found ${missingPatientIds.length} MISSING patients → fetching from server: $missingPatientIds',
    );
    final patientRepo = ref.read(patientRepositoryProvider);
    final fetchFutures = missingPatientIds.map(
      (id) => patientRepo.getPatientById(id),
    );
    final fetched = await Future.wait(fetchFutures);

    // Check if the provider is still mounted after the async gap
    if (!ref.mounted) {
      debugPrint(
        '🔴 [TRACE][enriched] Provider was disposed during fetch. Aborting.',
      );
      return;
    }

    for (final p in fetched) {
      if (p != null) {
        patientMap[p.id] = p;
        debugPrint(
          '  ✅ [TRACE][enriched] Fetched missing patient from server: id=${p.id}, name=${p.name}',
        );
        // Also trigger patients refresh so next poll has the data in cache
        ref.read(patientsRefreshProvider.notifier).refresh();
      } else {
        debugPrint(
          '  ❌ [TRACE][enriched] Patient still NOT FOUND even after server fetch!',
        );
      }
    }
  }

  // Check again before yielding
  if (!ref.mounted) return;

  final enriched = appointments.map((app) {
    final patient = patientMap[app.patientId];
    if (patient == null) {
      debugPrint(
        '  ❌ [TRACE][enriched] appt id=${app.id} → patientId=${app.patientId} NOT FOUND (even after server fetch!)',
      );
    } else {
      debugPrint(
        '  ✅ [TRACE][enriched] appt id=${app.id} → patientId=${app.patientId} MATCHED: name=${patient.name}',
      );
    }
    return app.copyWith(patient: patient);
  }).toList();

  debugPrint(
    '🟡 [TRACE][enrichedAppointments] yielding ${enriched.length} enriched appts',
  );
  yield enriched;
});

// Stats Providers
final todayAppointmentsCountProvider = Provider<int>((ref) {
  final val = ref.watch(appointmentsStreamProvider).value;
  return val?.length ?? 0;
});

final waitingPatientsCountProvider = Provider<int>((ref) {
  final val = ref.watch(appointmentsStreamProvider).value;
  return val?.where((a) => a.isWaiting).length ?? 0;
});

// ─── Date filter for reminders ────────────────────────────────────────────────
class RemindersDateNotifier extends Notifier<DateTime> {
  @override
  DateTime build() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day).add(const Duration(days: 1));
  }

  void setDate(DateTime date) => state = date;
}

final remindersDateProvider = NotifierProvider<RemindersDateNotifier, DateTime>(
  RemindersDateNotifier.new,
);

// ─── Upcoming appointments ────────────────────────────────────────────────────
final upcomingAppointmentsStreamProvider = StreamProvider<List<Appointment>>((
  ref,
) async* {
  final user = await ref.watch(currentUserProvider.future);
  if (user == null) {
    yield [];
    return;
  }

  final repo = ref.watch(appointmentRepositoryProvider);
  final selectedDate = ref.watch(remindersDateProvider);

  ref.watch(appointmentsRefreshProvider);
  ref.watch(pollingTickProvider);
  ref.watch(pageRefreshProvider);

  // Yield cached immediately to avoid loading flicker
  yield await repo.getAppointments(user.clinicId, date: selectedDate);
});

// ─── Enriched upcoming appointments ──────────────────────────────────────────
final enrichedUpcomingAppointmentsProvider =
    Provider<AsyncValue<List<Appointment>>>((ref) {
      final appointmentsAsync = ref.watch(upcomingAppointmentsStreamProvider);
      final patientsAsync = ref.watch(patientsStreamProvider);

      final appointments = appointmentsAsync.value;
      final patients = patientsAsync.value;

      if (appointments == null || patients == null) {
        // If either hasn't loaded its first frame, show loading
        return const AsyncLoading();
      }

      final enriched = appointments.map((app) {
        final patient = patients.cast<dynamic>().firstWhere(
          (p) => p.id == app.patientId,
          orElse: () => null,
        );
        return app.copyWith(patient: patient);
      }).toList();

      return AsyncData(enriched);
    });

// ─── Local UI State for Dismissed Items ───────────────────────────────────────
class RemovedAppointmentIdsNotifier extends Notifier<Set<String>> {
  @override
  Set<String> build() => {};

  void add(String id) => state = {...state, id};
  void clear() => state = {};
}

final removedAppointmentIdsProvider =
    NotifierProvider<RemovedAppointmentIdsNotifier, Set<String>>(
      RemovedAppointmentIdsNotifier.new,
    );
