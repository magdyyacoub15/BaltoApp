import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/patient_repository.dart';
import '../../auth/presentation/auth_providers.dart';
import 'patient.dart';
import '../../../core/services/appwrite_client.dart';

// Stream provider of all patients for the current user's clinic
// Listens to Appwrite Realtime for instant updates when new patients are added.
final patientsStreamProvider = StreamProvider<List<Patient>>((ref) async* {
  final user = await ref.watch(currentUserProvider.future);
  if (user == null) {
    yield [];
    return;
  }

  final realtime = ref.watch(appwriteRealtimeProvider);
  final repo = ref.watch(patientRepositoryProvider);
  final clinicId = user.clinicId;

  // Initial load
  List<Patient> currentList = [];
  try {
    currentList = await repo.getPatients(clinicId);
    yield currentList;
  } catch (_) {}

  // Subscribe to Realtime
  final subscription = realtime.subscribe([
    'databases.$appwriteDatabaseId.collections.patients.documents',
  ]);

  ref.onDispose(() {
    subscription.close();
  });

  // Listen for real-time events and refresh from the network/cache
  await for (final event in subscription.stream) {
    debugPrint('REALTIME PATIENT EVENT: ${event.events}');
    try {
      final updated = await repo.refreshPatients(clinicId);
      debugPrint('REALTIME PATIENT UPDATED: ${updated.length}');
      yield updated;
    } catch (e, stack) {
      debugPrint('REALTIME PATIENT ERROR: $e');
      debugPrint(stack.toString());
    }
  }
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
