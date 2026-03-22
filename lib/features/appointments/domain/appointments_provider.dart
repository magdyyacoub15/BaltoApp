import 'package:appwrite/appwrite.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/appointment_repository.dart';
import '../../auth/presentation/auth_providers.dart';
import 'appointment.dart';
import '../../patients/domain/patients_provider.dart';
import '../../../core/services/appwrite_client.dart';

// ─── Realtime Appointments Notifier (for Dashboard) ───────────────────────────
// Listens to Appwrite Realtime and maintains a fresh list of appointments.
// Uses Notifier for robust lifecycle management and immediate local updates.
class AppointmentsNotifier extends AsyncNotifier<List<Appointment>> {
  RealtimeSubscription? _subscription;
  bool _isPolling = true;

  @override
  Future<List<Appointment>> build() async {
    final user = await ref.watch(currentUserProvider.future);
    if (user == null) return [];

    final repo = ref.watch(appointmentRepositoryProvider);
    final clinicId = user.clinicId;
    final threshold = await ref.watch(clinicVisibilityThresholdProvider.future);

    // 1. Initial Load
    List<Appointment> currentList = [];
    try {
      currentList = await repo.getAppointments(clinicId, startAfter: threshold);
    } catch (e) {
      debugPrint('AppointmentsNotifier: Initial load error: $e');
    }

    // 2. Subscribe to Realtime
    _subscribe(clinicId);

    // 3. Start Polling Fallback
    _startPolling(clinicId, repo);

    ref.onDispose(() {
      _subscription?.close();
      _isPolling = false;
    });

    return currentList;
  }

  void _subscribe(String clinicId) {
    _subscription?.close();
    final realtime = ref.read(appwriteRealtimeProvider);
    _subscription = realtime.subscribe([
      'databases.$appwriteDatabaseId.collections.appointments.documents',
    ]);

    _subscription!.stream.listen(
      (event) async {
        debugPrint('REALTIME APPOINTMENT EVENT: ${event.events}');
        final payload = event.payload;
        if (payload.isEmpty ||
            payload['clinicId']?.toString().trim() != clinicId.trim())
          return;

        final appt = Appointment.fromMap(
          payload,
          payload['\$id'] ?? payload['id'] ?? '',
        );

        final isCreate = event.events.any((e) => e.contains('.create'));
        final isUpdate = event.events.any((e) => e.contains('.update'));
        final isDelete = event.events.any((e) => e.contains('.delete'));

        final currentData = state.value ?? [];
        final newList = List<Appointment>.from(currentData);
        bool changed = false;

        if (isDelete) {
          final before = newList.length;
          newList.removeWhere((a) => a.id == appt.id);
          changed = newList.length != before;
        } else if (isUpdate) {
          final idx = newList.indexWhere((a) => a.id == appt.id);
          if (idx != -1) {
            newList[idx] = appt;
            changed = true;
          } else {
            newList.add(appt);
            changed = true;
          }
        } else if (isCreate) {
          if (!newList.any((a) => a.id == appt.id)) {
            newList.add(appt);
            changed = true;

            // Proactive Sync: If the patient is missing from our local list,
            // trigger an immediate silent refresh of the patients provider.
            final patients = ref.read(patientsStreamProvider).value ?? [];
            if (!patients.any((p) => p.id == appt.patientId)) {
              debugPrint(
                'AppointmentsNotifier: New patient detected, triggering sync...',
              );
              ref.read(patientsStreamProvider.notifier).silentRefresh();
            }
          }
        }

        if (changed) {
          final t = await ref.read(clinicVisibilityThresholdProvider.future);
          final filtered = newList.where((a) {
            return a.date.isAfter(t) || a.date.isAtSameMomentAs(t);
          }).toList();

          _sortAppointments(filtered);
          state = AsyncData(filtered);
          debugPrint('REALTIME APPOINTMENT UPDATED: ${filtered.length}');
        }

        // Sync repository cache in background
        ref
            .read(appointmentRepositoryProvider)
            .refreshAppointments(clinicId)
            .catchError((_) => <Appointment>[]);
      },
      onError: (e) {
        debugPrint('REALTIME APPOINTMENT STREAM ERROR: $e');
        Future.delayed(const Duration(seconds: 5), () {
          if (_isPolling) _subscribe(clinicId);
        });
      },
      onDone: () {
        debugPrint('REALTIME APPOINTMENT STREAM DONE (Closed)');
        Future.delayed(const Duration(seconds: 5), () {
          if (_isPolling) _subscribe(clinicId);
        });
      },
    );
  }

