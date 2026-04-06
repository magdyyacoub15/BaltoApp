import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/appointment_repository.dart';
import '../../auth/presentation/auth_providers.dart';
import 'appointment.dart';
import '../../patients/domain/patients_provider.dart';
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
final appointmentsStreamProvider =
    StreamProvider<List<Appointment>>((ref) async* {
  final user = await ref.watch(currentUserProvider.future);
  if (user == null) {
    yield [];
    return;
  }

  final clinicId = user.clinicId;
  final repo = ref.watch(appointmentRepositoryProvider);
  final threshold = ref.watch(clinicVisibilityThresholdProvider);

  // Watch triggers that force a rebuild
  ref.watch(appointmentsRefreshProvider);
  ref.watch(pollingTickProvider);
  ref.watch(pageRefreshProvider);

  // 1. Yield cached data immediately
  final cached = await repo.getAppointments(clinicId);
  yield _filterAndSort(cached, threshold); // Always yield even if empty

  // 2. Fetch fresh from network in background
  try {
    final fresh = await repo.fetchLiveAppointments(clinicId);
    yield _filterAndSort(fresh, threshold); // Always yield
  } catch (_) {
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
        debugPrint("✅ [Tracer] Appointment PASS filter: ${a.id} date=${a.date.toUtc().toIso8601String()} threshold=$threshold");
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

  debugPrint("🔄 [Tracer] appointmentsStream: showing=${filtered.length}, total=${all.length} (Threshold: $threshold)");
  return filtered;
}

// ─── Enriched appointments with patient data ─────────────────────────────────
final enrichedAppointmentsProvider =
    StreamProvider<List<Appointment>>((ref) async* {
  final appointmentsAsync = ref.watch(appointmentsStreamProvider);
  final patientsAsync = ref.watch(patientsStreamProvider);

  final appointments = appointmentsAsync.value;
  final patients = patientsAsync.value;

  if (appointments == null || patients == null) {
    yield [];
    return;
  }

  final enriched = appointments.map((app) {
    final patient = patients.cast<dynamic>().firstWhere(
      (p) => p.id == app.patientId,
      orElse: () => null,
    );
    return app.copyWith(patient: patient);
  }).toList();

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
final enrichedUpcomingAppointmentsProvider = Provider<AsyncValue<List<Appointment>>>((
  ref,
) {
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

// ─── Local UI State for "In Examination" (دخول pressed) ──────────────────────
// This is PURELY local — never written to DB/cache — so it never triggers a
// queue re-sort. The set is cleared when the appointment is completed (إنهاء).
class InExaminationIdsNotifier extends Notifier<Set<String>> {
  @override
  Set<String> build() => {};

  void enter(String id) => state = {...state, id};
  void finish(String id) => state = {...state}..remove(id);
  void clear() => state = {};
}

final inExaminationIdsProvider =
    NotifierProvider<InExaminationIdsNotifier, Set<String>>(
      InExaminationIdsNotifier.new,
    );
