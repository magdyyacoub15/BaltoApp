import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/appointment_repository.dart';
import '../../auth/presentation/auth_providers.dart';
import '../domain/appointment.dart';
import '../../patients/domain/patients_provider.dart';
import '../../../core/services/appwrite_client.dart';

// ─── Realtime Appointments Stream Provider (for Dashboard) ───────────────────
// Listens to Appwrite Realtime and emits a fresh list whenever any appointment
// document is created, updated, or deleted in the current clinic.
final appointmentsStreamProvider = StreamProvider<List<Appointment>>((
  ref,
) async* {
  final user = await ref.watch(currentUserProvider.future);
  if (user == null) {
    yield [];
    return;
  }

  final realtime = ref.watch(appwriteRealtimeProvider);
  final repo = ref.watch(appointmentRepositoryProvider);
  final clinicId = user.clinicId;

  // Initial load from cache/network
  List<Appointment> currentList = [];
  try {
    final threshold = await ref.watch(clinicVisibilityThresholdProvider.future);
    currentList = await repo.getAppointments(clinicId, startAfter: threshold);
    yield currentList;
  } catch (_) {}

  // Subscribe to Realtime changes for this clinic's appointments
  final subscription = realtime.subscribe([
    'databases.$appwriteDatabaseId.collections.appointments.documents',
  ]);

  ref.onDispose(() {
    subscription.close();
  });

  // Listen for real-time events and refresh from the cache/network
  await for (final event in subscription.stream) {
    debugPrint('REALTIME APPOINTMENT EVENT: ${event.events}');
    try {
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
      debugPrint('REALTIME APPOINTMENT UPDATED: ${filtered.length}');
      yield filtered;
    } catch (e, stack) {
      debugPrint('REALTIME APPOINTMENT ERROR: $e');
      debugPrint(stack.toString());
    }
  }
});

// --- Enriched appointments with patient data ---------------------------------
// Reacts to every update from appointmentsStreamProvider or patientsStreamProvider.
final enrichedAppointmentsProvider = Provider<AsyncValue<List<Appointment>>>((
  ref,
) {
  final appointmentsAsync = ref.watch(appointmentsStreamProvider);
  final patientsAsync = ref.watch(patientsStreamProvider);

  if (appointmentsAsync is AsyncLoading || patientsAsync is AsyncLoading) {
    if (!appointmentsAsync.hasValue) return const AsyncLoading();
  }
  if (appointmentsAsync is AsyncError) {
    return AsyncError(appointmentsAsync.error!, appointmentsAsync.stackTrace!);
  }

  final appointments = appointmentsAsync.value ?? [];
  final patients = patientsAsync.value ?? [];

  final enriched = appointments.map((app) {
    final patient = patients.cast<dynamic>().firstWhere(
      (p) => p.id == app.patientId,
      orElse: () => null,
    );
    return app.copyWith(patient: patient);
  }).toList();

  return AsyncData(enriched);
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
