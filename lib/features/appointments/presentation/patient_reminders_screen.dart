import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/services.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import '../domain/appointments_provider.dart';
import '../domain/appointment.dart';
import '../../auth/presentation/auth_providers.dart';
import 'package:intl/intl.dart';
import '../../../core/presentation/widgets/animated_gradient_background.dart';
import '../../../core/localization/language_provider.dart';

class PatientRemindersScreen extends ConsumerWidget {
  const PatientRemindersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final upcomingAsync = ref.watch(enrichedUpcomingAppointmentsProvider);
    final selectedDate = ref.watch(remindersDateProvider);

    return Scaffold(
      body: AnimatedGradientBackground(
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            SliverAppBar(
              expandedHeight: 80,
              floating: true,
              pinned: false,
              elevation: 0,
              backgroundColor: Colors.transparent,
              title: Text(
                ref.tr('nav_reminders'),
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 22,
                ),
              ),
              centerTitle: true,
            ),
            SliverToBoxAdapter(
              child: Column(
                children: [
                  _buildDateSelector(context, ref, selectedDate),
                  _buildBulkActions(context, ref, upcomingAsync.value ?? []),
                ],
              ),
            ),
            upcomingAsync.when(
              data: (appointments) {
                if (appointments.isEmpty) {
                  return SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(
                      child: Text(
                        ref.tr('no_upcoming_reminders'),
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  );
                }

                return SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate((context, index) {
                      final appt = appointments[index];
                      final patient = appt.patient;
                      final dateStr = DateFormat(
                        'yyyy/MM/dd',
                        ref.watch(languageProvider).languageCode,
                      ).format(appt.date);

                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: Colors.white.withAlpha(25),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: Colors.white.withAlpha(40)),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      patient?.name ?? ref.tr('unknown_patient'),
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 15,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      ref.tr('appointment_date', [dateStr]),
                                      style: const TextStyle(
                                        color: Colors.white70,
                                        fontSize: 13,
                                      ),
                                    ),
                                    if (patient != null) ...[
                                      const SizedBox(height: 4),
                                      Row(
                                        children: [
                                          Flexible(
                                            child: GestureDetector(
                                              onTap: () => _makeCall(patient.phone),
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  const Icon(
                                                    Icons.phone,
                                                    color: Colors.white70,
                                                    size: 14,
                                                  ),
                                                  const SizedBox(width: 4),
                                                  Flexible(
                                                    child: Text(
                                                      patient.phone,
                                                      overflow: TextOverflow.ellipsis,
                                                      style: const TextStyle(
                                                        color: Colors.white70,
                                                        fontSize: 13,
                                                        decoration: TextDecoration.underline,
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          IconButton(
                                            icon: const Icon(
                                              Icons.copy,
                                              color: Colors.white38,
                                              size: 14,
                                            ),
                                            constraints: const BoxConstraints(),
                                            padding: EdgeInsets.zero,
                                            onPressed: () => _copyToClipboard(
                                              context,
                                              ref,
                                              patient.phone,
                                            ),
                                            tooltip: ref.tr('copy_number'),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    decoration: BoxDecoration(
                                      color: Colors.white.withAlpha(30),
                                      shape: BoxShape.circle,
                                    ),
                                    child: IconButton(
                                      icon: const Icon(
                                        Icons.sms_rounded,
                                        color: Colors.lightBlueAccent,
                                        size: 20,
                                      ),
                                      onPressed: patient != null
                                          ? () => _showMessageOptions(
                                              context,
                                              ref,
                                              patient,
                                              appt.date,
                                              isWhatsApp: false,
                                            )
                                          : null,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Container(
                                    decoration: BoxDecoration(
                                      color: Colors.white.withAlpha(30),
                                      shape: BoxShape.circle,
                                    ),
                                    child: IconButton(
                                      icon: const FaIcon(
                                        FontAwesomeIcons.whatsapp,
                                        color: Color(0xFF25D366),
                                        size: 20,
                                      ),
                                      onPressed: patient != null
                                          ? () => _showMessageOptions(
                                              context,
                                              ref,
                                              patient,
                                              appt.date,
                                              isWhatsApp: true,
                                            )
                                          : null,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    }, childCount: appointments.length),
                  ),
                );
              },
              loading: () => const SliverFillRemaining(
                child: Center(
                  child: CircularProgressIndicator(color: Colors.white),
                ),
              ),
              error: (e, st) => SliverFillRemaining(
                child: Center(
                  child: Text(
                    ref.tr('error_label', [e.toString()]),
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDateSelector(
    BuildContext context,
    WidgetRef ref,
    DateTime selectedDate,
  ) {
    final tomorrow = DateTime.now().add(const Duration(days: 1));
    final isTomorrow =
        selectedDate.year == tomorrow.year &&
        selectedDate.month == tomorrow.month &&
        selectedDate.day == tomorrow.day;

    final today = DateTime.now();
    final isToday =
        selectedDate.year == today.year &&
        selectedDate.month == today.month &&
        selectedDate.day == today.day;

    String dateLabel;
    if (isToday) {
      dateLabel = ref.tr('today');
    } else if (isTomorrow) {
      dateLabel = ref.tr('tomorrow');
    } else {
      dateLabel = DateFormat(
        'yyyy/MM/dd',
        ref.watch(languageProvider).languageCode,
      ).format(selectedDate);
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: Row(
        children: [
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.white.withAlpha(30),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white.withAlpha(50)),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.calendar_today,
                    color: Colors.white70,
                    size: 18,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      ref.tr('view_appointments_for', [dateLabel]),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          Container(
            decoration: BoxDecoration(
              color: Colors.white.withAlpha(40),
              borderRadius: BorderRadius.circular(16),
            ),
            child: IconButton(
              icon: const Icon(Icons.edit_calendar, color: Colors.white),
              onPressed: () => _selectDate(context, ref, selectedDate),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBulkActions(
    BuildContext context,
    WidgetRef ref,
    List<Appointment> appointments,
  ) {
    if (appointments.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: _buildBulkButton(
              context,
              color: Colors.lightBlueAccent,
              icon: Icons.sms_rounded,
              label: ref.tr('send_sms_all'),
              onPressed: () => _sendBulkReminder(
                context,
                ref,
                appointments,
                isWhatsApp: false,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _buildBulkButton(
              context,
              color: const Color(0xFF25D366),
              icon: FontAwesomeIcons.whatsapp,
              label: ref.tr('send_whatsapp_all'),
              onPressed: () => _sendBulkReminder(
                context,
                ref,
                appointments,
                isWhatsApp: true,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBulkButton(
    BuildContext context, {
    required Color color,
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
  }) {
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: color.withAlpha(30),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withAlpha(60)),
        ),
        child: Column(
          children: [
            FaIcon(icon, color: color, size: 20),
            const SizedBox(height: 4),
            Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _selectDate(
    BuildContext context,
    WidgetRef ref,
    DateTime currentDate,
  ) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: currentDate,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.light(
              primary: Theme.of(context).primaryColor,
              onPrimary: Colors.white,
              onSurface: Colors.black,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null && context.mounted) {
      ref.read(remindersDateProvider.notifier).setDate(picked);
    }
  }

  Future<void> _showMessageOptions(
    BuildContext context,
    WidgetRef ref,
    dynamic patient, // Patient model
    DateTime date, {
    required bool isWhatsApp,
  }) async {
    final dateStr = DateFormat(
      'yyyy/MM/dd',
      ref.watch(languageProvider).languageCode,
    ).format(date);

    final clinic = ref.watch(clinicStreamProvider).value;
    final admin = ref.watch(clinicAdminProvider).value;

    final clinicName = clinic?.name ?? '';
    final doctorName = admin?.name ?? '';

    String signature = '';
    if (clinicName.isNotEmpty || doctorName.isNotEmpty) {
      signature = '\n\n';
      if (clinicName.isNotEmpty) {
        signature += '${ref.tr('clinic_prefix')} $clinicName\n';
      }
      if (doctorName.isNotEmpty) {
        signature += '${ref.tr('dr_prefix')} $doctorName';
      }
    }

    final reminderMsg = ref.tr('reminder_msg_template', [dateStr]) + signature;
    final followUpMsg = ref.tr('followup_msg_template') + signature;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: const Color(0xFF1A237E).withValues(alpha: 0.95),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              ref.tr('select_msg_type'),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 20),
            _buildOptionItem(
              context,
              icon: Icons.notifications_active_outlined,
              title: ref.tr('reminder_msg_title'),
              subtitle: ref.tr('reminder_msg_sub'),
              onTap: () {
                Navigator.pop(context);
                if (isWhatsApp) {
                  _sendWhatsApp(patient.phone, reminderMsg);
                } else {
                  _sendSms(patient.phone, reminderMsg);
                }
              },
            ),
            const Divider(color: Colors.white12, height: 1),
            _buildOptionItem(
              context,
              icon: Icons.favorite_border,
              title: ref.tr('followup_msg_title'),
              subtitle: ref.tr('followup_msg_sub'),
              onTap: () {
                Navigator.pop(context);
                if (isWhatsApp) {
                  _sendWhatsApp(patient.phone, followUpMsg);
                } else {
                  _sendSms(patient.phone, followUpMsg);
                }
              },
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildOptionItem(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Icon(icon, color: Colors.blueAccent),
      title: Text(title, style: const TextStyle(color: Colors.white)),
      subtitle: Text(subtitle, style: const TextStyle(color: Colors.white70)),
      onTap: onTap,
    );
  }

  Future<void> _sendWhatsApp(String phone, String message) async {
    // Sanitize phone number (remove non-digits)
    String cleanPhone = phone.replaceAll(RegExp(r'\D'), '');

    // Auto-fix for Egyptian numbers (e.g., 01012345678 -> 201012345678)
    if (cleanPhone.startsWith('0') && cleanPhone.length == 11) {
      cleanPhone = '2$cleanPhone';
    } else if (cleanPhone.length == 10 &&
        (cleanPhone.startsWith('10') ||
            cleanPhone.startsWith('11') ||
            cleanPhone.startsWith('12') ||
            cleanPhone.startsWith('15'))) {
      // If user typed 10 digits starting with 10, 11, etc. (missing leading 0)
      cleanPhone = '20$cleanPhone';
    }

    // Use whatsapp:// for more direct app opening, fallback to wa.me
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

  Future<void> _sendSms(String phone, String message) async {
    final cleanPhone = phone.replaceAll(RegExp(r'\D'), '');
    final uri = Uri(
      scheme: 'sms',
      path: cleanPhone,
      queryParameters: {'body': message},
    );

    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _makeCall(String phone) async {
    final uri = Uri(scheme: 'tel', path: phone);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  void _copyToClipboard(BuildContext context, WidgetRef ref, String text) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ref.tr('phone_copied')),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _sendBulkReminder(
    BuildContext context,
    WidgetRef ref,
    List<Appointment> appointments, {
    required bool isWhatsApp,
  }) {
    final type = isWhatsApp ? ref.tr('whatsapp') : 'SMS';
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(ref.tr('bulk_send_title', [type])),
        content: Text(
          ref.tr('bulk_send_confirm', [type, appointments.length.toString()]),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(ref.tr('cancel')),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _showBulkProcessDialog(
                context,
                ref,
                appointments,
                isWhatsApp: isWhatsApp,
              );
            },
            child: Text(ref.tr('start_bulk_send')),
          ),
        ],
      ),
    );
  }

  void _showBulkProcessDialog(
    BuildContext context,
    WidgetRef ref,
    List<Appointment> appointments, {
    required bool isWhatsApp,
  }) {
    int current = 0;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          final appt = appointments[current];
          final type = isWhatsApp ? ref.tr('whatsapp') : 'SMS';
          return AlertDialog(
            title: Text(
              ref.tr('bulk_process_title', [
                type,
                (current + 1).toString(),
                appointments.length.toString(),
              ]),
            ),
            content: Text(
              ref.tr('patient_label', [
                appt.patient?.name ?? ref.tr('unknown_patient'),
              ]),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(ref.tr('stop')),
              ),
              ElevatedButton(
                onPressed: () async {
                  final dateStr = DateFormat(
                    'yyyy/MM/dd',
                    ref.watch(languageProvider).languageCode,
                  ).format(appt.date);
                  final clinic = ref.watch(clinicStreamProvider).value;
                  final admin = ref.watch(clinicAdminProvider).value;

                  final clinicName = clinic?.name ?? '';
                  final doctorName = admin?.name ?? '';

                  String signature = '';
                  if (clinicName.isNotEmpty || doctorName.isNotEmpty) {
                    signature = '\n\n';
                    if (clinicName.isNotEmpty) signature += '$clinicName\n';
                    if (doctorName.isNotEmpty) {
                      signature += '${ref.tr('dr_prefix')} $doctorName';
                    }
                  }

                  final message =
                      ref.tr('reminder_msg_template', [dateStr]) + signature;
                  if (isWhatsApp) {
                    await _sendWhatsApp(appt.patient?.phone ?? '', message);
                  } else {
                    await _sendSms(appt.patient?.phone ?? '', message);
                  }

                  if (context.mounted) {
                    if (current < appointments.length - 1) {
                      setState(() => current++);
                    } else {
                      Navigator.pop(context);
                    }
                  }
                },
                child: Text(
                  current == appointments.length - 1
                      ? ref.tr('finish')
                      : ref.tr('next'),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
