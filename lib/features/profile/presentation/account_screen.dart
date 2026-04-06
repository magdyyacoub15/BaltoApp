import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../auth/presentation/auth_providers.dart';
import '../../auth/data/auth_repository.dart';
import '../../auth/domain/models/clinic_group.dart';
import '../../admin/presentation/admin_management_screen.dart';
import 'subscription_page.dart';
import 'super_admin_page.dart';
import 'clinics_manager_dialog.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../core/localization/language_provider.dart';
import '../../../core/presentation/widgets/animated_gradient_background.dart';
import 'tutorial_video_page.dart';

class AccountScreen extends ConsumerWidget {
  const AccountScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userAsync = ref.watch(currentUserProvider);

    return Scaffold(
      body: AnimatedGradientBackground(
        child: userAsync.when(
          data: (user) {
            if (user == null) {
              return Center(
                child: Text(
                  ref.tr('user_data_not_found'),
                  style: const TextStyle(color: Colors.white),
                ),
              );
            }

            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 800),
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
                        ref.tr('account_title'),
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
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Action Icons (Left side or Wrap)
                                Wrap(
                                  direction: Axis.vertical,
                                  spacing: 0,
                                  children: [
                                    IconButton(
                                      visualDensity: VisualDensity.compact,
                                      icon: const Icon(Icons.language, color: Colors.white, size: 20),
                                      onPressed: () => _showLanguageDialog(context, ref),
                                      tooltip: ref.tr('change_language'),
                                    ),
                                    IconButton(
                                      visualDensity: VisualDensity.compact,
                                      icon: const Icon(Icons.format_size, color: Colors.white, size: 20),
                                      onPressed: () => _showScaleDialog(context, ref),
                                      tooltip: ref.tr('change_scale'),
                                    ),
                                    IconButton(
                                      visualDensity: VisualDensity.compact,
                                      icon: const Icon(Icons.corporate_fare, color: Colors.white, size: 20),
                                      onPressed: () {
                                        final user = ref.read(currentUserProvider).value;
                                        if (user != null) {
                                          _showClinicsDialog(
                                            context, ref, user.id, user.clinicId,
                                            userEmail: user.email,
                                          );
                                        }
                                      },
                                      tooltip: ref.tr('my_groups'),
                                    ),
                                    IconButton(
                                      visualDensity: VisualDensity.compact,
                                      icon: const Icon(Icons.info_outline, color: Colors.white, size: 20),
                                      onPressed: () => _showInfoDialog(context, ref),
                                      tooltip: ref.tr('about_app'),
                                    ),
                                  ],
                                ),
                                // User Info Section (Expanded to take middle space)
                                Expanded(
                                  child: Column(
                                    children: [
                                      const CircleAvatar(
                                        radius: 50,
                                        backgroundColor: Colors.white24,
                                        child: Icon(Icons.person, size: 60, color: Colors.white),
                                      ),
                                      const SizedBox(height: 16),
                                      FittedBox(
                                        fit: BoxFit.scaleDown,
                                        child: Text(
                                          user.name,
                                          style: const TextStyle(
                                            fontSize: 22,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.white,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      FittedBox(
                                        fit: BoxFit.scaleDown,
                                        child: Text(
                                          user.email,
                                          style: const TextStyle(fontSize: 14, color: Colors.white70),
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      FittedBox(
                                        fit: BoxFit.scaleDown,
                                        child: Text(
                                          '${user.phone} • ${user.isAdmin ? ref.tr('admin') : ref.tr('secretary')}',
                                          style: const TextStyle(fontSize: 12, color: Colors.white54),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                // Placeholder for symmetry or more actions
                                const SizedBox(width: 40),
                              ],
                            ),
                          ),
                          const SizedBox(height: 30),

                          // Contact Us Section
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 24.0,
                            ),
                            child: _buildContactUsSection(context, ref),
                          ),

                          const SizedBox(height: 30),

                          // App Group Section
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 24.0,
                            ),
                            child: _buildAppGroupSection(context, ref),
                          ),

                          // Tutorial Video Button
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 24.0,
                              vertical: 10,
                            ),
                            child: ElevatedButton.icon(
                              onPressed: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) =>
                                        const TutorialVideoPage(),
                                  ),
                                );
                              },
                              icon: const Icon(
                                Icons.play_circle_fill,
                                color: Colors.redAccent,
                                size: 28,
                              ),
                              label: Flexible(
                                child: Text(
                                  ref.tr('tutorial_video_btn'),
                                ),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.white,
                                foregroundColor: Colors.black,
                                minimumSize: const Size(double.infinity, 50),
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(15),
                                ),
                              ),
                            ),
                          ),

                          // Subscription Button
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 24.0,
                              vertical: 15,
                            ),
                            child: ElevatedButton.icon(
                              onPressed: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) =>
                                        const SubscriptionPage(),
                                  ),
                                );
                              },
                              icon: const Icon(Icons.star, color: Colors.blue),
                              label: Flexible(
                                child: Text(
                                  ref.tr('subscription_details'),
                                ),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.white,
                                foregroundColor: Colors.black,
                                minimumSize: const Size(double.infinity, 50),
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(15),
                                ),
                              ),
                            ),
                          ),

                          // Admin Management Button
                          if (ref.watch(isAdminProvider).value ?? false)
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 24.0,
                                vertical: 15,
                              ),
                              child: ElevatedButton.icon(
                                onPressed: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) =>
                                          const AdminManagementScreen(),
                                    ),
                                  );
                                },
                                icon: const Icon(
                                  Icons.admin_panel_settings,
                                  color: Colors.lightBlue,
                                ),
                                label: Flexible(
                                  child: Text(
                                    ref.tr('manage_clinic'),
                                  ),
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.white,
                                  foregroundColor: Colors.black,
                                  minimumSize: const Size(double.infinity, 50),
                                  elevation: 0,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(15),
                                  ),
                                ),
                              ),
                            ),

                          // Clinic Prescription Settings Button
                          if (ref.watch(isAdminProvider).value ?? false)
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 24.0,
                                vertical: 15,
                              ),
                              child: ElevatedButton.icon(
                                onPressed: () {
                                  final clinic = ref
                                      .read(clinicStreamProvider)
                                      .value;
                                  if (clinic != null) {
                                    _showClinicSettingsDialog(
                                      context,
                                      ref,
                                      clinic,
                                    );
                                  }
                                },
                                icon: const Icon(
                                  Icons.settings_suggest,
                                  color: Colors.orangeAccent,
                                ),
                                label: Flexible(
                                  child: Text(
                                    ref.tr('clinic_settings'),
                                  ),
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.white,
                                  foregroundColor: Colors.black,
                                  minimumSize: const Size(double.infinity, 50),
                                  elevation: 0,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(15),
                                  ),
                                ),
                              ),
                            ),

                          // Super Admin Button
                          if (user.email == 'magdyyacoub41@gmail.com')
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 24.0,
                                vertical: 15,
                              ),
                              child: ElevatedButton.icon(
                                onPressed: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) =>
                                          const SuperAdminPage(),
                                    ),
                                  );
                                },
                                icon: const Icon(
                                  Icons.admin_panel_settings,
                                  color: Colors.red,
                                ),
                                label: Flexible(
                                  child: Text(
                                    ref.tr('super_admin_panel'),
                                  ),
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.white,
                                  foregroundColor: Colors.black,
                                  minimumSize: const Size(double.infinity, 50),
                                  elevation: 0,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(15),
                                  ),
                                ),
                              ),
                            ),

                          const SizedBox(height: 32),

                          ElevatedButton.icon(
                            onPressed: () =>
                                ref.read(authRepositoryProvider).logOut(),
                            icon: const Icon(Icons.logout),
                            label: Text(ref.tr('logout')),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red.shade400,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 24,
                                vertical: 12,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(20),
                              ),
                            ),
                          ),
                          const SizedBox(height: 32),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
          loading: () => const Center(
            child: CircularProgressIndicator(color: Colors.white),
          ),
          error: (e, st) => Center(
            child: Text(
              ref.tr('error_label', [e.toString()]),
              style: const TextStyle(color: Colors.white),
            ),
          ),
        ),
      ),
    );
  }

  void _showScaleDialog(BuildContext context, WidgetRef ref) {
    final currentScale = ref.read(appScaleProvider);

    final options = [
      {'label': ref.tr('font_small'), 'value': 0.8},
      {'label': ref.tr('font_normal'), 'value': 1.0},
      {'label': ref.tr('font_medium'), 'value': 1.2},
      {'label': ref.tr('font_large'), 'value': 1.4},
      {'label': ref.tr('font_extra_large'), 'value': 1.6},
    ];

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(ref.tr('change_scale')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: options.map((opt) {
              final label = opt['label'] as String;
              final value = opt['value'] as double;
              return RadioListTile<double>(
                title: Text(label),
                value: value,
                groupValue: currentScale,
                onChanged: (val) {
                  if (val != null) {
                    ref.read(appScaleProvider.notifier).setScale(val);
                    Navigator.pop(context);
                  }
                },
              );
            }).toList(),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(ref.tr('cancel')),
            ),
          ],
        );
      },
    );
  }

  Widget _buildContactUsSection(BuildContext context, WidgetRef ref) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(25),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: Colors.white.withAlpha(51)),
      ),
      child: Column(
        children: [
          Text(
            ref.tr('contact_us'),
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildSocialButton(
                icon: Icons.chat_bubble_outline,
                label: ref.tr('whatsapp'),
                color: Colors.green.shade400,
                onTap: () => _launchURL("https://wa.me/qr/PVCRF6JDXXLVD1"),
              ),
              _buildSocialButton(
                icon: Icons.camera_alt_outlined,
                label: ref.tr('instagram'),
                color: Colors.pink.shade400,
                onTap: () => _launchURL(
                  "https://www.instagram.com/magdyyacoub0?igsh=MXFyb2ZwcjJtbGNwYg==",
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAppGroupSection(BuildContext context, WidgetRef ref) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(25),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: Colors.white.withAlpha(51)),
      ),
      child: Column(
        children: [
          Text(
            ref.tr('official_group'),
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildSocialButton(
                icon: Icons.chat_bubble_outline,
                label: ref.tr('whatsapp_official'),
                color: Colors.green.shade400,
                onTap: () => _launchURL(
                  "https://chat.whatsapp.com/HZQmatPpF1QFF61NVxm5Um?mode=gi_t",
                ),
              ),
              _buildSocialButton(
                icon: Icons.send,
                label: ref.tr('telegram_official'),
                color: Colors.blue.shade400,
                onTap: () => _launchURL("https://t.me/+Tc7-CpyO4nsyZTRk"),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSocialButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color.withAlpha(51), // equivalent to withOpacity(0.2)
              shape: BoxShape.circle,
              border: Border.all(color: color.withAlpha(128)),
            ),
            child: Icon(icon, color: color, size: 28),
          ),
          const SizedBox(height: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              label,
              style: const TextStyle(color: Colors.white, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _launchURL(String url) async {
    final Uri uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      debugPrint('Could not launch \$url');
    }
  }

  void _showClinicsDialog(
    BuildContext context,
    WidgetRef ref,
    String userId,
    String activeClinicId, {
    String userEmail = '',
  }) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => ClinicsManagerDialog(
        userId: userId,
        activeClinicId: activeClinicId,
        authRepo: ref.read(authRepositoryProvider),
        userEmail: userEmail,
      ),
    );
  }

  void _showLanguageDialog(BuildContext context, WidgetRef ref) {
    final currentLocale = ref.read(languageProvider);

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(ref.tr('select_language')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              RadioListTile<String>(
                title: Text(ref.tr('arabic')),
                value: 'ar',
                groupValue: currentLocale.languageCode,
                onChanged: (val) {
                  if (val != null) {
                    ref.read(languageProvider.notifier).setLanguage(val);
                    Navigator.pop(context);
                  }
                },
              ),
              RadioListTile<String>(
                title: Text(ref.tr('english')),
                value: 'en',
                groupValue: currentLocale.languageCode,
                onChanged: (val) {
                  if (val != null) {
                    ref.read(languageProvider.notifier).setLanguage(val);
                    Navigator.pop(context);
                  }
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(ref.tr('cancel')),
            ),
          ],
        );
      },
    );
  }

  void _showInfoDialog(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.info_outline, color: Color(0xFF0277BD)),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                ref.tr('about_app_security'),
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                ref.tr('about_app_desc'),
                textAlign: TextAlign.right,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Divider(height: 30),
              _buildSecurityPoint(
                ref.tr('sec_encryption_title'),
                ref.tr('sec_encryption_desc'),
              ),
              const SizedBox(height: 12),
              _buildSecurityPoint(
                ref.tr('sec_anti_hack_title'),
                ref.tr('sec_anti_hack_desc'),
              ),
              const SizedBox(height: 12),
              _buildSecurityPoint(
                ref.tr('sec_password_hash_title'),
                ref.tr('sec_password_hash_desc'),
              ),
              const SizedBox(height: 12),
              _buildSecurityPoint(
                ref.tr('sec_media_sec_title'),
                ref.tr('sec_media_sec_desc'),
              ),
              const SizedBox(height: 12),
              _buildSecurityPoint(
                ref.tr('sec_data_isolation_title'),
                ref.tr('sec_data_isolation_desc'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              ref.tr('close'),
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSecurityPoint(String title, String description) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Flexible(
              child: Text(
                title,
                textAlign: TextAlign.right,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: Color(0xFF0277BD),
                  height: 1.3,
                ),
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.check_circle, size: 16, color: Colors.green),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          description,
          textAlign: TextAlign.right,
          style: const TextStyle(
            fontSize: 13,
            color: Colors.black87,
            height: 1.3,
          ),
        ),
      ],
    );
  }

  void _showClinicSettingsDialog(
    BuildContext context,
    WidgetRef ref,
    ClinicGroup clinic,
  ) {
    final nameController = TextEditingController(text: clinic.name);
    final doctorNameController = TextEditingController(
      text: clinic.doctorName ?? '',
    );
    final addressController = TextEditingController(text: clinic.address ?? '');
    final phoneController = TextEditingController(text: clinic.phone ?? '');
    final specController = TextEditingController(
      text: clinic.specialization ?? '',
    );

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(ref.tr('clinic_settings')),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  decoration: InputDecoration(labelText: ref.tr('clinic_name')),
                ),
                TextField(
                  controller: doctorNameController,
                  decoration: InputDecoration(
                    labelText: ref.tr('prescription_doctor_name'),
                  ),
                ),
                TextField(
                  controller: specController,
                  decoration: InputDecoration(
                    labelText: ref.tr('specialization'),
                  ),
                ),
                TextField(
                  controller: addressController,
                  decoration: InputDecoration(
                    labelText: ref.tr('clinic_address'),
                  ),
                ),
                TextField(
                  controller: phoneController,
                  decoration: InputDecoration(
                    labelText: ref.tr('clinic_phone'),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(ref.tr('cancel')),
            ),
            ElevatedButton(
              onPressed: () async {
                final updatedClinic = ClinicGroup(
                  id: clinic.id,
                  name: nameController.text.trim(),
                  clinicCode: clinic.clinicCode,
                  createdAt: clinic.createdAt,
                  lastShiftReset: clinic.lastShiftReset,
                  subscriptionEndDate: clinic.subscriptionEndDate,
                  isTrial: clinic.isTrial,
                  doctorName: doctorNameController.text.trim(),
                  address: addressController.text.trim(),
                  phone: phoneController.text.trim(),
                  specialization: specController.text.trim(),
                );

                try {
                  await ref
                      .read(authRepositoryProvider)
                      .updateClinic(updatedClinic);
                  ref.invalidate(clinicStreamProvider);
                  if (context.mounted) {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(ref.tr('clinic_info_updated'))),
                    );
                  }
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(ref.tr('error_label', [e.toString()])),
                      ),
                    );
                  }
                }
              },
              child: Text(ref.tr('save')),
            ),
          ],
        );
      },
    );
  }
}
