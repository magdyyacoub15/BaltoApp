import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/patient_repository.dart';
import '../../auth/presentation/auth_providers.dart';
import '../../../core/services/polling_service.dart';
import 'patient.dart';

// ─── Manual Refresh Trigger for Patients ─────────────────────────────────────
class PatientsRefreshNotifier extends Notifier<int> {
  @override
  int build() => 0;
  void refresh() => state++;
}

final patientsRefreshProvider =
    NotifierProvider<PatientsRefreshNotifier, int>(PatientsRefreshNotifier.new);

// ─── Patients Stream Provider ─────────────────────────────────────────────────
// Reacts to:
//   1. patientsRefreshProvider increments (local writes → immediate)
//   2. pollingTickProvider (every 5 sec → other devices)
final patientsStreamProvider = StreamProvider<List<Patient>>((ref) async* {
  final user = await ref.watch(currentUserProvider.future);
  if (user == null) {
    yield [];
    return;
  }

  final clinicId = user.clinicId;
  final repo = ref.watch(patientRepositoryProvider);

  ref.watch(patientsRefreshProvider);
  ref.watch(pollingTickProvider);
  ref.watch(pageRefreshProvider);

  // 1. Yield cached data immediately (no loading spinner)
  final cached = await repo.getPatients(clinicId);
  if (cached.isNotEmpty) yield cached;

  // 2. Fetch fresh from network in background and yield update
  try {
    final fresh = await repo.fetchLivePatients(clinicId);
    yield fresh;
  } catch (_) {
    // Silently ignore network errors if cache is already shown
  }
});

// Search query notifier
class SearchQueryNotifier extends Notifier<String> {
  @override
  String build() => '';
  void update(String query) => state = query;
}

final searchQueryProvider = NotifierProvider<SearchQueryNotifier, String>(
  SearchQueryNotifier.new,
);

// Sorting options
enum PatientSort { name, date }

class PatientSortNotifier extends Notifier<PatientSort> {
  @override
  PatientSort build() => PatientSort.name;
  void setSort(PatientSort sort) => state = sort;
}

final patientSortProvider = NotifierProvider<PatientSortNotifier, PatientSort>(
  PatientSortNotifier.new,
);

// ─── Local UI State for deleted items ────────────────────────────────────────
// Holds IDs of patients that were just deleted to hide them INSTANTLY from the UI
class DeletedPatientIdsNotifier extends Notifier<Set<String>> {
  @override
  Set<String> build() => {};

  void add(String id) {
    state = {...state, id};
  }
}

final deletedPatientIdsProvider =
    NotifierProvider<DeletedPatientIdsNotifier, Set<String>>(
        DeletedPatientIdsNotifier.new);

// ─── Filtered patient list ────────────────────────────────────────────────────
final filteredPatientsProvider = StreamProvider<List<Patient>>((ref) async* {
  final patientsAsync = ref.watch(patientsStreamProvider);
  final query = ref.watch(searchQueryProvider).toLowerCase();
  final threshold = ref.watch(clinicVisibilityThresholdProvider);
  final sort = ref.watch(patientSortProvider);
  final deletedIds = ref.watch(deletedPatientIdsProvider);

  final patients = patientsAsync.value;
  if (patients == null) return;

  // 1. Exclude new patients and LOCALLY DELETED ones
  var filtered = patients.where((p) {
    if (deletedIds.contains(p.id)) return false; // Filter out immediately
    
    final isNewToday =
        p.records.length == 1 &&
        (p.lastVisit.isAfter(threshold) ||
            p.lastVisit.isAtSameMomentAs(threshold));
    return !isNewToday;
  }).toList();

  // 2. Apply search query
  if (query.isNotEmpty) {
    filtered = filtered
        .where((p) => p.name.toLowerCase().contains(query) || p.phone.contains(query))
        .toList();
  }

  // 3. Apply sorting
  if (sort == PatientSort.name) {
    filtered.sort((a, b) => a.name.compareTo(b.name));
  } else {
    filtered.sort((a, b) => b.lastVisit.compareTo(a.lastVisit));
  }

  yield filtered;
});
