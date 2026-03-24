import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../domain/patient.dart';
import '../data/patient_repository.dart';
import '../../auth/presentation/auth_providers.dart';
import '../../appointments/domain/appointment.dart';
import '../../appointments/data/appointment_repository.dart';
import '../../appointments/domain/appointments_provider.dart';
import '../domain/patients_provider.dart';
import '../../../core/presentation/widgets/scaled_icon.dart';
import '../../../core/localization/language_provider.dart';
import '../../accounts/domain/transaction.dart';
import '../../accounts/data/transaction_repository.dart';
import '../../accounts/domain/accounts_provider.dart';
import '../domain/models/medical_record.dart';

class AddPatientScreen extends ConsumerStatefulWidget {
  final Patient? patient;
  final Appointment? appointment;
  final bool isReExamination;
  /// When true, only edits patient info — does NOT add a new appointment or medical record.
  final bool editOnly;

  const AddPatientScreen({
    super.key,
    this.patient,
    this.appointment,
    this.isReExamination = false,
    this.editOnly = false,
  });

  @override
  ConsumerState<AddPatientScreen> createState() => _AddPatientScreenState();
}

class _AddPatientScreenState extends ConsumerState<AddPatientScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _phoneController;
  DateTime? _dateOfBirth;
  late final TextEditingController _addressController;
  late final TextEditingController _paidController;
  late final TextEditingController _remainingController;
  bool _isLoading = false;
  String _examType = 'new_examination';

  // Smart Detection State
  Patient? _matchedPatient;
  bool _isSearching = false;
  int _searchCounter = 0;

  @override
  void initState() {
    super.initState();
    _examType = widget.appointment?.type ??
        (widget.isReExamination ? 're_examination' : 'new_examination');
    _nameController = TextEditingController(text: widget.patient?.name);
    _phoneController = TextEditingController(text: widget.patient?.phone);
    _dateOfBirth = widget.patient?.dateOfBirth;
    _addressController = TextEditingController(text: widget.patient?.address);
    // Find relevant record for this session
    MedicalRecord? todayRecord;
    if (widget.patient != null) {
      final searchDate = widget.appointment?.date ?? DateTime.now();
      try {
        todayRecord = widget.patient!.records.firstWhere((r) =>
            r.date.year == searchDate.year &&
            r.date.month == searchDate.month &&
            r.date.day == searchDate.day &&
            !r.isFinalized);
      } catch (_) {}
    }

    _paidController = TextEditingController(
      text: todayRecord != null && todayRecord.paidAmount > 0
          ? todayRecord.paidAmount.toString()
          : '',
    );
    _remainingController = TextEditingController(
      text: todayRecord != null && todayRecord.remainingAmount > 0
          ? todayRecord.remainingAmount.toString()
          : '',
    );
    _nameController.addListener(_onNameChanged);
  }

  void _onNameChanged() async {
    final name = _nameController.text.trim();
    if (name.isEmpty || widget.patient != null) return;

    final currentCounter = ++_searchCounter;
    await Future.delayed(const Duration(milliseconds: 500));
    if (currentCounter != _searchCounter || !mounted) return;

    final user = ref.read(currentUserProvider).value;
    if (user == null) return;

    setState(() => _isSearching = true);
    final repo = ref.read(patientRepositoryProvider);
    final match = await repo.getPatientByName(name, user.clinicId);

    if (currentCounter == _searchCounter && mounted) {
      setState(() {
        final previousMatch = _matchedPatient;
        _matchedPatient = match;
        _isSearching = false;

        if (match == null && widget.patient == null) {
          _examType = 'new_examination';
        }

        if (match != null) {
          if (_phoneController.text.isEmpty ||
              (previousMatch != null &&
                  _phoneController.text == previousMatch.phone)) {
            _phoneController.text = match.phone;
          }
          if (_dateOfBirth == null ||
              (previousMatch != null &&
                  _dateOfBirth == previousMatch.dateOfBirth)) {
            _dateOfBirth = match.dateOfBirth;
          }
          if (_addressController.text.isEmpty ||
              (previousMatch != null &&
                  _addressController.text == previousMatch.address)) {
            _addressController.text = match.address;
          }
          // Remove pre-filling of financial amounts for matched existing patients
          // Each visit should start with empty/fresh payment inputs
        } else if (previousMatch != null) {
          if (_phoneController.text == previousMatch.phone) {
            _phoneController.text = '';
          }
          if (_dateOfBirth == previousMatch.dateOfBirth) {
            _dateOfBirth = null;
          }
          if (_addressController.text == previousMatch.address) {
            _addressController.text = '';
          }

          // paid/remaining were never set from patient match, nothing to clear here.
        }
      });
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    _paidController.dispose();
    _remainingController.dispose();
    super.dispose();
  }

  Future<void> _selectDateOfBirth() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _dateOfBirth ?? DateTime(1990),
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
      locale: Locale(ref.read(languageProvider).languageCode),
    );
    if (picked != null && picked != _dateOfBirth) {
      setState(() {
        _dateOfBirth = picked;
      });
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_dateOfBirth == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(ref.tr('invalid_dob'))),
      );
      return;
    }

    final user = ref.read(currentUserProvider).value;
    if (user == null) return;

    setState(() => _isLoading = true);
    try {
      final repo = ref.read(patientRepositoryProvider);
      final apptRepo = ref.read(appointmentRepositoryProvider);
      final transactionRepo = ref.read(transactionRepositoryProvider);
      
      String patientId = widget.patient?.id ?? '';
      
      final double paid = double.tryParse(_paidController.text) ?? 0.0;
      final double remaining = double.tryParse(_remainingController.text) ?? 0.0;

      double oldPaidAmount = 0.0;
      int todayRecordIndex = -1;

      // --- FINANCIAL TRANSACTION & RECORD SAVE ---
      String? currentTransactionId;
      final double totalPaid = paid; 

      String newApptId = '';

      if (widget.patient == null && _matchedPatient == null) {
        // --- NEW PATIENT ---
        // 1. Create Transaction first to get ID
        currentTransactionId = await transactionRepo.addTransaction(
          AppTransaction(
            id: '',
            amount: totalPaid,
            description: ref.tr('examine_patient', [_nameController.text.trim()]),
            type: TransactionType.revenue,
            date: DateTime.now(),
            clinicId: user.clinicId,
            appointmentId: newApptId.isNotEmpty ? newApptId : null,
          ),
        );

        final newPatient = Patient(
          id: '',
          name: _nameController.text.trim(),
          phone: _phoneController.text.trim(),
          dateOfBirth: _dateOfBirth!,
          address: _addressController.text.trim(),
          paidAmount: totalPaid,
          remainingAmount: remaining,
          clinicId: user.clinicId,
          lastVisit: DateTime.now(),
          records: [
            MedicalRecord(
              id: '',
              date: DateTime.now(),
              diagnosis: '',
              doctorNotes: '',
              paidAmount: totalPaid,
              remainingAmount: remaining,
              transactionId: currentTransactionId,
            )
          ],
        );
        patientId = await repo.addPatient(newPatient);

        await apptRepo.addAppointment(
          Appointment(
            id: '',
            patientId: patientId,
            date: DateTime.now(),
            type: _examType,
            clinicId: user.clinicId,
            isWaiting: true,
            isManual: true,
          ),
        );
      } else {
        // --- EXISTING PATIENT ---
        final targetPatient = widget.patient ?? _matchedPatient!;
        patientId = targetPatient.id;

        final searchDate = widget.appointment?.date ?? DateTime.now();
        todayRecordIndex = targetPatient.records.indexWhere((r) => 
            r.date.year == searchDate.year &&
            r.date.month == searchDate.month &&
            r.date.day == searchDate.day &&
            !r.isFinalized);
        
        MedicalRecord? activeRecord;
        if (todayRecordIndex != -1) {
          activeRecord = targetPatient.records[todayRecordIndex];
          oldPaidAmount = activeRecord.paidAmount;
          currentTransactionId = activeRecord.transactionId;
        }

        // Handle Transaction (Add or Update)
        if (currentTransactionId != null) {
          // Update existing transaction
          await transactionRepo.updateTransaction(
            currentTransactionId,
            AppTransaction(
              id: currentTransactionId,
              amount: totalPaid,
              description: ref.tr('examine_patient', [_nameController.text.trim()]),
              type: TransactionType.revenue,
              date: activeRecord?.date ?? DateTime.now(),
              clinicId: user.clinicId,
            ),
          );
        } else if (totalPaid != 0) {
          // Create new transaction for this record (either stay empty or legacy)
          currentTransactionId = await transactionRepo.addTransaction(
            AppTransaction(
              id: '',
              amount: totalPaid,
              description: ref.tr('examine_patient', [_nameController.text.trim()]),
              type: TransactionType.revenue,
              date: activeRecord?.date ?? DateTime.now(),
              clinicId: user.clinicId,
            ),
          );
        }

        // Prepare updated patient
        final updatedPatient = targetPatient.copyWith(
          name: _nameController.text.trim(),
          phone: _phoneController.text.trim(),
          dateOfBirth: _dateOfBirth!,
          address: _addressController.text.trim(),
          paidAmount: (targetPatient.paidAmount - oldPaidAmount) + totalPaid,
          remainingAmount: (targetPatient.remainingAmount - (activeRecord?.remainingAmount ?? 0)) + remaining,
        );

        if (!widget.editOnly) {
          // Check if patient already has a non-finalized record today (avoid duplicates)
          final existingNonFinalizedIndex = targetPatient.records.indexWhere((r) => !r.isFinalized);

          if (existingNonFinalizedIndex != -1) {
            // Update existing record (e.g., if re-adding from queue to change type)
             final updatedRecords = List<MedicalRecord>.from(targetPatient.records);
             updatedRecords[existingNonFinalizedIndex] = updatedRecords[existingNonFinalizedIndex].copyWith(
               paidAmount: totalPaid,
               remainingAmount: remaining,
               transactionId: currentTransactionId,
               // Update parent if it's now a re-examination and didn't have one
               parentRecordId: _examType == 're_examination' ? (updatedRecords[existingNonFinalizedIndex].parentRecordId ?? _findLatestRootRecordId(targetPatient)) : null,
             );
             await repo.updatePatient(updatedPatient.copyWith(records: updatedRecords));
          } else {
            // New Appointment session
            await apptRepo.addAppointment(
              Appointment(
                id: '',
                patientId: patientId,
                date: DateTime.now(),
                type: _examType,
                clinicId: user.clinicId,
                isWaiting: true,
                isManual: true,
              ),
            );

            // Create Medical Record
            String? parentId;
            if (_examType == 're_examination') {
               parentId = _findLatestRootRecordId(targetPatient);
            }
            final newRecord = MedicalRecord(
              id: '',
              date: DateTime.now(),
              diagnosis: '',
              doctorNotes: '',
              paidAmount: totalPaid,
              remainingAmount: remaining,
              parentRecordId: parentId,
              transactionId: currentTransactionId,
              isFinalized: false,
            );
            await repo.updatePatient(updatedPatient.copyWith(records: [...targetPatient.records, newRecord]));
          }
        } else {
          // Edit existing session
          if (widget.appointment != null && widget.appointment!.type != _examType) {
            await apptRepo.updateAppointment(widget.appointment!.copyWith(type: _examType));
          }

          if (todayRecordIndex != -1) {
            final updatedRecords = List<MedicalRecord>.from(targetPatient.records);
            // When editing, ensure we maintain/update parent if type changed to re-examination
            String? parentId = updatedRecords[todayRecordIndex].parentRecordId;
            if (_examType == 're_examination' && parentId == null) {
              parentId = _findLatestRootRecordId(targetPatient);
            } else if (_examType == 'new_examination') {
              parentId = null;
            }

            updatedRecords[todayRecordIndex] = updatedRecords[todayRecordIndex].copyWith(
              paidAmount: totalPaid,
              remainingAmount: remaining,
              transactionId: currentTransactionId,
              parentRecordId: parentId,
            );
            await repo.updatePatient(updatedPatient.copyWith(records: updatedRecords));
          } else {
            // Note: If editOnly but no record found, we just update demographics
            await repo.updatePatient(updatedPatient);
          }
        }
      }

      // --- REFRESH ---
      ref.read(patientsRefreshProvider.notifier).refresh();
      ref.read(appointmentsRefreshProvider.notifier).refresh();
      ref.read(transactionsRefreshProvider.notifier).refresh();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ref.tr('save_success'))));
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${ref.tr('save_error')}: $e')));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String? _findLatestRootRecordId(Patient patient) {
    // Only records with null parent are "main" examinations
    final mainRecords = patient.records.where((r) => r.parentRecordId == null).toList();
    if (mainRecords.isNotEmpty) {
      mainRecords.sort((a, b) => b.date.compareTo(a.date));
      return mainRecords.first.id;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.patient != null;

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
          constraints: const BoxConstraints(maxWidth: 600, maxHeight: 660),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildDialogHeader(context, isEditing),
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildSectionTitle(ref.tr('basic_info')),
                        const SizedBox(height: 16),
                        _buildTextField(
                          controller: _nameController,
                          label: ref.tr('patient_full_name'),
                          icon: Icons.person_outline,
                          suffixIcon: _isSearching
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: Padding(
                                    padding: EdgeInsets.all(12),
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  ),
                                )
                              : null,
                          validator: (v) =>
                              v!.isEmpty ? ref.tr('enter_name_error') : null,
                        ),
                        const SizedBox(height: 16),
                        if (widget.patient != null ||
                            _matchedPatient != null) ...[
                          _buildSectionTitle(ref.tr('current_visit_details')),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: _buildExamTypeButton(
                                  label: ref.tr('new_examination'),
                                  type: 'new_examination',
                                  icon: Icons.personal_injury_outlined,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _buildExamTypeButton(
                                  label: ref.tr('re_examination'),
                                  type: 're_examination',
                                  icon: Icons.history_edu_outlined,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                        ],
                        _buildTextField(
                          controller: _phoneController,
                          label: ref.tr('phone_number'),
                          icon: Icons.phone_android_outlined,
                          keyboardType: TextInputType.phone,
                          validator: (v) {
                            if (v == null || v.isEmpty) {
                              return ref.tr('enter_phone_error');
                            }
                            if (v.length < 11) {
                              return ref.tr('phone_too_short');
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),
                        InkWell(
                          onTap: _selectDateOfBirth,
                          child: IgnorePointer(
                            child: _buildTextField(
                              controller: TextEditingController(
                                text: _dateOfBirth != null
                                    ? DateFormat(
                                        'yyyy/MM/dd',
                                        ref.read(languageProvider).languageCode,
                                      ).format(_dateOfBirth!)
                                    : '',
                              ),
                              label: ref.tr('dob_label'),
                              icon: Icons.cake_outlined,
                              validator: (v) => _dateOfBirth == null
                                  ? ref.tr('invalid_dob')
                                  : null,
                            ),
                          ),
                        ),
                        if (_dateOfBirth != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 8, left: 12),
                            child: Text(
                              ref.tr('current_age', [
                                _calculateAge(_dateOfBirth!),
                              ]),
                              style: TextStyle(
                                color: Colors.blue.shade700,
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        const SizedBox(height: 16),
                        _buildTextField(
                          controller: _addressController,
                          label: ref.tr('address'),
                          hintText: ref.tr('address_label'),
                          icon: Icons.location_on_outlined,
                        ),
                        const SizedBox(height: 16),
                        _buildSectionTitle(ref.tr('finance_details_today')),
                        const SizedBox(height: 16),
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
                        const SizedBox(height: 40),
                        _buildSaveButton(isEditing),
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

  int _calculateAge(DateTime dob) {
    final now = DateTime.now();
    int age = now.year - dob.year;
    if (now.month < dob.month ||
        (now.month == dob.month && now.day < dob.day)) {
      age--;
    }
    return age;
  }

  Widget _buildDialogHeader(BuildContext context, bool isEditing) {
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
              isEditing
                  ? ref.tr('edit_patient_info')
                  : ref.tr('add_new_patient'),
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
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
    required String label,
    required IconData icon,
    String? hintText,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
    Widget? suffixIcon,
    Color? color,
  }) {
    return TextFormField(
      controller: controller,
      decoration: InputDecoration(
        label: FittedBox(fit: BoxFit.scaleDown, child: Text(label)),
        hintText: hintText,
        prefixIcon: ScaledIcon(
          icon,
          color: color ?? Colors.grey.shade600,
          size: 22,
        ),
        suffixIcon: suffixIcon,
      ),
      keyboardType: keyboardType,
      validator: validator,
    );
  }

  Widget _buildSaveButton(bool isEditing) {
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
              isEditing ? ref.tr('save_changes') : ref.tr('save_patient_visit'),
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          );
  }

  Widget _buildExamTypeButton({
    required String label,
    required String type,
    required IconData icon,
  }) {
    final isSelected = _examType == type;
    final color = isSelected
        ? Theme.of(context).primaryColor
        : Colors.grey.shade100;

    return InkWell(
      onTap: () => setState(() => _examType = type),
      borderRadius: BorderRadius.circular(16),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color: color.withAlpha(isSelected ? 20 : 100),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? color : Colors.grey.shade300,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Column(
          children: [
            Icon(
              icon,
              color: isSelected ? color : Colors.grey.shade600,
              size: 28,
            ),
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                label,
                style: TextStyle(
                  color: isSelected ? color : Colors.grey.shade700,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  fontSize: 13,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
