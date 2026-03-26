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

  // 1. Yield cached data immediately
  final cached = await repo.getAppointments(clinicId);
  if (cached.isNotEmpty) yield _filterAndSort(cached, threshold);

  // 2. Fetch fresh from network in background
  try {
    final fresh = await repo.fetchLiveAppointments(clinicId);
    yield _filterAndSort(fresh, threshold);
  } catch (_) {
    // Silently ignore network errors if cache is already shown
  }
});

List<Appointment> _filterAndSort(
  List<Appointment> all,
  DateTime threshold,
) {
  final filtered = all.where((a) {
    return a.date.isAfter(threshold) || a.date.isAtSameMomentAs(threshold);
  }).toList();

  filtered.sort((a, b) {
    if (a.isCompleted && !b.isCompleted) return 1;
    if (!a.isCompleted && b.isCompleted) return -1;
    if (a.queueOrder != b.queueOrder) {
      return a.queueOrder.compareTo(b.queueOrder);
    }
    return a.date.compareTo(b.date);
  });

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
final upcomingAppointmentsStreamProvider = FutureProvider<List<Appointment>>((
  ref,
) async {
  final user = await ref.watch(currentUserProvider.future);
  final repo = ref.watch(appointmentRepositoryProvider);
  final selectedDate = ref.watch(remindersDateProvider);

  if (user != null) {
    return await repo.getAppointments(user.clinicId, date: selectedDate);
  }
  return [];
});

// ─── Enriched upcoming appointments ──────────────────────────────────────────
final enrichedUpcomingAppointmentsProvider = FutureProvider<List<Appointment>>((
  ref,
) async {
  final appointments = await ref.watch(
    upcomingAppointmentsStreamProvider.future,
  );
  final patients = await ref.watch(patientsStreamProvider.future);

  return appointments.map((app) {
    final patient = patients.cast<dynamic>().firstWhere(
      (p) => p.id == app.patientId,
      orElse: () => null,
    );
    return app.copyWith(patient: patient);
  }).toList();
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
