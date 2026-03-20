import 'dart:async';
import 'package:appwrite/appwrite.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/appointment_repository.dart';
import '../../auth/presentation/auth_providers.dart';
import '../domain/appointment.dart';
import '../../patients/domain/patients_provider.dart';
import '../../../core/services/appwrite_client.dart';

// ─── Appwrite Realtime Client Provider ───────────────────────────────────────
final appwriteRealtimeProvider = Provider<Realtime>((ref) {
  final client = ref.watch(appwriteClientProvider);
  return Realtime(client);
});

// ─── Realtime Appointments Stream Provider (for Dashboard) ───────────────────
// Listens to Appwrite Realtime and emits a fresh list whenever any appointment
// document is created, updated, or deleted in the current clinic.
final appointmentsStreamProvider = StreamProvider<List<Appointment>>((ref) {
  final userAsync = ref.watch(authStateProvider);
  final user = userAsync.value;
  if (user == null) return Stream.value([]);

  final realtime = ref.watch(appwriteRealtimeProvider);
  final repo = ref.watch(appointmentRepositoryProvider);

  // Controller to emit lists
  final controller = StreamController<List<Appointment>>();

  // Fetch current user's clinicId
  Future<String?> getClinicId() async {
    final appUser = await ref.read(currentUserProvider.future);
    return appUser?.clinicId;
  }

  // Initial load from cache/network
  getClinicId().then((clinicId) async {
    if (clinicId == null) return;

    // Emit initial data (from cache or network)
    final threshold = await ref.read(clinicVisibilityThresholdProvider.future);
    final all = await repo.getAppointments(clinicId, startAfter: threshold);
    if (!controller.isClosed) controller.add(all);

    // Subscribe to Realtime changes for this clinic's appointments
    final subscription = realtime.subscribe([
      'databases.$appwriteDatabaseId.collections.appointments.documents',
    ]);

    subscription.stream.listen((_) async {
      // Any change → refresh from cache/network
      final updated = await repo.refreshAppointments(clinicId);
      final t = await ref.read(clinicVisibilityThresholdProvider.future);
      final filtered = updated.where((a) {
        return a.date.isAfter(t) || a.date.isAtSameMomentAs(t);
      }).toList();
      filtered.sort((a, b) {
        if (a.isCompleted && !b.isCompleted) return 1;
        if (!a.isCompleted && b.isCompleted) return -1;
        if (a.queueOrder != b.queueOrder) {
          return a.queueOrder.compareTo(b.queueOrder);
        }
        return a.date.compareTo(b.date);
      });
      if (!controller.isClosed) controller.add(filtered);
    });

    ref.onDispose(() {
      subscription.close();
      controller.close();
    });
  });

  return controller.stream;
});

// ─── Enriched appointments with patient data ─────────────────────────────────
final enrichedAppointmentsProvider = FutureProvider<List<Appointment>>((
  ref,
) async {
  final appointments = await ref.watch(appointmentsStreamProvider.future);
  final patients = await ref.watch(patientsStreamProvider.future);

  final enriched = appointments.map((app) {
    final patient = patients.cast<dynamic>().firstWhere(
      (p) => p.id == app.patientId,
      orElse: () => null,
    );
    return app.copyWith(patient: patient);
  }).toList();
  return enriched;
});

// ─── Stats derived from data ──────────────────────────────────────────────────
final todayAppointmentsCountProvider = Provider<int>((ref) {
  final appointmentsAsync = ref.watch(appointmentsStreamProvider);
  return appointmentsAsync.value?.length ?? 0;
});

final waitingPatientsCountProvider = Provider<int>((ref) {
  final appointmentsAsync = ref.watch(appointmentsStreamProvider);
  return appointmentsAsync.value?.where((a) => a.isWaiting).length ?? 0;
});

// ─── Date filter for reminders (defaults to tomorrow) ────────────────────────
class RemindersDateNotifier extends Notifier<DateTime> {
  @override
  DateTime build() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day).add(const Duration(days: 1));
  }

  void setDate(DateTime date) {
    state = date;
  }
}

final remindersDateProvider = NotifierProvider<RemindersDateNotifier, DateTime>(
  () {
    return RemindersDateNotifier();
  },
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

  final enriched = appointments.map((app) {
    final patient = patients.cast<dynamic>().firstWhere(
      (p) => p.id == app.patientId,
      orElse: () => null,
    );
    return app.copyWith(patient: patient);
  }).toList();
  return enriched;
});
