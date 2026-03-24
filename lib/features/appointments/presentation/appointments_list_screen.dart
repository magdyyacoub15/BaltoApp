import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../domain/appointment.dart';
import '../data/appointment_repository.dart';
import '../domain/appointments_provider.dart';
import '../../auth/presentation/auth_providers.dart';
import '../../patients/domain/patients_provider.dart';
import '../../patients/domain/models/medical_record.dart';
import '../../patients/data/patient_repository.dart';
import '../../patients/presentation/add_patient_screen.dart';
import '../../../core/localization/language_provider.dart';
import 'package:uuid/uuid.dart';

class SelectedDateNotifier extends Notifier<DateTime> {
  @override
  DateTime build() => DateTime.now();

  void update(DateTime date) {
    state = date;
  }
}

final selectedDateProvider = NotifierProvider<SelectedDateNotifier, DateTime>(
  SelectedDateNotifier.new,
);

// Live stream of appointments for the selected date
final appointmentsForSelectedDateProvider = FutureProvider<List<Appointment>>((
  ref,
) async {
  final user = await ref.watch(currentUserProvider.future);
  final repo = ref.watch(appointmentRepositoryProvider);
  final selectedDate = ref.watch(selectedDateProvider);

  if (user != null) {
    return await repo.getAppointments(user.clinicId, date: selectedDate);
  }
  return [];
});

