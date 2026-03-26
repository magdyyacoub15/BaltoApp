import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import '../domain/patient.dart';
import '../domain/models/medical_record.dart';
import './medical_record_dialog.dart';
import '../domain/patients_provider.dart';
import '../data/patient_repository.dart';
import 'visit_details_screen.dart';
import '../data/prescription_service.dart';
import '../../../core/presentation/widgets/scaled_icon.dart';
import '../../../core/presentation/widgets/animated_gradient_background.dart';
import '../../../core/presentation/widgets/delete_confirmation_dialog.dart';
import '../../../core/services/permission_service.dart';
import '../../auth/presentation/auth_providers.dart';
import '../../../core/presentation/widgets/full_screen_image_viewer.dart';
import '../../../core/localization/language_provider.dart';
import 'prescription_preview_screen.dart';
import 'debt_payment_dialog.dart';

class PatientProfileScreen extends ConsumerStatefulWidget {
  final Patient patient;

  const PatientProfileScreen({super.key, required this.patient});

  @override
  ConsumerState<PatientProfileScreen> createState() =>
      _PatientProfileScreenState();
}

class _PatientProfileScreenState extends ConsumerState<PatientProfileScreen> {
  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final patientsAsync = ref.watch(patientsStreamProvider);
    final livePatient =
        patientsAsync.value?.firstWhere(
          (p) => p.id == widget.patient.id,
          orElse: () => widget.patient,
        ) ??
        widget.patient;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: AnimatedGradientBackground(
        child: NestedScrollView(
          headerSliverBuilder: (context, innerBoxIsScrolled) {
            return [
              SliverAppBar(
                expandedHeight: 280,
                pinned: false,
                floating: true,
                elevation: 0,
                backgroundColor: Colors.transparent,
                automaticallyImplyLeading: false,
                leading: IconButton(
                  icon: const Icon(Icons.arrow_back, color: Colors.white),
                  onPressed: () => Navigator.pop(context),
                ),
                actions: [
                  // Profile Edit button removed as per user request
                ],
                flexibleSpace: FlexibleSpaceBar(
                  background: Container(
                    decoration: const BoxDecoration(color: Colors.transparent),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const SizedBox(height: 70),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              livePatient.name,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 28,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withAlpha(20),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: Colors.white.withAlpha(30),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.phone_android_rounded,
                                size: 14,
                                color: Colors.white,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                livePatient.phone,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              _buildCommunicationButton(
                                icon: Icons.phone_forwarded_rounded,
                                color: Colors.blueAccent,
                                onTap: () => _makeCall(livePatient.phone),
                              ),
                              const SizedBox(width: 16),
                              _buildCommunicationButton(
                                icon: FontAwesomeIcons.whatsapp,
                                color: const Color(0xFF25D366),
                                onTap: () => _sendWhatsApp(
                                  livePatient.phone,
                                  ref.tr('whatsapp_greeting', [
                                    livePatient.name,
                                  ]),
                                ),
                              ),
                              const SizedBox(width: 16),
                              _buildCommunicationButton(
                                icon: Icons.copy_rounded,
                                color: Colors.white,
                                onTap: () => _copyToClipboard(
                                  context,
                                  livePatient.phone,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),
                      ],
                    ),
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: _buildQuickStatCard(
                              context: context,
                              label: ref.tr('age_label'),
                              value: '${livePatient.age}',
                              unit: ref.tr('years_unit'),
                              subtitle: DateFormat(
                                'yyyy/MM/dd',
                                ref.read(languageProvider).languageCode,
                              ).format(livePatient.dateOfBirth),
                              icon: Icons.cake_outlined,
                              color: Colors.blue,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: _buildQuickStatCard(
                              context: context,
                              label: ref.tr('total_visits'),
                              value: '${livePatient.records.length}',
                              unit: ref.tr('visits_unit'),
                              icon: Icons.calendar_today_outlined,
                              color: Colors.indigo,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      _buildHealthAlertCard(
                        context,
                        title: ref.tr('chronic_diseases'),
                        content: livePatient.chronicDiseases.isNotEmpty
                            ? livePatient.chronicDiseases
                            : ref.tr('no_chronic_diseases'),
                        icon: Icons.medical_information_outlined,
                        color: Colors.red.shade400,
                        onTap: () => _showEditChronicDiseasesDialog(
                          context,
                          livePatient,
                        ),
                      ),
                      const SizedBox(height: 16),
                      _buildCurrentVisitCard(context, livePatient),
                    ],
                  ),
                ),
              ),
            ];
          },
          body: _buildMedicalHistoryTab(context, livePatient),
        ),
      ),
    );
  }

  Widget _buildCommunicationButton({
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(15),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white.withAlpha(25),
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: Colors.white.withAlpha(40)),
        ),
        child: Icon(icon, color: color, size: 20),
      ),
    );
  }

  Future<void> _sendWhatsApp(String phone, String message) async {
    String cleanPhone = phone.replaceAll(RegExp(r'\D'), '');
    if (cleanPhone.startsWith('0') && cleanPhone.length == 11) {
      cleanPhone = '2$cleanPhone';
    } else if (cleanPhone.length == 10) {
      cleanPhone = '20$cleanPhone';
    }

    final appUrl =
        'whatsapp://send?phone=$cleanPhone&text=${Uri.encodeComponent(message)}';
    final webUrl =
        'https://wa.me/$cleanPhone?text=${Uri.encodeComponent(message)}';

    if (await canLaunchUrl(Uri.parse(appUrl))) {
      await launchUrl(Uri.parse(appUrl), mode: LaunchMode.externalApplication);
    } else if (await canLaunchUrl(Uri.parse(webUrl))) {
      await launchUrl(Uri.parse(webUrl), mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _makeCall(String phone) async {
    final uri = Uri(scheme: 'tel', path: phone);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  void _copyToClipboard(BuildContext context, String text) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ref.tr('phone_copied')),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _printPrescription(Patient patient, MedicalRecord record) async {
    final clinic = ref.read(clinicStreamProvider).value;
    if (clinic == null) return;

    final pdfBytes = await PrescriptionService.generatePrescriptionPdf(
      clinic: clinic,
      patient: patient,
      record: record,
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

  Future<void> _showDeleteRecordDialog(
    BuildContext context,
    Patient patient,
    MedicalRecord record,
  ) async {
    showDialog(
      context: context,
      builder: (dialogContext) => DeleteConfirmationDialog(
        title: ref.tr('delete_visit_title'),
        content: ref.tr('delete_visit_desc'),
        onDelete: () async {
          if (!context.mounted) return;
          try {
            await ref
                .read(patientRepositoryProvider)
                .deleteMedicalRecord(patient, record.id);

            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(ref.tr('record_deleted_success'))),
              );
            }
          } catch (e) {
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('${ref.tr('record_delete_error')}: $e')),
              );
            }
          }
        },
      ),
    );
  }

  Widget _buildQuickStatCard({
    required BuildContext context,
    required String label,
    required String value,
    required String unit,
    required IconData icon,
    required Color color,
    String? subtitle,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(50),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withAlpha(80)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Icon(icon, color: Colors.white, size: 18),
            ],
          ),
          const SizedBox(height: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  value,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  unit,
                  style: const TextStyle(color: Colors.white, fontSize: 10),
                ),
              ],
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 10,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMedicalHistoryTab(BuildContext context, Patient p) {
    final sortedRecords =
        p.records
            .where((r) => r.isFinalized) // Only show finalized records
            .toList()
          ..sort((a, b) => b.date.compareTo(a.date));

    return ListView.builder(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.all(24.0),
      itemCount: sortedRecords.length + 1,
      itemBuilder: (context, index) {
        if (index == 0) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.timeline, color: Colors.white),
                    const SizedBox(width: 12),
                    Text(
                      ref.tr('visit_history'),
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
                if (p.records.isEmpty)
                  _buildEmptyTabState(
                    Icons.history_outlined,
                    ref.tr('no_visits_yet'),
                  ),
              ],
            ),
          );
        }

        final record = sortedRecords[index - 1];
        final formattedDate = DateFormat(
          'yyyy/MM/dd',
          ref.read(languageProvider).languageCode,
        ).format(record.date);

        return Container(
          margin: const EdgeInsets.only(bottom: 24),
          decoration: BoxDecoration(
            color: Colors.white.withAlpha(50),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.white.withAlpha(80)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.1),
                blurRadius: 15,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              initiallyExpanded: false,
              tilePadding: const EdgeInsets.symmetric(
                horizontal: 20,
                vertical: 12,
              ),
              leading: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).primaryColor.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: ScaledIcon(
                  Icons.calendar_month_outlined,
                  color: Theme.of(context).primaryColor,
                  size: 24,
                ),
              ),
              title: Text(
                record.diagnosis.isNotEmpty
                    ? '$formattedDate - ${record.diagnosis}'
                    : formattedDate,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                  color: Colors.white,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 6),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerRight,
                    child: Row(
                      children: [
                        _buildSmallFinanceInfo(
                          '${ref.tr('paid')}: ${record.paidAmount}',
                          Colors.green,
                        ),
                        const SizedBox(width: 8),
                        _buildSmallFinanceInfo(
                          '${ref.tr('remaining')}: ${record.remainingAmount}',
                          Colors.red,
                          onTap: () {
                            if (record.remainingAmount > 0) {
                              showDialog(
                                context: context,
                                builder: (context) => DebtPaymentDialog(
                                  patient: p,
                                  record: record,
                                ),
                              );
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.print, color: Colors.white70),
                    onPressed: () => _printPrescription(p, record),
                    tooltip: ref.tr('print_prescription'),
                  ),
                  IconButton(
                    icon: const Icon(Icons.edit_note, color: Colors.blue),
                    onPressed: () async {
                      final clinic = ref.read(clinicStreamProvider).value;
                      if (clinic == null) return;

                      final canWrite = await ref
                          .read(permissionServiceProvider)
                          .canWrite(clinic.id);
                      if (!canWrite) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                ref.tr('edit_restricted_subscription'),
                              ),
                            ),
                          );
                        }
                        return;
                      }

                      if (!context.mounted) return;

                      showDialog(
                        context: context,
                        builder: (context) =>
                            MedicalRecordDialog(patient: p, record: record),
                      );
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline, color: Colors.red),
                    onPressed: () async {
                      final clinic = ref.read(clinicStreamProvider).value;
                      if (clinic == null) return;

                      final canWrite = await ref
                          .read(permissionServiceProvider)
                          .canWrite(clinic.id);
                      if (!canWrite) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                ref.tr('delete_restricted_subscription'),
                              ),
                            ),
                          );
                        }
                        return;
                      }

                      if (!context.mounted) return;
                      _showDeleteRecordDialog(context, p, record);
                    },
                  ),
                ],
              ),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Divider(height: 32),
                      if (record.diagnosis.isNotEmpty) ...[
                        _buildRecordDetail(
                          ref.tr('medical_diagnosis'),
                          record.diagnosis,
                        ),
                        const SizedBox(height: 20),
                      ],
                      if (record.doctorNotes.isNotEmpty) ...[
                        _buildRecordDetail(
                          ref.tr('doctor_notes_recommendations'),
                          record.doctorNotes,
                        ),
                        const SizedBox(height: 20),
                      ],
                      if (record.vitalSigns != null) ...[
                        Text(
                          ref.tr('vital_signs'),
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            color: Colors.cyanAccent,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          children: [
                            if (record.vitalSigns!.bloodPressure.isNotEmpty)
                              _buildVitalChip(
                                Icons.speed,
                                '${ref.tr('blood_pressure')}: ${record.vitalSigns!.bloodPressure}',
                              ),
                            if (record.vitalSigns!.weight > 0)
                              _buildVitalChip(
                                Icons.monitor_weight_outlined,
                                '${ref.tr('weight')}: ${record.vitalSigns!.weight} ${ref.tr('kg_unit')}',
                              ),
                            if (record.vitalSigns!.temperature > 0)
                              _buildVitalChip(
                                Icons.thermostat_outlined,
                                '${ref.tr('temperature')}: ${record.vitalSigns!.temperature} °C',
                              ),
                            if (record.vitalSigns!.sugarLevel > 0)
                              _buildVitalChip(
                                Icons.water_drop_outlined,
                                '${ref.tr('sugar_level')}: ${record.vitalSigns!.sugarLevel}',
                              ),
                          ],
                        ),
                        const SizedBox(height: 20),
                      ],
                      const Divider(height: 32),
                      if (record.medications.isNotEmpty) ...[
                        const SizedBox(height: 24),
                        Text(
                          ref.tr('medications_title'),
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white.withAlpha(20),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: Colors.white.withAlpha(40),
                            ),
                          ),
                          child: Column(
                            children: record.medications.map((med) {
                              return Container(
                                margin: const EdgeInsets.only(bottom: 12),
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: Colors.white.withAlpha(20),
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: Colors.white.withAlpha(30),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        color: Colors.white.withAlpha(30),
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(
                                        Icons.medication_outlined,
                                        color: Colors.white,
                                        size: 20,
                                      ),
                                    ),
                                    const SizedBox(width: 16),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            med.name,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 14,
                                              color: Colors.white,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            '${med.dosage} • ${med.frequency}',
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 12,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          if (med.instructions.isNotEmpty)
                                            Container(
                                              margin: const EdgeInsets.only(
                                                top: 8,
                                              ),
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 10,
                                                    vertical: 4,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: Colors.white.withAlpha(
                                                  30,
                                                ),
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                              ),
                                              child: Text(
                                                '💡 ${med.instructions}',
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                    if (med.duration.isNotEmpty)
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 6,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.green.withValues(
                                            alpha: 0.1,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                        ),
                                        child: Text(
                                          med.duration,
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 11,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                      ],
                      if (record.attachmentUrls.isNotEmpty) ...[
                        const SizedBox(height: 24),
                        Text(
                          ref.tr('attachments_title'),
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          height: 250,
                          child: ListView.builder(
                            scrollDirection: Axis.horizontal,
                            itemCount: record.attachmentUrls.length,
                            itemBuilder: (context, i) {
                              return Padding(
                                padding: const EdgeInsets.only(left: 12.0),
                                child: InkWell(
                                  onTap: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) =>
                                            FullScreenImageViewer(
                                              imageUrls: record.attachmentUrls
                                                  .cast<String>(),
                                              initialIndex: i,
                                            ),
                                      ),
                                    );
                                  },
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(16),
                                    child: CachedNetworkImage(
                                      imageUrl: record.attachmentUrls[i],
                                      width: 250,
                                      height: 250,
                                      fit: BoxFit.cover,
                                      placeholder: (context, url) =>
                                          Container(
                                            width: 250,
                                            height: 250,
                                            color: Colors.grey.shade200,
                                            child: const Center(
                                              child:
                                                  CircularProgressIndicator(),
                                            ),
                                          ),
                                      errorWidget:
                                          (context, url, error) =>
                                              Container(
                                                width: 250,
                                                height: 250,
                                                color: Colors.grey.shade200,
                                                child: Column(
                                                  mainAxisAlignment:
                                                      MainAxisAlignment
                                                          .center,
                                                  children: [
                                                    Icon(
                                                      Icons
                                                          .broken_image_outlined,
                                                      size: 40,
                                                      color: Colors.grey,
                                                    ),
                                                    SizedBox(height: 8),
                                                    Text(
                                                      ref.tr(
                                                        'image_load_failed',
                                                      ),
                                                      style: TextStyle(
                                                        color: Colors.grey,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildRecordDetail(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 13,
            color: Colors.cyanAccent,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          value,
          style: const TextStyle(
            fontSize: 14,
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Widget _buildSmallFinanceInfo(String text, Color color, {VoidCallback? onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          text,
          style: TextStyle(
            color: color,
            fontSize: 11,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  Widget _buildVitalChip(IconData icon, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(40),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withAlpha(30)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ScaledIcon(icon, size: 14, color: Colors.blueGrey),
          const SizedBox(width: 6),
          Text(
            value,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHealthAlertCard(
    BuildContext context, {
    required String title,
    required String content,
    required IconData icon,
    required Color color,
    VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(24),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white.withAlpha(30),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.white.withAlpha(50)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 24),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: color.withValues(alpha: 0.9),
                      letterSpacing: 0.3,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    content,
                    style: const TextStyle(
                      fontSize: 15,
                      color: Colors.white,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
            if (onTap != null)
              Icon(
                Icons.edit_note_rounded,
                color: Colors.white.withAlpha(50),
                size: 26,
              ),
          ],
        ),
      ),
    );
  }

  void _showEditChronicDiseasesDialog(BuildContext context, Patient patient) {
    final controller = TextEditingController(text: patient.chronicDiseases);
    showDialog(
      context: context,
      builder: (innerContext) => AlertDialog(
        title: Text(ref.tr('chronic_diseases')),
        content: TextField(
          controller: controller,
          maxLines: 3,
          decoration: InputDecoration(
            hintText: ref.tr('enter_chronic_diseases_hint'),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(innerContext),
            child: Text(ref.tr('cancel')),
          ),
          ElevatedButton(
            onPressed: () async {
              final repo = ref.read(patientRepositoryProvider);
              await repo.updatePatient(
                patient.copyWith(chronicDiseases: controller.text.trim()),
              );
              if (innerContext.mounted) Navigator.pop(innerContext);
            },
            child: Text(ref.tr('save')),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyTabState(IconData icon, String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 64.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ScaledIcon(icon, size: 64, color: Colors.white54),
            const SizedBox(height: 16),
            Text(
              message,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 15,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCurrentVisitCard(BuildContext context, Patient patient) {
    final latestRecords =
        patient.records.where((r) => !r.isFinalized).toList()
          ..sort((a, b) => b.date.compareTo(a.date));

    if (latestRecords.isEmpty) {
      return const SizedBox.shrink();
    }

    final record = latestRecords.first;

    return InkWell(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) =>
                VisitDetailsScreen(patient: patient, record: record),
          ),
        );
      },
      child: Container(
        margin: const EdgeInsets.only(top: 8),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.blue.shade700, Colors.indigo.shade800],
          ),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.blue.withAlpha(40),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.medical_services_outlined,
                  color: Colors.white,
                  size: 22,
                ),
                const SizedBox(width: 8),
                Text(
                  ref.tr('current_visit'),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                const Spacer(),
                const Icon(
                  Icons.arrow_forward_ios,
                  color: Colors.white70,
                  size: 16,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              ref.tr('visit_details_description'),
              style: const TextStyle(color: Colors.white70, fontSize: 13),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white.withAlpha(30),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                DateFormat('yyyy/MM/dd hh:mm a', ref.read(languageProvider).languageCode).format(record.date),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
