import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../domain/models/medical_record.dart';
import '../domain/models/prescription.dart';
import '../domain/patients_provider.dart';
import '../data/patient_repository.dart';
import '../../auth/presentation/auth_providers.dart';
import '../data/prescription_service.dart';
import '../domain/patient.dart';
import '../../../core/localization/language_provider.dart';
import 'package:intl/intl.dart';
import 'prescription_preview_screen.dart';

class WritePrescriptionScreen extends ConsumerStatefulWidget {
  final String patientId;

  const WritePrescriptionScreen({super.key, required this.patientId});

  @override
  ConsumerState<WritePrescriptionScreen> createState() =>
      _WritePrescriptionScreenState();
}

class _WritePrescriptionScreenState
    extends ConsumerState<WritePrescriptionScreen> {
  final _medications = <Medication>[];
  final _medNameController = TextEditingController();
  final _dosageController = TextEditingController();
  final _freqController = TextEditingController();
  final _durationController = TextEditingController();
  final _notesController = TextEditingController();
  bool _isLoading = false;

  @override
  void dispose() {
    _medNameController.dispose();
    _dosageController.dispose();
    _freqController.dispose();
    _durationController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  void _addMedication() {
    if (_medNameController.text.isNotEmpty &&
        _dosageController.text.isNotEmpty) {
      setState(() {
        _medications.add(
          Medication(
            name: _medNameController.text.trim(),
            dosage: _dosageController.text.trim(),
            frequency: _freqController.text.trim(),
            duration: _durationController.text.trim(),
          ),
        );
      });
      _medNameController.clear();
      _dosageController.clear();
      _freqController.clear();
      _durationController.clear();
    }
  }

  void _removeMedication(int index) {
    setState(() {
      _medications.removeAt(index);
    });
  }

  Future<void> _printPrescription() async {
    debugPrint('🖨️ [Tracer] Printing prescription in write_prescription_screen for patientId: ${widget.patientId}');
    final clinic = ref.read(clinicStreamProvider).value;
    if (clinic == null) return;

    final patientsAsync = ref.read(patientsStreamProvider);
    final patient =
        patientsAsync.value?.firstWhere(
          (p) => p.id == widget.patientId,
          orElse: () => Patient(
            id: widget.patientId,
            name: '...',
            phone: '',
            dateOfBirth: DateTime.now(),
            clinicId: clinic.id,
            lastVisit: DateTime.now(),
          ),
        ) ??
        Patient(
          id: widget.patientId,
          name: '...',
          phone: '',
          dateOfBirth: DateTime.now(),
          clinicId: clinic.id,
          lastVisit: DateTime.now(),
        );

    final tempRecord = MedicalRecord(
      id: '',
      date: DateTime.now(),
      diagnosis: ref.tr('dispense_medications_followup'),
      doctorNotes: _notesController.text.trim(),
      medications: _medications,
    );

    final pdfBytes = await PrescriptionService.generatePrescriptionPdf(
      clinic: clinic,
      patient: patient,
      record: tempRecord,
      languageCode: ref.read(languageProvider).languageCode,
    );

    if (mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => PrescriptionPreviewScreen(
            pdfBytes: pdfBytes,
            title: '${ref.tr('prescription')} - ${patient.name}',
          ),
        ),
      );
    }
  }

  Future<void> _savePrescription() async {
    if (_medications.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(ref.tr('please_add_at_least_one_medication'))),
      );
      return;
    }

    setState(() => _isLoading = true);
    try {
      final patientsAsync = ref.read(patientsStreamProvider);
      final patient = patientsAsync.value?.firstWhere(
        (p) => p.id == widget.patientId,
      );

      if (patient == null) throw Exception(ref.tr('patient_not_found'));

      // 1. Create the prescription object (still keeping it for legacy/backup if needed)
      final newPrescription = Prescription(
        id: const Uuid().v4(),
        date: DateTime.now(),
        medications: _medications,
        doctorNotes: _notesController.text.trim(),
      );

      // 2. Link medications to a MedicalRecord (today's visit)
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);

      List<MedicalRecord> updatedRecords = List.from(patient.records);
      int todayRecordIndex = updatedRecords.indexWhere((r) {
        final rDate = DateTime(r.date.year, r.date.month, r.date.day);
        return rDate.isAtSameMomentAs(today);
      });

      if (todayRecordIndex != -1) {
        // Update today's existing record
        final existingRecord = updatedRecords[todayRecordIndex];
        updatedRecords[todayRecordIndex] = MedicalRecord(
          id: existingRecord.id,
          date: existingRecord.date,
          diagnosis: existingRecord.diagnosis,
          doctorNotes: existingRecord.doctorNotes.isEmpty
              ? _notesController.text.trim()
              : '${existingRecord.doctorNotes}\n${_notesController.text.trim()}',
          vitalSigns: existingRecord.vitalSigns,
          attachmentUrls: existingRecord.attachmentUrls,
          medications: [...existingRecord.medications, ..._medications],
          paidAmount: existingRecord.paidAmount,
          remainingAmount: existingRecord.remainingAmount,
        );
      } else {
        // Create new record for today
        updatedRecords.add(
          MedicalRecord(
            id: const Uuid().v4(),
            date: now,
            diagnosis: ref.tr('dispense_medications_followup'),
            doctorNotes: _notesController.text.trim(),
            medications: _medications,
          ),
        );
      }

      final updatedPatient = patient.copyWith(
        prescriptions: [...patient.prescriptions, newPrescription],
        records: updatedRecords,
        lastVisit: now,
      );

      await ref.read(patientRepositoryProvider).updatePatient(updatedPatient);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(ref.tr('data_saved_successfully'))),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(ref.tr('save_error', [e.toString()]))),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(ref.tr('write_new_prescription')),
        actions: [
          IconButton(
            icon: const Icon(Icons.print),
            onPressed: _printPrescription,
            tooltip: ref.tr('print_prescription'),
          ),
          if (!_isLoading)
            IconButton(
              onPressed: _savePrescription,
              icon: const Icon(Icons.save),
              tooltip: ref.tr('save'),
            )
          else
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 16.0),
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 2,
                  ),
                ),
              ),
            ),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            // Prescription Paper Preview Section (Now includes interactive inputs)
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 16.0,
                vertical: 20.0,
              ),
              child: _buildPaperPreview(),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildPaperPreview() {
    final clinic = ref.watch(clinicStreamProvider).value;
    final patient = ref
        .watch(patientsStreamProvider)
        .value
        ?.firstWhere(
          (p) => p.id == widget.patientId,
          orElse: () => Patient(
            id: '',
            name: '...',
            phone: '',
            lastVisit: DateTime.now(),
            dateOfBirth: DateTime.now(),
            clinicId: '',
          ),
        );

    final isArabic = ref.read(languageProvider).languageCode == 'ar';
    final primaryColor = const Color(0xFFD32F2F);
    final bgColor = const Color(0xFFFFF5F5);

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(50),
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      clinic?.doctorName ?? clinic?.name ?? "Dr. Mohamed",
                      style: TextStyle(
                        color: primaryColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    const Text(
                      "MBBCH - Specialist",
                      style: TextStyle(fontSize: 10),
                    ),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      clinic?.doctorName ?? clinic?.name ?? "د. محمد",
                      style: TextStyle(
                        color: primaryColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    Text(
                      clinic?.specialization ?? "أخصائي",
                      style: const TextStyle(fontSize: 10),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Pulse Line
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    height: 1,
                    color: primaryColor.withAlpha(50),
                  ),
                ),
                const Icon(Icons.favorite, color: Color(0xFFD32F2F), size: 20),
                Expanded(
                  child: Container(
                    height: 1,
                    color: primaryColor.withAlpha(50),
                  ),
                ),
              ],
            ),
          ),

          // Patient Info
          Container(
            margin: const EdgeInsets.all(12),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              border: Border.symmetric(
                horizontal: BorderSide(color: primaryColor, width: 2),
              ),
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _buildPaperInfoField(
                    ref.tr('prescription_name'),
                    patient?.name ?? "...",
                    isArabic,
                  ),
                  const SizedBox(width: 10),
                  _buildPaperInfoField(
                    ref.tr('prescription_age'),
                    "${patient?.age ?? '...'}",
                    isArabic,
                  ),
                  const SizedBox(width: 10),
                  _buildPaperInfoField(
                    ref.tr('prescription_date'),
                    DateFormat('yyyy/MM/dd').format(DateTime.now()),
                    isArabic,
                  ),
                ],
              ),
            ),
          ),

          // Rx Content & Integrated Medication Inputs
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Rx",
                  style: TextStyle(
                    color: primaryColor,
                    fontSize: 80,
                    fontWeight: FontWeight.bold,
                    fontStyle: FontStyle.italic,
                  ),
                ),
                const Spacer(),
                const Column(
                  children: [
                    Icon(
                      Icons.monitor_heart_outlined,
                      size: 24,
                      color: Colors.grey,
                    ),
                    SizedBox(height: 12),
                    Icon(
                      Icons.bloodtype_outlined,
                      size: 24,
                      color: Colors.grey,
                    ),
                    SizedBox(height: 12),
                    Icon(
                      Icons.monitor_weight_outlined,
                      size: 24,
                      color: Colors.grey,
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Integrated Inputs
          Padding(
            padding: const EdgeInsets.fromLTRB(40, 0, 40, 20),
            child: Column(
              children: [
                TextField(
                  controller: _medNameController,
                  decoration: InputDecoration(
                    hintText: ref.tr('medication_name'),
                    hintStyle: TextStyle(color: Colors.grey[400]),
                    border: InputBorder.none,
                    isCollapsed: true,
                  ),
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
                const Divider(color: Colors.grey),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _dosageController,
                        decoration: InputDecoration(
                          hintText: ref.tr('dosage'),
                          hintStyle: TextStyle(
                            color: Colors.grey[400],
                            fontSize: 12,
                          ),
                          border: InputBorder.none,
                          isCollapsed: true,
                        ),
                        style: const TextStyle(fontSize: 14),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _freqController,
                        decoration: InputDecoration(
                          hintText: ref.tr('frequency'),
                          hintStyle: TextStyle(
                            color: Colors.grey[400],
                            fontSize: 12,
                          ),
                          border: InputBorder.none,
                          isCollapsed: true,
                        ),
                        style: const TextStyle(fontSize: 14),
                      ),
                    ),
                    IconButton(
                      icon: Icon(
                        Icons.add_circle,
                        color: primaryColor,
                        size: 30,
                      ),
                      onPressed: _addMedication,
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Medications List
          if (_medications.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 40),
              child: Text(
                "Add medications to see preview...",
                style: TextStyle(
                  color: Colors.grey,
                  fontStyle: FontStyle.italic,
                ),
              ),
            )
          else
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _medications.length,
              itemBuilder: (context, index) {
                final med = _medications[index];
                return Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 40.0,
                    vertical: 4.0,
                  ),
                  child: Row(
                    children: [
                      Text(
                        "${index + 1}. ",
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              med.name,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              "${med.dosage} - ${med.frequency} (${med.duration})",
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[700],
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(
                          Icons.close,
                          size: 16,
                          color: Colors.red,
                        ),
                        onPressed: () => _removeMedication(index),
                      ),
                    ],
                  ),
                );
              },
            ),

          const SizedBox(height: 40),

          const Divider(color: Colors.grey, indent: 40, endIndent: 40),

          // Instructions / Notes integrated in paper
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 10),
            child: TextField(
              controller: _notesController,
              maxLines: null,
              decoration: InputDecoration(
                hintText: ref.tr('general_instructions_notes'),
                hintStyle: TextStyle(color: Colors.grey[400], fontSize: 12),
                border: InputBorder.none,
                isCollapsed: true,
              ),
              style: const TextStyle(fontSize: 13, fontStyle: FontStyle.italic),
              onChanged: (v) => setState(() {}),
            ),
          ),

          const SizedBox(height: 20),

          // Footer
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: primaryColor, width: 2)),
            ),
            child: Row(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.phone, size: 12),
                        const SizedBox(width: 4),
                        Text(
                          clinic?.phone ?? "",
                          style: const TextStyle(fontSize: 10),
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        const Icon(Icons.chat_bubble_outline, size: 12),
                        const SizedBox(width: 4),
                        Text(
                          clinic?.phone ?? "",
                          style: const TextStyle(fontSize: 10),
                        ),
                      ],
                    ),
                  ],
                ),
                Expanded(
                  child: Text(
                    clinic?.address ?? "Address Not Set",
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 10),
                  ),
                ),
                const Icon(Icons.qr_code_2, size: 30),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPaperInfoField(String label, String value, bool isArabic) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          "$label: ",
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
        ),
        Text(value, style: const TextStyle(fontSize: 11)),
      ],
    );
  }
}
