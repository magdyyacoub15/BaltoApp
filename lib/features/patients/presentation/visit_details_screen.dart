import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';
import '../domain/patient.dart';
import '../domain/models/medical_record.dart';
import '../domain/models/prescription.dart';
import '../data/patient_repository.dart';
import '../data/prescription_service.dart';
import '../../auth/presentation/auth_providers.dart';
import '../../../core/localization/language_provider.dart';
import '../../../core/presentation/widgets/animated_gradient_background.dart';
import '../../../core/services/imgbb_service.dart';

class VisitDetailsScreen extends ConsumerStatefulWidget {
  final Patient patient;
  final MedicalRecord record;

  const VisitDetailsScreen({
    super.key,
    required this.patient,
    required this.record,
  });

  @override
  ConsumerState<VisitDetailsScreen> createState() => _VisitDetailsScreenState();
}

class _VisitDetailsScreenState extends ConsumerState<VisitDetailsScreen> {
  late final TextEditingController _diagnosisController;
  late final TextEditingController _notesController;
  late final TextEditingController _bpController;
  late final TextEditingController _weightController;
  late final TextEditingController _tempController;
  late final TextEditingController _sugarController;

  List<String> _attachmentUrls = [];
  final List<File> _visitImages = [];
  List<Medication> _medications = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _diagnosisController = TextEditingController(text: widget.record.diagnosis);
    _notesController = TextEditingController(text: widget.record.doctorNotes);
    _bpController = TextEditingController(
      text: widget.record.vitalSigns?.bloodPressure ?? '',
    );
    _weightController = TextEditingController(
      text: widget.record.vitalSigns?.weight != 0
          ? widget.record.vitalSigns?.weight.toString()
          : '',
    );
    _tempController = TextEditingController(
      text: widget.record.vitalSigns?.temperature != 0
          ? widget.record.vitalSigns?.temperature.toString()
          : '',
    );
    _sugarController = TextEditingController(
      text: widget.record.vitalSigns?.sugarLevel != 0
          ? widget.record.vitalSigns?.sugarLevel.toString()
          : '',
    );
    _attachmentUrls = List.from(widget.record.attachmentUrls);
    _medications = List.from(widget.record.medications);
  }

  @override
  void dispose() {
    _diagnosisController.dispose();
    _notesController.dispose();
    _bpController.dispose();
    _weightController.dispose();
    _tempController.dispose();
    _sugarController.dispose();
    super.dispose();
  }

  Future<void> _pickImage(ImageSource source) async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(
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

  Future<List<String>> _uploadImages() async {
    if (_visitImages.isEmpty) return [];

    final List<String> uploadedUrls = [];
    final imgbbService = ref.read(imgbbServiceProvider);

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

  Future<void> _save() async {
    setState(() => _isLoading = true);
    try {
      final repo = ref.read(patientRepositoryProvider);

      // Upload new images first
      final newUrls = await _uploadImages();
      final finalUrls = [..._attachmentUrls, ...newUrls];

      final updatedRecord = widget.record.copyWith(
        diagnosis: _diagnosisController.text.trim(),
        doctorNotes: _notesController.text.trim(),
        attachmentUrls: finalUrls,
        isFinalized: true, // Mark as past visit upon saving
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

      await repo.updatePatient(
        widget.patient.copyWith(records: updatedRecords),
      );

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(ref.tr('save_success'))));
        // Optional: Navigate back or refresh state
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

  void _showPrescriptionDialog() {
    final nameController = TextEditingController();
    final dosageController = TextEditingController();
    final frequencyController = TextEditingController();
    final durationController = TextEditingController();
    final instructionsController = TextEditingController();

    showDialog(
      context: context,
      builder: (innerContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        contentPadding: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        content: Container(
          width: double.infinity,
          constraints: const BoxConstraints(maxWidth: 550),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 20,
                ),
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
                        ref.tr('write_prescription'),
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white70),
                      onPressed: () => Navigator.pop(innerContext),
                    ),
                  ],
                ),
              ),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildDialogField(
                        label: ref.tr('medication_name'),
                        controller: nameController,
                        icon: Icons.medication_outlined,
                      ),
                      const SizedBox(height: 16),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: _buildDialogField(
                              label: ref.tr('dosage'),
                              controller: dosageController,
                              icon: Icons.science_outlined,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _buildDialogField(
                              label: ref.tr('frequency'),
                              controller: frequencyController,
                              icon: Icons.repeat_on_outlined,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      _buildDialogField(
                        label: ref.tr('duration'),
                        controller: durationController,
                        icon: Icons.timer_outlined,
                      ),
                      const SizedBox(height: 16),
                      _buildDialogField(
                        label: ref.tr('additional_instructions'),
                        controller: instructionsController,
                        icon: Icons.info_outline,
                        maxLines: 2,
                      ),
                      const SizedBox(height: 32),
                      SizedBox(
                        width: double.infinity,
                        height: 56,
                        child: ElevatedButton(
                          onPressed: () {
                            if (nameController.text.trim().isNotEmpty) {
                              setState(() {
                                _medications.add(
                                  Medication(
                                    name: nameController.text.trim(),
                                    dosage: dosageController.text.trim(),
                                    frequency: frequencyController.text.trim(),
                                    duration: durationController.text.trim(),
                                    instructions: instructionsController.text
                                        .trim(),
                                  ),
                                );
                              });
                              Navigator.pop(innerContext);
                            }
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Theme.of(context).primaryColor,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                            elevation: 4,
                            shadowColor: Theme.of(
                              context,
                            ).primaryColor.withAlpha(100),
                          ),
                          child: Text(
                            ref.tr('add'),
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDialogField({
    required String label,
    required TextEditingController controller,
    required IconData icon,
    int maxLines = 1,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          softWrap: true,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            color: Colors.blue.shade900,
            letterSpacing: 0.3,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          maxLines: maxLines,
          style: const TextStyle(
            color: Colors.black87,
            fontSize: 15,
            fontWeight: FontWeight.w500,
          ),
          decoration: InputDecoration(
            prefixIcon: Icon(icon, color: Colors.blue.shade700, size: 20),
            filled: true,
            fillColor: Colors.blue.shade50.withAlpha(30),
            hintText: '',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(color: Colors.blue.shade100, width: 1),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(color: Colors.blue.shade100, width: 1),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(
                color: Theme.of(context).primaryColor,
                width: 2,
              ),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 14,
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _printPrescription() async {
    final clinic = ref.read(clinicStreamProvider).value;
    if (clinic == null) return;

    final printRecord = widget.record.copyWith(
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
      patient: widget.patient,
      record: printRecord,
      languageCode: ref.read(languageProvider).languageCode,
    );
  }

  @override
  Widget build(BuildContext context) {
    final followUps =
        widget.patient.records
            .where((r) => r.parentRecordId == widget.record.id)
            .toList()
          ..sort((a, b) => b.date.compareTo(a.date));

    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Text(
          ref.tr('visit_workspace'),
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: AnimatedGradientBackground(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 100, 16, 16),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 800),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildPatientHeader(),
                const SizedBox(height: 20),
                _buildMainRecordCard(),
                const SizedBox(height: 20),
                if (followUps.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 8,
                    ),
                    child: Text(
                      ref.tr('follow_up_visits'),
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  ...followUps.asMap().entries.map((entry) {
                    final index = followUps.length - entry.key;
                    return _buildFollowUpCard(entry.value, index);
                  }).toList(),
                  const SizedBox(height: 20),
                ],
                ElevatedButton.icon(
                  onPressed: _isLoading ? null : _save,
                  icon: _isLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.check_circle_outline),
                  label: Text(ref.tr('save_visit_details')),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    backgroundColor: Colors.white.withAlpha(50),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
                const SizedBox(height: 40),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPatientHeader() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(5),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 24,
            backgroundColor: Colors.blue.withAlpha(20),
            child: const Icon(Icons.person, color: Colors.blue),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.patient.name,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
                Text(
                  '${ref.tr('last_visit')}: ${DateFormat('yyyy/MM/dd').format(widget.record.date)}',
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMainRecordCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.blue.shade100, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.medical_services_outlined,
                color: Colors.blue.shade700,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                widget.record.isFinalized
                    ? ref.tr('visit_details')
                    : ref.tr('current_visit'),
                style: TextStyle(
                  color: Colors.blue.shade900,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              Text(
                DateFormat('yyyy/MM/dd hh:mm a').format(widget.record.date),
                style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
              ),
            ],
          ),
          const Divider(height: 24),
          _buildInputSection(
            label: ref.tr('diagnosis'),
            controller: _diagnosisController,
            icon: Icons.assignment_outlined,
            maxLines: 2,
          ),
          const SizedBox(height: 16),
          _buildInputSection(
            label: ref.tr('doctor_notes'),
            controller: _notesController,
            icon: Icons.notes_outlined,
            maxLines: 4,
          ),
          const SizedBox(height: 20),
          _buildVitalsGrid(),
          const SizedBox(height: 20),
          _buildPrescriptionSection(),
          const SizedBox(height: 20),
          _buildAttachmentsSection(),
        ],
      ),
    );
  }

  Widget _buildPrescriptionSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              ref.tr('prescription'),
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
            ),
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextButton.icon(
                      onPressed: _showPrescriptionDialog,
                      icon: const Icon(Icons.edit_note, size: 18),
                      label: Text(ref.tr('write_prescription')),
                    ),
                    if (_medications.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      TextButton.icon(
                        onPressed: _printPrescription,
                        icon: const Icon(Icons.print, size: 18),
                        label: Text(ref.tr('print')),
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.green,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
        if (_medications.isEmpty)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            alignment: Alignment.center,
            child: Text(
              ref.tr('no_medications_added'),
              style: TextStyle(color: Colors.grey.shade400, fontSize: 12),
            ),
          )
        else
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _medications.length,
            itemBuilder: (context, index) {
              final med = _medications[index];
              return ListTile(
                dense: true,
                visualDensity: VisualDensity.compact,
                title: Text(
                  med.name,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: Text(med.dosage),
                trailing: IconButton(
                  icon: const Icon(
                    Icons.delete_outline,
                    size: 18,
                    color: Colors.red,
                  ),
                  onPressed: () => setState(() => _medications.removeAt(index)),
                ),
              );
            },
          ),
      ],
    );
  }

  Widget _buildInputSection({
    required String label,
    required TextEditingController controller,
    required IconData icon,
    int maxLines = 1,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          maxLines: maxLines,
          decoration: InputDecoration(
            hintText: '${ref.tr('enter')} $label...',
            prefixIcon: Icon(icon, size: 20),
            filled: true,
            fillColor: Colors.grey.shade50,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildVitalsGrid() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          ref.tr('vital_signs'),
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
        ),
        const SizedBox(height: 8),
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 2,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 2.5,
          children: [
            _buildVitalField(_bpController, ref.tr('bp'), Icons.speed_outlined),
            _buildVitalField(
              _weightController,
              ref.tr('weight'),
              Icons.monitor_weight_outlined,
            ),
            _buildVitalField(
              _tempController,
              ref.tr('temp'),
              Icons.thermostat_outlined,
            ),
            _buildVitalField(
              _sugarController,
              ref.tr('sugar'),
              Icons.water_drop_outlined,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildVitalField(
    TextEditingController controller,
    String label,
    IconData icon,
  ) {
    return TextField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, size: 18),
        filled: true,
        fillColor: Colors.grey.shade50,
        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }

  Widget _buildAttachmentsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              ref.tr('attachments'),
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
            ),
            TextButton.icon(
              onPressed: () => _pickImage(ImageSource.gallery),
              icon: const Icon(Icons.add_a_photo_outlined, size: 16),
              label: Text(
                ref.tr('attach_images'),
                style: const TextStyle(fontSize: 12),
              ),
            ),
          ],
        ),
        if (_attachmentUrls.isEmpty && _visitImages.isEmpty)
          Container(
            height: 60,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: Colors.grey.shade200,
                style: BorderStyle.solid,
              ),
            ),
            child: Text(
              ref.tr('no_attachments'),
              style: TextStyle(color: Colors.grey.shade400, fontSize: 12),
            ),
          )
        else
          SizedBox(
            height: 100,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: _attachmentUrls.length + _visitImages.length,
              itemBuilder: (context, index) {
                if (index < _attachmentUrls.length) {
                  final url = _attachmentUrls[index];
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Stack(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: _buildImage(url),
                        ),
                        Positioned(
                          top: 2,
                          right: 2,
                          child: GestureDetector(
                            onTap: () =>
                                setState(() => _attachmentUrls.removeAt(index)),
                            child: CircleAvatar(
                              radius: 10,
                              backgroundColor: Colors.red.withAlpha(200),
                              child: const Icon(
                                Icons.close,
                                size: 12,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                } else {
                  final imageIndex = index - _attachmentUrls.length;
                  final file = _visitImages[imageIndex];
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Stack(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image.file(
                            file,
                            width: 90,
                            height: 90,
                            fit: BoxFit.cover,
                          ),
                        ),
                        Positioned(
                          top: 2,
                          right: 2,
                          child: GestureDetector(
                            onTap: () => setState(
                              () => _visitImages.removeAt(imageIndex),
                            ),
                            child: CircleAvatar(
                              radius: 10,
                              backgroundColor: Colors.red.withAlpha(200),
                              child: const Icon(
                                Icons.close,
                                size: 12,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }
              },
            ),
          ),
      ],
    );
  }

  Widget _buildImage(String url) {
    if (url.startsWith('http')) {
      return Image.network(url, width: 90, height: 90, fit: BoxFit.cover);
    } else {
      return Image.file(File(url), width: 90, height: 90, fit: BoxFit.cover);
    }
  }

  Widget _buildFollowUpCard(MedicalRecord record, int number) {
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  ref.tr('followup_entry', [number.toString()]),
                  style: TextStyle(
                    color: Colors.orange.shade900,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
              const Spacer(),
              Text(
                DateFormat('yyyy/MM/dd').format(record.date),
                style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
              ),
            ],
          ),
          if (record.diagnosis.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              record.diagnosis,
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ],
          if (record.doctorNotes.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              record.doctorNotes,
              style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }
}
