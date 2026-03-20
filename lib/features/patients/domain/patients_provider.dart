import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/patient_repository.dart';
import '../../auth/presentation/auth_providers.dart';
import 'patient.dart';

// Future provider of all patients for the current user's clinic
final patientsStreamProvider = FutureProvider<List<Patient>>((ref) async {
  final user = await ref.watch(currentUserProvider.future);
  final repo = ref.watch(patientRepositoryProvider);

  if (user != null) {
    return await repo.getPatients(user.clinicId);
  }
  return [];
});

// Search query notifier for filtering results locally
class SearchQuery extends Notifier<String> {
  @override
  String build() => '';

  void update(String query) {
    state = query;
  }
}

final searchQueryProvider = NotifierProvider<SearchQuery, String>(
  SearchQuery.new,
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
