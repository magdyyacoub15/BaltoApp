import 'dart:io';
import '../../../core/services/cleanup_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import '../domain/patient.dart';
import '../domain/models/medical_record.dart';
import '../data/patient_repository.dart';
import '../../auth/presentation/auth_providers.dart';
import '../../accounts/data/transaction_repository.dart';
import '../../accounts/domain/transaction.dart';
import '../../../core/presentation/widgets/scaled_icon.dart';
import '../../../core/localization/language_provider.dart';
import '../domain/models/prescription.dart';
import '../data/prescription_service.dart';
import '../../../core/services/imgbb_service.dart';

class MedicalRecordDialog extends ConsumerStatefulWidget {
  final Patient patient;
  final MedicalRecord record;

  const MedicalRecordDialog({
    super.key,
    required this.patient,
    required this.record,
  });

  @override
  ConsumerState<MedicalRecordDialog> createState() =>
      _MedicalRecordDialogState();
}

class _MedicalRecordDialogState extends ConsumerState<MedicalRecordDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _diagnosisController;
  late final TextEditingController _notesController;
  late final TextEditingController _bpController;
  late final TextEditingController _weightController;
  late final TextEditingController _tempController;
  late final TextEditingController _sugarController;
  late final TextEditingController _paidController;
  late final TextEditingController _remainingController;

  final List<File> _visitImages = [];
  late List<String> _existingUrls;
  final List<String> _urlsToDelete = [];
  final ImagePicker _picker = ImagePicker();

  late final TextEditingController _medNameController;
  late final TextEditingController _dosageController;
  late final TextEditingController _freqController;
  late final TextEditingController _durationController;
  late final TextEditingController _medNotesController;
  late List<Medication> _medications;

  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    final rec = widget.record;
    _diagnosisController = TextEditingController(text: rec.diagnosis);
    _notesController = TextEditingController(text: rec.doctorNotes);

    if (rec.vitalSigns != null) {
      _bpController = TextEditingController(
        text: rec.vitalSigns!.bloodPressure,
      );
      _weightController = TextEditingController(
        text: rec.vitalSigns!.weight > 0
            ? rec.vitalSigns!.weight.toString()
            : '',
      );
      _tempController = TextEditingController(
        text: rec.vitalSigns!.temperature > 0
            ? rec.vitalSigns!.temperature.toString()
            : '',
      );
      _sugarController = TextEditingController(
        text: rec.vitalSigns!.sugarLevel > 0
            ? rec.vitalSigns!.sugarLevel.toString()
            : '',
      );
    } else {
      _bpController = TextEditingController();
      _weightController = TextEditingController();
      _tempController = TextEditingController();
      _sugarController = TextEditingController();
    }

    _paidController = TextEditingController(
      text: rec.paidAmount > 0 ? rec.paidAmount.toString() : '',
    );
    _remainingController = TextEditingController(
      text: rec.remainingAmount > 0 ? rec.remainingAmount.toString() : '',
    );

    _existingUrls = List.from(rec.attachmentUrls);
    _medications = List.from(rec.medications);

    _medNameController = TextEditingController();
    _dosageController = TextEditingController();
    _freqController = TextEditingController();
    _durationController = TextEditingController();
    _medNotesController = TextEditingController();
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

  Future<void> _pickImage(ImageSource source) async {
    if (source == ImageSource.gallery) {
      final pickedFiles = await _picker.pickMultiImage(
        imageQuality: 50,
        maxWidth: 1080,
        maxHeight: 1080,
      );
      if (pickedFiles.isNotEmpty) {
        setState(() {
          _visitImages.addAll(pickedFiles.map((p) => File(p.path)));
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
          content: Text(ref.tr('uploading_images', [_visitImages.length])),
        ),
      );
    }

    for (var i = 0; i < _visitImages.length; i++) {
      try {
        final url = await imgbbService.uploadImage(_visitImages[i]);
        if (url != null) {
          uploadedUrls.add(url);
        }
      } catch (e) {
        debugPrint('Error uploading image $i: $e');
      }
    }
    return uploadedUrls;
  }

  void _addMedication() {
    if (_medNameController.text.isEmpty) return;

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
      _medNameController.clear();
      _dosageController.clear();
      _freqController.clear();
      _durationController.clear();
      _medNotesController.clear();
    });
  }

  void _removeMedication(int index) {
    setState(() {
      _medications.removeAt(index);
    });
  }

  Future<void> _printPrescription() async {
    final clinic = ref.read(clinicStreamProvider).value;
    if (clinic == null) return;

    final tempRecord = widget.record.copyWith(
      medications: _medications,
      diagnosis: _diagnosisController.text.trim(),
      doctorNotes: _notesController.text.trim(),
    );

    await PrescriptionService.printPrescription(
      clinic: clinic,
      patient: widget.patient,
      record: tempRecord,
      languageCode: ref.read(languageProvider).languageCode,
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);
    try {
      final repo = ref.read(patientRepositoryProvider);
      final user = ref.read(currentUserProvider).value;
      if (user == null) throw Exception(ref.tr('user_not_logged_in'));

      // Upload new images
      final newUrls = await _uploadImages(user.clinicId);
      final finalUrls = [..._existingUrls, ...newUrls];

      // Cleanup deleted images from storage
      final cleanupService = ref.read(cleanupServiceProvider);
      for (var url in _urlsToDelete) {
        await cleanupService.deleteCloudFile(url);
      }

      final paid = double.tryParse(_paidController.text) ?? 0.0;
      final remaining = double.tryParse(_remainingController.text) ?? 0.0;

      final updatedRecord = widget.record.copyWith(
        diagnosis: _diagnosisController.text.trim(),
        doctorNotes: _notesController.text.trim(),
        paidAmount: paid,
        remainingAmount: remaining,
        attachmentUrls: finalUrls,
        isFinalized: true, // Mark as finalized upon saving
        vitalSigns: VitalSigns(
          bloodPressure: _bpController.text.trim(),
          weight: double.tryParse(_weightController.text) ?? 0.0,
          temperature: double.tryParse(_tempController.text) ?? 0.0,
          sugarLevel: double.tryParse(_sugarController.text) ?? 0.0,
        ),
        medications: _medications,
      );

      final updatedRecords = widget.patient.records.map((r) {
        return r.id == widget.record.id ? updatedRecord : r;
      }).toList();

      final updatedPatient = widget.patient.copyWith(
        records: updatedRecords,
        paidAmount:
            widget.patient.paidAmount + (paid - widget.record.paidAmount),
        remainingAmount:
            widget.patient.remainingAmount +
            (remaining - widget.record.remainingAmount),
      );

      await repo.updatePatient(updatedPatient);

      if (paid != widget.record.paidAmount) {
        final transactionRepo = ref.read(transactionRepositoryProvider);
        final diff = paid - widget.record.paidAmount;
        final revenue = AppTransaction(
          id: '',
          amount: diff,
          description:
              '${ref.tr('edit_payment_for')}: ${widget.patient.name}', // I should add this key or use a generic one
          type: TransactionType.revenue,
          date: DateTime.now(),
          clinicId: user.clinicId,
        );
        await transactionRepo.addTransaction(revenue);
      }

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(ref.tr('update_success'))));
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('${ref.tr('save_error')}: $e')));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: Theme.of(context).copyWith(
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.grey.shade50,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(color: Colors.grey.shade200),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(color: Colors.grey.shade200),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(
              color: Theme.of(context).primaryColor,
              width: 2,
            ),
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 20,
            vertical: 16,
          ),
        ),
      ),
      child: AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        contentPadding: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        content: Container(
          constraints: const BoxConstraints(maxWidth: 600, maxHeight: 850),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildDialogHeader(context),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildSectionTitle(ref.tr('visit_details')),
                        const SizedBox(height: 16),
                        _buildTextField(
                          controller: _diagnosisController,
                          label: ref.tr('diagnosis'),
                          icon: Icons.assignment_outlined,
                        ),
                        const SizedBox(height: 16),
                        _buildTextField(
                          controller: _notesController,
                          label: ref.tr('doctor_notes_hint'),
                          icon: Icons.note_alt_outlined,
                        ),
                        const SizedBox(height: 24),
                        _buildSectionTitle(ref.tr('vital_signs_optional')),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: _buildTextField(
                                controller: _bpController,
                                label: ref.tr('bp'),
                                hintText: '120/80',
                                icon: Icons.speed,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: _buildTextField(
                                controller: _weightController,
                                label: ref.tr('weight'),
                                hintText: ref.tr('weight_unit'),
                                icon: Icons.monitor_weight_outlined,
                                keyboardType: TextInputType.number,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: _buildTextField(
                                controller: _tempController,
                                label: ref.tr('temp'),
                                hintText: '37',
                                icon: Icons.thermostat_outlined,
                                keyboardType: TextInputType.number,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: _buildTextField(
                                controller: _sugarController,
                                label: ref.tr('sugar'),
                                hintText: '90',
                                icon: Icons.water_drop_outlined,
                                keyboardType: TextInputType.number,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 32),
                        _buildSectionTitle(ref.tr('finance_details_today')),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: _buildTextField(
                                controller: _paidController,
                                label: ref.tr('paid'),
                                icon: Icons.add_card_outlined,
                                color: Colors.green,
                                keyboardType: TextInputType.number,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: _buildTextField(
                                controller: _remainingController,
                                label: ref.tr('remaining'),
                                icon: Icons.money_off_outlined,
                                color: Colors.red,
                                keyboardType: TextInputType.number,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 32),
                        _buildSectionTitle(ref.tr('prescribed_medications')),
                        const SizedBox(height: 16),
                        _buildMedicationInput(),
                        if (_medications.isNotEmpty) _buildMedicationsList(),

                        const SizedBox(height: 24),
                        _buildSectionTitle(ref.tr('attachments')),
                        const SizedBox(height: 16),
                        _buildImagePickerButton(context),
                        if (_existingUrls.isNotEmpty || _visitImages.isNotEmpty)
                          _buildImagesList(),
                        const SizedBox(height: 40),
                        _buildSaveButton(),
                        const SizedBox(height: 16),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDialogHeader(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Theme.of(context).primaryColor,
            Theme.of(context).primaryColor.withBlue(220),
          ],
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              ref.tr('edit_visit_title'),
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.print, color: Colors.white70),
            onPressed: _printPrescription,
            tooltip: ref.tr('print_prescription'),
          ),
          IconButton(
            icon: const Icon(Icons.close, color: Colors.white70),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.bold,
        color: Colors.blue.shade800,
        letterSpacing: 0.5,
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    String? label,
    required IconData icon,
    String? hintText,
    TextInputType? keyboardType,
    Color? color,
  }) {
    return TextFormField(
      controller: controller,
      decoration: InputDecoration(
        label: label != null
            ? FittedBox(fit: BoxFit.scaleDown, child: Text(label))
            : null,
        hintText: hintText,
        prefixIcon: ScaledIcon(
          icon,
          color: color ?? Colors.grey.shade600,
          size: 22,
        ),
      ),
      keyboardType: keyboardType,
    );
  }

  Widget _buildImagePickerButton(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: () => _showImageSourcePicker(context),
      icon: const Icon(Icons.add_a_photo_outlined),
      label: Text(ref.tr('add_new_images')),
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        side: BorderSide(
          color: Theme.of(context).primaryColor.withValues(alpha: 0.5),
        ),
      ),
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
                  title: Text(ref.tr('select_from_gallery')),
                  onTap: () {
                    _pickImage(ImageSource.gallery);
                    Navigator.of(context).pop();
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.photo_camera, color: Colors.grey),
                  title: Text(ref.tr('take_photo_camera')),
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
                  onRemove: () => setState(() {
                    final removedUrl = _existingUrls.removeAt(index);
                    _urlsToDelete.add(removedUrl);
                  }),
                );
              }),
              // New images
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

  Widget _buildSaveButton() {
    return _isLoading
        ? const Center(child: CircularProgressIndicator())
        : ElevatedButton(
            onPressed: _save,
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 18),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              elevation: 4,
              backgroundColor: Theme.of(context).primaryColor,
              foregroundColor: Colors.white,
            ),
            child: Text(
              ref.tr('update_visit_button'),
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          );
  }

  Widget _buildMedicationInput() {
    return Card(
      elevation: 0,
      color: Colors.grey.shade50,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            _buildTextField(
              controller: _medNameController,
              label: ref.tr('medication_name'),
              icon: Icons.medication_outlined,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _buildTextField(
                    controller: _dosageController,
                    label: ref.tr('dosage'),
                    icon: Icons.numbers_outlined,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildTextField(
                    controller: _freqController,
                    label: ref.tr('frequency'),
                    icon: Icons.repeat_on_outlined,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _buildTextField(
                    controller: _durationController,
                    label: ref.tr('duration'),
                    icon: Icons.timer_outlined,
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: _addMedication,
                  icon: const Icon(Icons.add),
                  label: Text(ref.tr('add_to_prescription')),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).primaryColor,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _buildTextField(
              controller: _medNotesController,
              label: ref.tr('additional_instructions'),
              icon: Icons.note_add_outlined,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMedicationsList() {
    return Padding(
      padding: const EdgeInsets.only(top: 16.0),
      child: ListView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: _medications.length,
        itemBuilder: (context, index) {
          final med = _medications[index];
          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: ListTile(
              title: Text(
                '${med.name} (${med.dosage})',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: Text(
                '${med.frequency} - ${med.duration}\n${med.instructions}',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
              trailing: IconButton(
                icon: const Icon(Icons.delete_outline, color: Colors.red),
                onPressed: () => _removeMedication(index),
              ),
            ),
          );
        },
      ),
    );
  }
}
