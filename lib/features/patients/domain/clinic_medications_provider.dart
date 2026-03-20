import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'patients_provider.dart';
import 'models/prescription.dart';

final clinicMedicationsProvider = Provider<List<Medication>>((ref) {
  final patientsAsync = ref.watch(patientsStreamProvider);
  final patients = patientsAsync.value ?? [];
  final uniqueMedications = <String, Medication>{};

  for (final patient in patients) {
    for (final record in patient.records) {
      for (final med in record.medications) {
        final existing = uniqueMedications[med.name];
        // Keep the one with instructions if exists, otherwise keep first one
        if (existing == null ||
            (existing.instructions.isEmpty && med.instructions.isNotEmpty)) {
          uniqueMedications[med.name] = med;
        }
      }
    }
  }

  final medicationsList = uniqueMedications.values.toList();
  medicationsList.sort(
    (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
  );
  return medicationsList;
});