// Enriched appointments for the selected date
final enrichedAppointmentsForSelectedDateProvider =
    Provider<AsyncValue<List<Appointment>>>((ref) {
      final appointmentsAsync = ref.watch(appointmentsForSelectedDateProvider);
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

class AppointmentsListScreen extends ConsumerWidget {
  const AppointmentsListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedDate = ref.watch(selectedDateProvider);
    final appointmentsAsync = ref.watch(
      enrichedAppointmentsForSelectedDateProvider,
    );
    final isToday = DateUtils.isSameDay(selectedDate, DateTime.now());

    return Scaffold(
      appBar: AppBar(
        title: Text(
          isToday
              ? ref.tr('today_appointments_list')
              : ref.tr('appointments_on_date', [
                  selectedDate.day.toString(),
                  selectedDate.month.toString(),
                ]),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.calendar_month),
            onPressed: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: selectedDate,
                firstDate: DateTime(2000),
                lastDate: DateTime(2100),
              );
              if (picked != null) {
                ref.read(selectedDateProvider.notifier).update(picked);
              }
            },
          ),
        ],
      ),
      body: appointmentsAsync.when(
        data: (appointments) => appointments.isEmpty
            ? Center(
                child: Text(
                  isToday
                      ? ref.tr('no_appointments_today')
                      : ref.tr('no_appointments_on_date'),
                ),
              )
            : ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: appointments.length,
                separatorBuilder: (context, index) => const Divider(),
                itemBuilder: (context, index) {
                  final appt = appointments[index];
                  final patientName =
                      appt.patient?.name ?? ref.tr('unknown_patient');
                  final timeStr = DateFormat(
                    'hh:mm',
                    ref.watch(languageProvider).languageCode,
                  ).format(appt.date);

                  return ListTile(
                    leading: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          timeStr,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        Text(
                          appt.date.hour < 12
                              ? ref.tr('morning')
                              : ref.tr('afternoons'),
                          style: const TextStyle(fontSize: 10),
                        ),
                      ],
                    ),
                    title: Text(patientName),
                    subtitle: Text(
                      appt.isWaiting
                          ? ref.tr('in_queue', [appt.type])
                          : (appt.isCompleted
                                ? ref.tr('completed_status', [appt.type])
                                : ref.tr('upcoming_status', [appt.type])),
                    ),
                    trailing: appt.isWaiting && !appt.isCompleted
                        ? ElevatedButton(
                            onPressed: () {
                              ref
                                  .read(appointmentRepositoryProvider)
                                  .updateAppointment(
                                    appt.copyWith(
                                      isWaiting: false,
                                      isCompleted: true,
                                    ),
                                  );
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 8,
                              ),
                              minimumSize: Size.zero,
                            ),
                            child: Text(ref.tr('enter')),
                          )
                        : (appt.isCompleted
                              ? const Icon(
                                  Icons.check_circle,
                                  color: Colors.green,
                                )
                              : const SizedBox.shrink()),
                  );
                },
              ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) =>
            Center(child: Text(ref.tr('error_occurred', [e.toString()]))),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAppointmentActions(context, ref),
        label: Text(ref.tr('add_appointment')),
        icon: const Icon(Icons.add),
      ),
    );
  }

  void _showAppointmentActions(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.person_add, color: Colors.blue),
                title: Text(ref.tr('new_patient_short')),
                onTap: () {
                  Navigator.pop(context);
                  showDialog(
                    context: context,
                    builder: (context) => const AddPatientScreen(),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.history, color: Colors.orange),
                title: Text(ref.tr('re_examination_old_patient')),
                onTap: () {
                  Navigator.pop(context);
                  _showPatientSearchDialog(context, ref);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  void _showPatientSearchDialog(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (context) {
        String searchQuery = '';
        return StatefulBuilder(
          builder: (context, setState) {
            final patientsAsync = ref.watch(patientsStreamProvider);
            final filteredPatients =
                patientsAsync.value?.where((p) {
                  return p.name.contains(searchQuery) ||
                      p.phone.contains(searchQuery);
                }).toList() ??
                [];

            return AlertDialog(
              title: Text(ref.tr('search_patient')),
              content: SizedBox(
                width: double.maxFinite,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      decoration: InputDecoration(
                        label: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(ref.tr('patient_name_or_phone')),
                        ),
                        prefixIcon: const Icon(Icons.search),
                      ),
                      onChanged: (value) => setState(() => searchQuery = value),
                    ),
                    const SizedBox(height: 16),
                    Flexible(
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: filteredPatients.length,
                        itemBuilder: (context, index) {
                          final patient = filteredPatients[index];
                          return ListTile(
                            title: Text(patient.name),
                            subtitle: Text(patient.phone),
                            onTap: () {
                              Navigator.pop(context);
                              _scheduleReExamination(context, ref, patient);
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _scheduleReExamination(
    BuildContext context,
    WidgetRef ref,
    dynamic patient,
  ) async {
    final user = ref.read(currentUserProvider).value;
    if (user == null) return;

    final newAppointment = Appointment(
      id: '',
      patientId: patient.id,
      date: DateTime.now().add(const Duration(minutes: 30)),
      type: 're_examination',
      clinicId: user.clinicId,
      isWaiting: true,
    );

    await ref
        .read(appointmentRepositoryProvider)
        .addAppointment(newAppointment);
    // Force immediate UI refresh
    ref.read(appointmentsRefreshProvider.notifier).refresh();

    // Create an unfinalized MedicalRecord for the current visit
    final patientRepo = ref.read(patientRepositoryProvider);
    String? parentId;
    final mainRecords = patient.records
        .where((r) => r.parentRecordId == null)
        .toList();
    if (mainRecords.isNotEmpty) {
      mainRecords.sort((a, b) => b.date.compareTo(a.date));
      parentId = mainRecords.first.id;
    }

    final newRecord = MedicalRecord(
      id: const Uuid().v4(),
      date: DateTime.now(),
      diagnosis: '',
      vitalSigns: VitalSigns(
        bloodPressure: '',
        weight: 0.0,
        temperature: 0.0,
        sugarLevel: 0.0,
      ),
      doctorNotes: '',
      attachmentUrls: [],
      isFinalized: false,
      medications: [],
      parentRecordId: parentId,
    );
    await patientRepo.addMedicalRecord(patient.id, newRecord);

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(ref.tr('added_to_queue', [patient.name]))),
      );
    }
  }
}