  void _startPolling(String clinicId, AppointmentRepository repo) async {
    while (_isPolling) {
      await Future.delayed(
        const Duration(seconds: 10),
      ); // Aggressive 10s polling
      if (!_isPolling) break;
      try {
        final fresh = await repo.refreshAppointments(clinicId);
        if (!_isPolling) break;

        final t = await ref.read(clinicVisibilityThresholdProvider.future);
        final filtered = fresh.where((a) {
          return a.date.isAfter(t) || a.date.isAtSameMomentAs(t);
        }).toList();

        _sortAppointments(filtered);
        state = AsyncData(filtered);
      } catch (_) {}
    }
  }

  void _sortAppointments(List<Appointment> list) {
    list.sort((a, b) {
      if (a.isCompleted && !b.isCompleted) return 1;
      if (!a.isCompleted && b.isCompleted) return -1;
      if (a.queueOrder != b.queueOrder) {
        return a.queueOrder.compareTo(b.queueOrder);
      }
      return a.date.compareTo(b.date);
    });
  }

  Future<void> manualRefresh() async {
    state = const AsyncLoading();
    ref.invalidateSelf();
  }
}

final appointmentsStreamProvider =
    AsyncNotifierProvider<AppointmentsNotifier, List<Appointment>>(() {
      return AppointmentsNotifier();
    });

// --- Enriched appointments with patient data ---------------------------------
// Reacts to every update from appointmentsStreamProvider or patientsStreamProvider.
final enrichedAppointmentsProvider = Provider<AsyncValue<List<Appointment>>>((
  ref,
) {
  final appointmentsAsync = ref.watch(appointmentsStreamProvider);
  final patientsAsync = ref.watch(patientsStreamProvider);

  // If we have data in both, show it immediately even if one is refreshing
  if (appointmentsAsync.hasValue && patientsAsync.hasValue) {
    final appointments = appointmentsAsync.value!;
    final patients = patientsAsync.value!;

    final enriched = appointments.map((app) {
      final patient = patients.cast<dynamic>().firstWhere(
        (p) => p.id == app.patientId,
        orElse: () => null,
      );
      return app.copyWith(patient: patient);
    }).toList();

    return AsyncData(enriched);
  }

  // Fallback to standard loading/error handling if no initial data
  if (appointmentsAsync is AsyncError) {
    return AsyncError(appointmentsAsync.error!, appointmentsAsync.stackTrace!);
  }
  if (patientsAsync is AsyncError) {
    return AsyncError(patientsAsync.error!, patientsAsync.stackTrace!);
  }

  return const AsyncLoading();
});

// Stats Providers
final todayAppointmentsCountProvider = Provider<int>((ref) {
  final appointments = ref.watch(appointmentsStreamProvider).value ?? [];
  final today = DateTime.now();
  return appointments.where((a) {
    return a.date.year == today.year &&
        a.date.month == today.month &&
        a.date.day == today.day;
  }).length;
});

final waitingPatientsCountProvider = Provider<int>((ref) {
  final appointments = ref.watch(appointmentsStreamProvider).value ?? [];
  return appointments.where((a) => !a.isCompleted && a.isWaiting).length;
});

final clinicStatsProvider = FutureProvider<Map<String, int>>((ref) async {
  final appointments = ref.watch(appointmentsStreamProvider).value ?? [];
  final user = await ref.watch(currentUserProvider.future);
  if (user == null) return {'today': 0, 'waiting': 0};

  final today = DateTime.now();
  final todayCount = appointments.where((a) {
    return a.date.year == today.year &&
        a.date.month == today.month &&
        a.date.day == today.day;
  }).length;

  final waitingCount = appointments
      .where((a) => !a.isCompleted && a.isWaiting)
      .length;

  return {'today': todayCount, 'waiting': waitingCount};
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
