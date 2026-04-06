import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';
import '../domain/patient.dart';
import '../domain/models/medical_record.dart';
import '../domain/models/prescription.dart';
import '../data/patient_repository.dart';
import '../data/prescription_service.dart';
import '../domain/clinic_medications_provider.dart';
import '../../auth/presentation/auth_providers.dart';
import '../../../core/localization/language_provider.dart';
import 'prescription_preview_screen.dart';
import '../../../core/presentation/widgets/animated_gradient_background.dart';
import '../../../core/services/imgbb_service.dart';
import '../../appointments/data/appointment_repository.dart';
import '../../appointments/domain/appointment.dart';
import '../../appointments/domain/appointments_provider.dart';

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
  DateTime? _nextReExamDate;

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
    _nextReExamDate = widget.record.nextReExamDate;
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
    if (source == ImageSource.gallery) {
      final pickedFiles = await picker.pickMultiImage(
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

  Future<List<String>> _uploadImages() async {
    if (_visitImages.isEmpty) return [];

    final List<String> uploadedUrls = [];
    final imgbbService = ref.read(imgbbServiceProvider);

    for (var i = 0; i < _visitImages.length; i++) {
      try {
        final result = await imgbbService.uploadImage(_visitImages[i]);
        if (result != null) {
          uploadedUrls.add(result.url);
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
        isFinalized: true,
        vitalSigns: VitalSigns(
          bloodPressure: _bpController.text.trim(),
          weight: double.tryParse(_weightController.text) ?? 0.0,
          temperature: double.tryParse(_tempController.text) ?? 0.0,
          sugarLevel: double.tryParse(_sugarController.text) ?? 0.0,
        ),
        medications: _medications,
        nextReExamDate: _nextReExamDate,
      );

      final updatedRecords = widget.patient.records.map((r) {
        return r.id == widget.record.id ? updatedRecord : r;
      }).toList();

      await repo.updatePatient(
        widget.patient.copyWith(records: updatedRecords),
      );

      // Create future appointment if next re-exam date was selected
      if (_nextReExamDate != null) {
        final user = ref.read(currentUserProvider).value;
        if (user != null) {
          final apptRepo = ref.read(appointmentRepositoryProvider);
          await apptRepo.addAppointment(
            Appointment(
              id: '',
              patientId: widget.patient.id,
              date: _nextReExamDate!,
              type: 're_examination',
              clinicId: user.clinicId,
              isWaiting: false,
              isManual: false,
            ),
          );
          ref.read(appointmentsRefreshProvider.notifier).refresh();
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(ref.tr('save_success'))));

        if (_medications.isNotEmpty) {
          final shouldPrint = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              title: Text(
                ref.tr('print_prescription_dialog_title'),
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
              ),
              content: Text(
                ref.tr('print_prescription_dialog_content'),
                style: const TextStyle(fontSize: 14),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: Text(
                    ref.tr('no'),
                    style: const TextStyle(color: Colors.grey),
                  ),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).primaryColor,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(ref.tr('yes')),
                ),
              ],
            ),
          );

          if (shouldPrint == true && mounted) {
            await _printPrescription();
          }
        }

        if (mounted) {
          Navigator.pop(context);
        }
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
    final nameFocusNode = FocusNode();
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
                      RawAutocomplete<Medication>(
                        textEditingController: nameController,
                        focusNode: nameFocusNode,
                        optionsBuilder: (TextEditingValue textEditingValue) {
                          if (textEditingValue.text.isEmpty) {
                            return const Iterable<Medication>.empty();
                          }
                          final allMeds = ref.read(clinicMedicationsProvider);
                          return allMeds.where(
                            (med) => med.name.toLowerCase().contains(
                              textEditingValue.text.toLowerCase(),
                            ),
                          );
                        },
                        displayStringForOption: (Medication med) => med.name,
                        onSelected: (Medication selection) {
                          if (instructionsController.text.isEmpty &&
                              selection.instructions.isNotEmpty) {
                            instructionsController.text =
                                selection.instructions;
                          }
                        },
                        fieldViewBuilder:
                            (
                              context,
                              controller,
                              focusNode,
                              onEditingComplete,
                            ) {
                              return _buildDialogField(
                                controller: controller,
                                focusNode: focusNode,
                                icon: Icons.medication_outlined,
                              );
                            },
                        optionsViewBuilder: (context, onSelected, options) {
                          return Align(
                            alignment: Alignment.topLeft,
                            child: Material(
                              elevation: 8.0,
                              borderRadius: BorderRadius.circular(16),
                              color: Colors.transparent,
                              child: Container(
                                width: 300,
                                constraints: const BoxConstraints(
                                  maxHeight: 250,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF1E1E1E).withAlpha(240),
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: Colors.white.withAlpha(50),
                                  ),
                                ),
                                child: ListView.builder(
                                  padding: EdgeInsets.zero,
                                  shrinkWrap: true,
                                  itemCount: options.length,
                                  itemBuilder: (context, index) {
                                    final option = options.elementAt(index);
                                    return ListTile(
                                      title: Text(
                                        option.name,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: Colors.white,
                                        ),
                                      ),
                                      subtitle: option.instructions.isNotEmpty
                                          ? Text(
                                              option.instructions,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                color: Colors.white70,
                                              ),
                                            )
                                          : null,
                                      onTap: () {
                                        onSelected(option);
                                      },
                                    );
                                  },
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 16),
                      _buildDialogField(
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
                                    dosage: '',
                                    frequency: '',
                                    duration: '',
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
    String? label,
    required TextEditingController controller,
    required IconData icon,
    int maxLines = 1,
    FocusNode? focusNode,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (label != null) ...[
          Text(
            label,
            softWrap: true,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: Colors.white,
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(height: 8),
        ],
        TextField(
          controller: controller,
          focusNode: focusNode,
          maxLines: maxLines,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 15,
            fontWeight: FontWeight.w500,
          ),
          decoration: InputDecoration(
            prefixIcon: Icon(icon, color: Colors.white70, size: 20),
            filled: true,
            fillColor: Colors.white.withAlpha(20),
            hintText: '',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(color: Colors.white.withAlpha(50), width: 1),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(color: Colors.white.withAlpha(50), width: 1),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(
                color: Colors.white,
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
    debugPrint('🖨️ [Tracer] Printing prescription for: ${widget.patient.name}, date: ${widget.record.date}');
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

    final pdfBytes = await PrescriptionService.generatePrescriptionPdf(
      clinic: clinic,
      patient: widget.patient,
      record: printRecord,
      languageCode: ref.read(languageProvider).languageCode,
    );

    if (mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => PrescriptionPreviewScreen(
            pdfBytes: pdfBytes,
            title: '${ref.tr('prescription')} - ${widget.patient.name}',
          ),
        ),
      );
    }
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
                  }),
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
        color: Colors.white.withAlpha(20),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withAlpha(50)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 24,
            backgroundColor: Colors.white.withAlpha(30),
            child: const Icon(Icons.person, color: Colors.white),
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
                    color: Colors.white,
                  ),
                ),
                Text(
                  '${ref.tr('last_visit')}: ${DateFormat('yyyy/MM/dd', ref.read(languageProvider).languageCode).format(widget.record.date)}',
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMainRecordCard() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.black.withAlpha(60),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withAlpha(50), width: 1),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.medical_services_outlined,
                    color: Colors.white,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    widget.record.isFinalized
                        ? ref.tr('visit_details')
                        : ref.tr('current_visit'),
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  Flexible(
                    child: Text(
                      DateFormat('yyyy/MM/dd hh:mm a', ref.read(languageProvider).languageCode).format(widget.record.date),
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                      textAlign: TextAlign.right,
                    ),
                  ),
                ],
              ),
              Divider(height: 24, color: Colors.white.withAlpha(50)),
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
              _buildNextReExamDatePicker(),
              const SizedBox(height: 20),
              _buildAttachmentsSection(),
            ],
          ),
        ),
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
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextButton.icon(
                      onPressed: _showPrescriptionDialog,
                      icon: const Icon(
                        Icons.add,
                        size: 18,
                        color: Colors.white,
                      ),
                      label: Text(
                        ref.tr('add_medication'),
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                    ),
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
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
          )
        else
          ListView.builder(
            shrinkWrap: true,
            padding: const EdgeInsets.symmetric(vertical: 8),
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _medications.length,
            itemBuilder: (context, index) {
              final med = _medications[index];
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                  color: Colors.white.withAlpha(20),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white.withAlpha(50)),
                ),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 4,
                  ),
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white.withAlpha(30),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.medication,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                  title: Text(
                    med.name,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                      color: Colors.white,
                    ),
                  ),
                  subtitle: med.instructions.isNotEmpty
                      ? Padding(
                          padding: const EdgeInsets.only(top: 4.0),
                          child: Text(
                            med.instructions,
                            style: const TextStyle(
                              fontSize: 13,
                              color: Colors.white70,
                            ),
                          ),
                        )
                      : null,
                  trailing: IconButton(
                    icon: const Icon(
                      Icons.delete_outline,
                      size: 22,
                      color: Colors.redAccent,
                    ),
                    onPressed: () =>
                        setState(() => _medications.removeAt(index)),
                  ),
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
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 13,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          maxLines: maxLines,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            prefixIcon: Icon(icon, size: 20, color: Colors.white70),
            filled: true,
            fillColor: Colors.white.withAlpha(20),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.white.withAlpha(60)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.white.withAlpha(60)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Colors.white, width: 2),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildNextReExamDatePicker() {
    final lang = ref.read(languageProvider).languageCode;
    final dateLabel = _nextReExamDate != null
        ? DateFormat('yyyy/MM/dd', lang).format(_nextReExamDate!)
        : ref.tr('not_set');

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(15),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _nextReExamDate != null
              ? Colors.tealAccent.withAlpha(150)
              : Colors.white.withAlpha(50),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.event_repeat_outlined,
            color: _nextReExamDate != null ? Colors.tealAccent : Colors.white70,
            size: 22,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  ref.tr('next_reexam_date'),
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  dateLabel,
                  style: TextStyle(
                    color: _nextReExamDate != null
                        ? Colors.tealAccent
                        : Colors.white54,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          if (_nextReExamDate != null)
            IconButton(
              icon: const Icon(Icons.clear, color: Colors.white54, size: 18),
              onPressed: () => setState(() => _nextReExamDate = null),
              tooltip: ref.tr('clear'),
            ),
          TextButton(
            onPressed: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: _nextReExamDate ??
                    DateTime.now().add(const Duration(days: 7)),
                firstDate: DateTime.now(),
                lastDate: DateTime.now().add(const Duration(days: 365)),
                locale: Locale(ref.read(languageProvider).languageCode),
              );
              if (picked != null) {
                setState(() => _nextReExamDate = picked);
              }
            },
            child: Text(
              _nextReExamDate != null
                  ? ref.tr('change_date')
                  : ref.tr('select_date'),
              style: const TextStyle(color: Colors.tealAccent, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVitalsGrid() {

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          ref.tr('vital_signs'),
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 13,
            color: Colors.white,
          ),
        ),
        GridView.count(
          shrinkWrap: true,
          padding: EdgeInsets.zero,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 2,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 1.8,
          children: [
            _buildVitalField(_bpController, ref.tr('bp'), Icons.speed_outlined),
            _buildVitalField(
              _weightController,
              ref.tr('weight'),
              Icons.monitor_weight_outlined,
              keyboardType: TextInputType.number,
            ),
            _buildVitalField(
              _tempController,
              ref.tr('temp'),
              Icons.thermostat_outlined,
              keyboardType: TextInputType.number,
            ),
            _buildVitalField(
              _sugarController,
              ref.tr('sugar'),
              Icons.water_drop_outlined,
              keyboardType: TextInputType.number,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildVitalField(
    TextEditingController controller,
    String label,
    IconData icon, {
    TextInputType? keyboardType,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 13,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: TextField(
            controller: controller,
            keyboardType: keyboardType,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              prefixIcon: Icon(icon, size: 18, color: Colors.white70),
              filled: true,
              fillColor: Colors.white.withAlpha(20),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 8,
                vertical: 8,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: Colors.white.withAlpha(60)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: Colors.white.withAlpha(60)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: Colors.white, width: 2),
              ),
            ),
          ),
        ),
      ],
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
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 13,
                color: Colors.white,
              ),
            ),
            TextButton.icon(
              onPressed: () => _showImageSourcePicker(context),
              icon: const Icon(
                Icons.add_a_photo_outlined,
                size: 16,
                color: Colors.white,
              ),
              label: Text(
                ref.tr('attach_images'),
                style: const TextStyle(fontSize: 12, color: Colors.white),
              ),
            ),
          ],
        ),
        if (_attachmentUrls.isEmpty && _visitImages.isEmpty)
          Container(
            height: 60,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Colors.white.withAlpha(20),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: Colors.white.withAlpha(50),
                style: BorderStyle.solid,
              ),
            ),
            child: Text(
              ref.tr('no_attachments'),
              style: const TextStyle(color: Colors.white70, fontSize: 12),
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
      return CachedNetworkImage(
        imageUrl: url,
        width: 90,
        height: 90,
        fit: BoxFit.cover,
      );
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
                DateFormat('yyyy/MM/dd', ref.read(languageProvider).languageCode).format(record.date),
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
