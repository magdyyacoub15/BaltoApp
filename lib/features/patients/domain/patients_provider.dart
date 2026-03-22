import 'package:appwrite/appwrite.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/patient_repository.dart';
import '../../auth/presentation/auth_providers.dart';
import 'patient.dart';
import '../../../core/services/appwrite_client.dart';

// ─── Realtime Patients Notifier ───────────────────────────────────────────────
// Listens to Appwrite Realtime and maintains a fresh list of patients.
class PatientsNotifier extends AsyncNotifier<List<Patient>> {
  RealtimeSubscription? _subscription;
  bool _isPolling = true;

  @override
  Future<List<Patient>> build() async {
    final user = await ref.watch(currentUserProvider.future);
    if (user == null) return [];

    final repo = ref.watch(patientRepositoryProvider);
    final clinicId = user.clinicId;

    // 1. Initial Load
    List<Patient> currentList = [];
    try {
      currentList = await repo.getPatients(clinicId);
    } catch (e) {
      debugPrint('PatientsNotifier: Initial load error: $e');
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
      'databases.$appwriteDatabaseId.collections.patients.documents',
    ]);

    _subscription!.stream.listen(
      (event) {
        debugPrint('REALTIME PATIENT EVENT: ${event.events}');
        final payload = event.payload;
        if (payload.isEmpty ||
            payload['clinicId']?.toString().trim() != clinicId.trim())
          return;

        final patient = Patient.fromMap(
          payload,
          payload['\$id'] ?? payload['id'] ?? '',
        );

        final isCreate = event.events.any((e) => e.contains('.create'));
        final isUpdate = event.events.any((e) => e.contains('.update'));
        final isDelete = event.events.any((e) => e.contains('.delete'));

        final currentData = state.value ?? [];
        final newList = List<Patient>.from(currentData);
        bool changed = false;

        if (isDelete) {
          final before = newList.length;
          newList.removeWhere((p) => p.id == patient.id);
          changed = newList.length != before;
        } else if (isUpdate) {
          final idx = newList.indexWhere((p) => p.id == patient.id);
          if (idx != -1) {
            newList[idx] = patient;
            changed = true;
          } else {
            newList.add(patient);
            changed = true;
          }
        } else if (isCreate) {
          if (!newList.any((p) => p.id == patient.id)) {
            newList.add(patient);
            changed = true;
          }
        }

        if (changed) {
          state = AsyncData(newList);
          debugPrint('REALTIME PATIENT UPDATED: ${newList.length}');
        }

        // Sync repository cache in background
        ref
            .read(patientRepositoryProvider)
            .refreshPatients(clinicId)
            .catchError((_) => <Patient>[]);
      },
      onError: (e) {
        debugPrint('REALTIME PATIENT STREAM ERROR: $e');
        Future.delayed(const Duration(seconds: 5), () {
          if (_isPolling) _subscribe(clinicId);
        });
      },
      onDone: () {
        debugPrint('REALTIME PATIENT STREAM DONE (Closed)');
        Future.delayed(const Duration(seconds: 5), () {
          if (_isPolling) _subscribe(clinicId);
        });
      },
    );
  }

  void _startPolling(String clinicId, PatientRepository repo) async {
    while (_isPolling) {
      await Future.delayed(const Duration(seconds: 15)); // Faster 15s polling
      if (!_isPolling) break;
      try {
        final fresh = await repo.refreshPatients(clinicId);
        if (!_isPolling) break;
        state = AsyncData(fresh);
      } catch (_) {}
    }
  }

  Future<void> manualRefresh() async {
    state = const AsyncLoading();
    ref.invalidateSelf();
  }

  // Silent Refresh: Updates the state from network but keeps existing data visible (no loading)
  Future<void> silentRefresh() async {
    final user = ref.read(currentUserProvider).value;
    if (user == null) return;

    try {
      final repo = ref.read(patientRepositoryProvider);
      final fresh = await repo.refreshPatients(user.clinicId);
      state = AsyncData(fresh);
    } catch (e) {
      debugPrint('PatientsNotifier: silentRefresh error: $e');
    }
  }
}

final patientsStreamProvider =
    AsyncNotifierProvider<PatientsNotifier, List<Patient>>(() {
      return PatientsNotifier();
    });

// Search query notifier for filtering results locally
class SearchQueryNotifier extends Notifier<String> {
  @override
  String build() => '';

  void update(String query) {
    state = query;
  }
}

final searchQueryProvider = NotifierProvider<SearchQueryNotifier, String>(
  SearchQueryNotifier.new,
);

// Sorting options for the patient list
enum PatientSort { name, date }

class PatientSortNotifier extends Notifier<PatientSort> {
  @override
  PatientSort build() => PatientSort.name;

  void setSort(PatientSort sort) {
    state = sort;
  }
}

final patientSortProvider = NotifierProvider<PatientSortNotifier, PatientSort>(
  PatientSortNotifier.new,
);

// Filtered patient list combining the live stream, the search query, and excluding new patients added today
final filteredPatientsProvider = FutureProvider<List<Patient>>((ref) async {
  final patients = await ref.watch(patientsStreamProvider.future);
  final query = ref.watch(searchQueryProvider).toLowerCase();
  final threshold = await ref.watch(clinicVisibilityThresholdProvider.future);
  final sort = ref.watch(patientSortProvider);

  // 1. Exclude entirely new patients added during the current shift
  var filtered = patients.where((p) {
    final isNewToday =
        p.records.length == 1 &&
        (p.lastVisit.isAfter(threshold) ||
            p.lastVisit.isAtSameMomentAs(threshold));
    return !isNewToday;
  }).toList();

  // 2. Apply search query
  if (query.isNotEmpty) {
    filtered = filtered
        .where(
          (p) =>
              p.name.toLowerCase().contains(query) || p.phone.contains(query),
        )
        .toList();
  }

  // 3. Apply sorting
  if (sort == PatientSort.name) {
    filtered.sort((a, b) => a.name.compareTo(b.name));
  } else {
    filtered.sort((a, b) => b.lastVisit.compareTo(a.lastVisit));
  }

  return filtered;
});
