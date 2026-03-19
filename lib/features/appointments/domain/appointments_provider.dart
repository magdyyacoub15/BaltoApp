import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/appointment_repository.dart';
import '../../auth/presentation/auth_providers.dart';
import '../domain/appointment.dart';
import '../../patients/domain/patients_provider.dart';

// Live stream of appointments for today
final appointmentsStreamProvider = StreamProvider<List<Appointment>>((ref) {
  final threshold = ref.watch(clinicVisibilityThresholdProvider);
  final userAsync = ref.watch(currentUserProvider);
  final repo = ref.watch(appointmentRepositoryProvider);

  return userAsync.when(
    data: (user) {
      if (user != null) {
        // Explicitly using named parameter to avoid NoSuchMethodError
        return repo
            .getAppointments(user.clinicId, startAfter: threshold)
            .map((list) => list.where((a) => a.isManual).toList());
      }
      return Stream.value([]);
    },
    loading: () => Stream.value([]),
    error: (e, st) => Stream.error(e, st),
  );
});

// Enriched appointments with patient data
final enrichedAppointmentsProvider = Provider<AsyncValue<List<Appointment>>>((
  ref,
) {
  final appointmentsAsync = ref.watch(appointmentsStreamProvider);
  final patientsAsync = ref.watch(patientsStreamProvider);

  return appointmentsAsync.when(
    data: (appointments) {
      return patientsAsync.when(
        data: (patients) {
          final enriched = appointments.map((app) {
            final patient = patients.cast<dynamic>().firstWhere(
              (p) => p.id == app.patientId,
              orElse: () => null,
            );
            return app.copyWith(patient: patient);
          }).toList();
          return AsyncValue.data(enriched);
        },
        loading: () => const AsyncValue.loading(),
        error: (e, st) => AsyncValue.error(e, st),
      );
    },
    loading: () => const AsyncValue.loading(),
    error: (e, st) => AsyncValue.error(e, st),
  );
});

// Stats derived from live Firestore data
final todayAppointmentsCountProvider = Provider<int>((ref) {
  final appointmentsAsync = ref.watch(appointmentsStreamProvider);
  return appointmentsAsync.value?.length ?? 0;
});

final waitingPatientsCountProvider = Provider<int>((ref) {
  final appointmentsAsync = ref.watch(appointmentsStreamProvider);
  return appointmentsAsync.value?.where((a) => a.isWaiting).length ?? 0;
});

// Date filter for reminders (defaults to tomorrow)
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

// Live stream of upcoming appointments
final upcomingAppointmentsStreamProvider = StreamProvider<List<Appointment>>((
  ref,
) {
  final userAsync = ref.watch(currentUserProvider);
  final repo = ref.watch(appointmentRepositoryProvider);
  final selectedDate = ref.watch(remindersDateProvider);

  return userAsync.when(
    data: (user) {
      if (user != null) {
        // Use getAppointments with the selected date instead of getUpcomingAppointments
        return repo.getAppointments(user.clinicId, date: selectedDate);
      }
      return Stream.value([]);
    },
    loading: () => Stream.value([]),
    error: (e, st) => Stream.error(e, st),
  );
});

// Enriched upcoming appointments
final enrichedUpcomingAppointmentsProvider =
    Provider<AsyncValue<List<Appointment>>>((ref) {
      final appointmentsAsync = ref.watch(upcomingAppointmentsStreamProvider);
      final patientsAsync = ref.watch(patientsStreamProvider);

      return appointmentsAsync.when(
        data: (appointments) {
          return patientsAsync.when(
            data: (patients) {
              final enriched = appointments.map((app) {
                final patient = patients.cast<dynamic>().firstWhere(
                  (p) => p.id == app.patientId,
                  orElse: () => null,
                );
                return app.copyWith(patient: patient);
              }).toList();
              return AsyncValue.data(enriched);
            },
            loading: () => const AsyncValue.loading(),
            error: (e, st) => AsyncValue.error(e, st),
          );
        },
        loading: () => const AsyncValue.loading(),
        error: (e, st) => AsyncValue.error(e, st),
      );
    });
