import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import 'package:image_picker/image_picker.dart';
import '../domain/models/medical_record.dart';
import '../domain/models/prescription.dart';
import '../domain/patients_provider.dart';
import '../data/patient_repository.dart';
import '../../accounts/domain/transaction.dart';
import '../../accounts/data/transaction_repository.dart';
import '../../auth/presentation/auth_providers.dart';
import '../../../core/localization/language_provider.dart';
import '../data/prescription_service.dart';
import '../domain/patient.dart';
import '../../../core/services/imgbb_service.dart';

class AddMedicalRecordScreen extends ConsumerStatefulWidget {
  final String patientId;
  final MedicalRecord? initialRecord;

  const AddMedicalRecordScreen({
    super.key,
    required this.patientId,
    this.initialRecord,
  });

  @override
  ConsumerState<AddMedicalRecordScreen> createState() =>
      _AddMedicalRecordScreenState();
}

class _AddMedicalRecordScreenState
    extends ConsumerState<AddMedicalRecordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _diagnosisController = TextEditingController();
  final _notesController = TextEditingController();

  // Vital Signs
  final _bpController = TextEditingController();
  final _weightController = TextEditingController();
  final _tempController = TextEditingController();
  final _sugarController = TextEditingController();

  // Financials
  final _paidController = TextEditingController();
  final _remainingController = TextEditingController();

  // Medications
  final _medications = <Medication>[];
  final _medNameController = TextEditingController();
  final _dosageController = TextEditingController();
  final _freqController = TextEditingController();
  final _durationController = TextEditingController();
  final _medNotesController = TextEditingController();

  final List<File> _visitImages = [];
  final List<String> _existingUrls = [];
  final ImagePicker _picker = ImagePicker();
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialRecord != null) {
      final rec = widget.initialRecord!;
      _diagnosisController.text = rec.diagnosis;
      _notesController.text = rec.doctorNotes;
      if (rec.vitalSigns != null) {
        _bpController.text = rec.vitalSigns!.bloodPressure;
        _weightController.text = rec.vitalSigns!.weight > 0
            ? rec.vitalSigns!.weight.toString()
            : '';
        _tempController.text = rec.vitalSigns!.temperature > 0
            ? rec.vitalSigns!.temperature.toString()
            : '';
        _sugarController.text = rec.vitalSigns!.sugarLevel > 0
            ? rec.vitalSigns!.sugarLevel.toString()
            : '';
      }
      _paidController.text = rec.paidAmount > 0
          ? rec.paidAmount.toString()
          : '';
      _remainingController.text = rec.remainingAmount > 0
          ? rec.remainingAmount.toString()
          : '';
      _medications.addAll(rec.medications);
      _existingUrls.addAll(rec.attachmentUrls);
    }
  }

  @override
  void dispose() {
    _diagnosisController.dispose();
    _notesController.dispose();
    _bpController.dispose();
    _weightController.dispose();
    _tempController.dispose();
    _sugarController.dispose();
    _paidController.dispose();
    _remainingController.dispose();
    _medNameController.dispose();
    _dosageController.dispose();
    _freqController.dispose();
    _durationController.dispose();
    _medNotesController.dispose();

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
            instructions: _medNotesController.text.trim(),
          ),
        );
      });
      _medNameController.clear();
      _dosageController.clear();
      _freqController.clear();
      _durationController.clear();
      _medNotesController.clear();
    }
  }

  void _removeMedication(int index) {
    setState(() {
      _medications.removeAt(index);
    });
  }

  Future<void> _pickImage(ImageSource source) async {
    if (source == ImageSource.gallery) {
      final pickedFiles = await _picker.pickMultiImage(
        imageQuality: 50,
        maxWidth: 1080,
        maxHeight: 1080,
      );
      if (pickedFiles.isNotEmpty) {
        setState(() {
          _visitImages.addAll(pickedFiles.map((f) => File(f.path)));
        });
      }
    } else {
      final pickedFile = await _picker.pickImage(
        source: source,
        imageQuality: 50,
        maxWidth: 1080,
        maxHeight: 1080,
      );
      if (pickedFile != null) {
        setState(() {
          _visitImages.add(File(pickedFile.path));
        });
      }
    }
  }

  Future<List<String>> _uploadImages(String clinicId) async {
    if (_visitImages.isEmpty) return [];

    final List<String> uploadedUrls = [];
    final imgbbService = ref.read(imgbbServiceProvider);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            ref.tr('uploading_images', [_visitImages.length.toString()]),
          ),
        ),
      );
    }

    for (var i = 0; i < _visitImages.length; i++) {
      try {
        final url = await imgbbService.uploadImage(_visitImages[i]);
        if (url != null) {
          uploadedUrls.add(url);
        } else {
          debugPrint('ImgBB Error index $i: Upload failed');
        }
      } catch (e) {
        debugPrint('Error uploading image $i: $e');
      }
    }
    return uploadedUrls;
  }

  Future<void> _printPrescription() async {
    final clinic = ref.read(clinicStreamProvider).value;
    if (clinic == null) return;

    // Get patient info
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

    // Create a temporary record representing current state
    final tempRecord = MedicalRecord(
      id: widget.initialRecord?.id ?? '',
      date: widget.initialRecord?.date ?? DateTime.now(),
      diagnosis: _diagnosisController.text.trim(),
      doctorNotes: _notesController.text.trim(),
      medications: _medications,
      vitalSigns: VitalSigns(
        bloodPressure: _bpController.text.trim(),
        weight: double.tryParse(_weightController.text) ?? 0.0,
        temperature: double.tryParse(_tempController.text) ?? 0.0,
        sugarLevel: double.tryParse(_sugarController.text) ?? 0.0,
      ),
    );

    await PrescriptionService.printPrescription(
      clinic: clinic,
      patient: patient,
      record: tempRecord,
      languageCode: ref.read(languageProvider).languageCode,
    );
  }

  void _showImageSourcePicker(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (BuildContext context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: Wrap(
              children: <Widget>[
                ListTile(
                  leading: const Icon(Icons.photo_library, color: Colors.blue),
                  title: Text(ref.tr('pick_from_gallery')),
                  onTap: () {
                    _pickImage(ImageSource.gallery);
                    Navigator.of(context).pop();
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.photo_camera, color: Colors.grey),
                  title: Text(ref.tr('take_camera_picture')),
                  onTap: () {
                    _pickImage(ImageSource.camera);
                    Navigator.of(context).pop();
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _saveRecord() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);
    try {
      final patientsAsync = ref.read(patientsStreamProvider);
      final patient = patientsAsync.value?.firstWhere(
        (p) => p.id == widget.patientId,
      );

      if (patient == null) throw Exception(ref.tr('patient_not_found'));

      final user = ref.read(currentUserProvider).value;
      if (user == null) throw Exception(ref.tr('user_not_logged_in'));

      final List<String> currentAttachments = List.from(_existingUrls);

      final paid = double.tryParse(_paidController.text) ?? 0.0;
      final remaining = double.tryParse(_remainingController.text) ?? 0.0;

      final newRecord = MedicalRecord(
        id: widget.initialRecord?.id ?? const Uuid().v4(),
        date: widget.initialRecord?.date ?? DateTime.now(),
        diagnosis: _diagnosisController.text.trim(),
        doctorNotes: _notesController.text.trim(),
        medications: _medications,
        paidAmount: paid,
        remainingAmount: remaining,
        attachmentUrls: currentAttachments,
        isFinalized: true, // Mark as finalized upon saving
        vitalSigns: VitalSigns(
          bloodPressure: _bpController.text.trim(),
          weight: double.tryParse(_weightController.text) ?? 0.0,
          temperature: double.tryParse(_tempController.text) ?? 0.0,
          sugarLevel: double.tryParse(_sugarController.text) ?? 0.0,
        ),
      );

      List<MedicalRecord> updatedRecords;
      if (widget.initialRecord != null) {
        updatedRecords = patient.records.map((r) {
          return r.id == widget.initialRecord!.id ? newRecord : r;
        }).toList();
      } else {
        updatedRecords = [...patient.records, newRecord];
      }

      final repo = ref.read(patientRepositoryProvider);
      final updatedPatient = patient.copyWith(
        records: updatedRecords,
        lastVisit: widget.initialRecord != null
            ? patient.lastVisit
            : DateTime.now(),
        paidAmount:
            patient.paidAmount +
            (widget.initialRecord != null
                ? (paid - widget.initialRecord!.paidAmount)
                : paid),
        remainingAmount:
            patient.remainingAmount +
            (widget.initialRecord != null
                ? (remaining - widget.initialRecord!.remainingAmount)
                : remaining),
      );

      await repo.updatePatient(updatedPatient);

      // Record transaction if payment changed or is new
      if (paid > 0 &&
          (widget.initialRecord == null ||
              paid != widget.initialRecord!.paidAmount)) {
        final transactionRepo = ref.read(transactionRepositoryProvider);
        final revenue = AppTransaction(
          id: '',
          amount: widget.initialRecord != null
              ? (paid - widget.initialRecord!.paidAmount)
              : paid,
          description: widget.initialRecord != null
              ? ref.tr('edit_payment_for_patient', [patient.name])
              : ref.tr('patient_visit', [patient.name]),
          type: TransactionType.revenue,
          date: DateTime.now(),
          clinicId: user.clinicId,
        );
        await transactionRepo.addTransaction(revenue);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(ref.tr('data_saved_successfully'))),
        );
        Navigator.pop(context);
      }

      // Handle background upload
      if (_visitImages.isNotEmpty) {
        _handleBackgroundUpload(
          clinicId: user.clinicId,
          patientId: patient.id,
          recordId: newRecord.id,
          repo: repo,
        );
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

  void _handleBackgroundUpload({
    required String clinicId,
    required String patientId,
    required String recordId,
    required PatientRepository repo,
  }) async {
    try {
      final urls = await _uploadImages(clinicId);
      if (urls.isEmpty) {
        debugPrint('No images uploaded or upload failed');
        return;
      }

      // Fetch the latest patient state directly from DB to avoid stream latency
      final currentPatient = await repo.getPatientById(patientId);

      if (currentPatient == null) {
        debugPrint('Patient not found after upload');
        return;
      }

      List<MedicalRecord> updatedRecords = List.from(currentPatient.records);
      bool updated = false;
      for (int i = 0; i < updatedRecords.length; i++) {
        if (updatedRecords[i].id == recordId) {
          updatedRecords[i] = updatedRecords[i].copyWith(
            attachmentUrls: [...updatedRecords[i].attachmentUrls, ...urls],
          );
          updated = true;
          break;
        }
      }

      if (updated) {
        final updatedPatient = currentPatient.copyWith(
          records: updatedRecords,
          prescriptionImageUrl:
              currentPatient.prescriptionImageUrl ??
              updatedRecords
                  .firstWhere((r) => r.id == recordId)
                  .attachmentUrls
                  .firstOrNull,
        );
        await repo.updatePatient(updatedPatient);

        // Final success feedback
        debugPrint('Background upload completed successfully');
      }
    } catch (e) {
      debugPrint('Background upload error: $e');
      // In a real-world scenario, we might want to store these failed paths
      // in a local "pending_uploads" table for later retry.
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.initialRecord != null
              ? ref.tr('edit_visit_data')
              : ref.tr('add_visit_medical_record'),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.print),
            onPressed: _printPrescription,
            tooltip: ref.tr('print_prescription'),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                ref.tr('diagnosis_and_notes'),
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _diagnosisController,
                decoration: InputDecoration(
                  label: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(ref.tr('diagnosis')),
                  ),
                  prefixIcon: const Icon(Icons.vaccines),
                ),
                validator: (value) => value == null || value.isEmpty
                    ? ref.tr('please_enter_diagnosis')
                    : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _notesController,
                decoration: InputDecoration(
                  label: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(ref.tr('doctor_notes')),
                  ),
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 32),
              Text(
                ref.tr('vital_signs_optional'),
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _bpController,
                      decoration: InputDecoration(
                        label: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(ref.tr('blood_pressure_hint')),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: TextFormField(
                      controller: _weightController,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        label: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(ref.tr('weight_kg')),
                        ),
                        suffixText: 'kg',
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _tempController,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        label: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(ref.tr('temperature')),
                        ),
                        suffixText: '°C',
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: TextFormField(
                      controller: _sugarController,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        label: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(ref.tr('sugar_level')),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 32),
              Text(
                ref.tr('financial_details_today'),
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      ref.tr('paid_amount'),
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.grey.shade700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Text(
                      ref.tr('remaining_amount'),
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.grey.shade700,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _paidController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.payment, color: Colors.green),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: TextFormField(
                      controller: _remainingController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.money_off, color: Colors.red),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 32),

              Text(
                ref.tr('prescribed_medications'),
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Column(
                    children: [
                      TextFormField(
                        controller: _medNameController,
                        decoration: InputDecoration(
                          label: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(ref.tr('medication_name')),
                          ),
                          prefixIcon: const Icon(Icons.medication),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _dosageController,
                              decoration: InputDecoration(
                                label: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Text(ref.tr('dosage')),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextFormField(
                              controller: _freqController,
                              decoration: InputDecoration(
                                label: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Text(ref.tr('frequency')),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextFormField(
                              controller: _durationController,
                              decoration: InputDecoration(
                                label: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Text(ref.tr('duration')),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _medNotesController,
                        decoration: InputDecoration(
                          label: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(ref.tr('additional_instructions')),
                          ),
                          prefixIcon: const Icon(Icons.note_alt_outlined),
                        ),
                      ),
                      const SizedBox(height: 12),
                      ElevatedButton.icon(
                        onPressed: _addMedication,
                        icon: const Icon(Icons.add),
                        label: Text(ref.tr('add_to_prescription')),
                      ),
                    ],
                  ),
                ),
              ),
              if (_medications.isNotEmpty) ...[
                const SizedBox(height: 16),
                ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _medications.length,
                  itemBuilder: (context, index) {
                    final med = _medications[index];
                    return ListTile(
                      title: Text('${med.name} (${med.dosage})'),
                      subtitle: Text('${med.frequency} - ${med.duration}'),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete, color: Colors.red),
                        onPressed: () => _removeMedication(index),
                      ),
                    );
                  },
                ),
              ],
              const SizedBox(height: 24),
              _buildImagePickerSection(context),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : ElevatedButton(
                        onPressed: _saveRecord,
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                        child: Text(
                          ref.tr('save_record'),
                          style: const TextStyle(fontSize: 18),
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildImagePickerSection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          ref.tr('prescription_or_attachments'),
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 16),
        _buildImagePickerButton(context),
        if (_visitImages.isNotEmpty || _existingUrls.isNotEmpty)
          _buildImagesList(),
      ],
    );
  }

  Widget _buildImagePickerButton(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: () => _showImageSourcePicker(context),
      icon: const Icon(Icons.add_a_photo_outlined),
      label: Text(ref.tr('attach_new_image')),
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        side: BorderSide(
          color: Theme.of(context).primaryColor.withValues(alpha: 0.5),
        ),
      ),
    );
  }

  Widget _buildImagesList() {
    return Padding(
      padding: const EdgeInsets.only(top: 20.0),
      child: SizedBox(
        height: 120,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              // Existing images
              ..._existingUrls.asMap().entries.map((entry) {
                final index = entry.key;
                final url = entry.value;
                return _buildImageItem(
                  child: Image.network(
                    url,
                    fit: BoxFit.cover,
                    width: 120,
                    height: 120,
                  ),
                  onRemove: () => setState(() => _existingUrls.removeAt(index)),
                );
              }),
              // Newly selected images
              ..._visitImages.asMap().entries.map((entry) {
                final index = entry.key;
                final file = entry.value;
                return _buildImageItem(
                  child: Image.file(
                    file,
                    fit: BoxFit.cover,
                    width: 120,
                    height: 120,
                  ),
                  onRemove: () => setState(() => _visitImages.removeAt(index)),
                );
              }),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildImageItem({
    required Widget child,
    required VoidCallback onRemove,
  }) {
    return Container(
      margin: const EdgeInsets.only(left: 12),
      width: 120,
      height: 120,
      child: Stack(
        children: [
          ClipRRect(borderRadius: BorderRadius.circular(16), child: child),
          Positioned(
            top: 4,
            right: 4,
            child: GestureDetector(
              onTap: onRemove,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: const BoxDecoration(
                  color: Colors.red,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.close, color: Colors.white, size: 14),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
