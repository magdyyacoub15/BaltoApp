import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../domain/patients_provider.dart';
import '../data/patient_repository.dart';
import 'patient_profile_screen.dart';
import '../../../core/presentation/widgets/scaled_icon.dart';
import '../../../core/presentation/widgets/animated_gradient_background.dart';
import '../../../core/presentation/widgets/delete_confirmation_dialog.dart';
import '../../../core/services/permission_service.dart';
import '../../auth/presentation/auth_providers.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import '../../../core/localization/language_provider.dart';
import 'debt_payment_dialog.dart';

class PatientsListScreen extends ConsumerStatefulWidget {
  const PatientsListScreen({super.key});

  @override
  ConsumerState<PatientsListScreen> createState() => _PatientsListScreenState();
}

class _PatientsListScreenState extends ConsumerState<PatientsListScreen> {
  late TextEditingController _searchController;
  late FocusNode _searchFocusNode;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
    _searchFocusNode = FocusNode();

    // Sync controller with initial provider state if any
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _searchController.text = ref.read(searchQueryProvider);
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  void _clearSearch() {
    _searchController.clear();
    ref.read(searchQueryProvider.notifier).update('');
    _searchFocusNode.unfocus();
  }

  @override
  Widget build(BuildContext context) {
    final patientsAsync = ref.watch(filteredPatientsProvider);
    final allPatientsAsync = ref.watch(patientsStreamProvider);
    final isSearching = ref.watch(searchQueryProvider).isNotEmpty;

    return PopScope(
      canPop: !isSearching,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (isSearching) {
          _clearSearch();
        }
      },
      child: Scaffold(
        body: AnimatedGradientBackground(
          child: CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              SliverAppBar(
                expandedHeight: 140,
                floating: false,
                pinned: false,
                elevation: 0,
                backgroundColor: Colors.transparent,
                iconTheme: const IconThemeData(color: Colors.white),
                title: const SizedBox.shrink(),
                centerTitle: true,
                flexibleSpace: FlexibleSpaceBar(
                  background: SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  ref.tr('welcome'),
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 14,
                                  ),
                                ),
                                FittedBox(
                                  fit: BoxFit.scaleDown,
                                  alignment: Alignment.centerRight,
                                  child: Text(
                                    ref.tr('patients_record'),
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 20,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          allPatientsAsync.maybeWhen(
                            data: (allPatients) {
                              final debtPatients = allPatients
                                  .where((p) => p.remainingAmount > 0)
                                  .toList();

                              return IntrinsicWidth(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    // Total Patients (Rectangular)
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 14,
                                        vertical: 6,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.white.withAlpha(30),
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(
                                          color: Colors.white.withAlpha(20),
                                        ),
                                      ),
                                      child: Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            '${ref.watch(filteredPatientsProvider).maybeWhen(data: (p) => p.length, orElse: () => 0)}',
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 15,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          const SizedBox(width: 6),
                                          Text(
                                            ref.tr('patients_count'),
                                            style: const TextStyle(
                                              color: Colors.white70,
                                              fontSize: 11,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    // Stats Row
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.end,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        allPatientsAsync.maybeWhen(
                                          data: (all) =>
                                              _buildBirthdayBadge(context, all),
                                          orElse: () => const SizedBox.shrink(),
                                        ),
                                        if (debtPatients.isNotEmpty) ...[
                                          const SizedBox(width: 8),
                                          InkWell(
                                            onTap: () =>
                                                _showOutstandingBalancesDialog(
                                                  context,
                                                  debtPatients,
                                                ),
                                            borderRadius: BorderRadius.circular(
                                              10,
                                            ),
                                            child: Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 8,
                                                    vertical: 4,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: Colors.redAccent
                                                    .withAlpha(40),
                                                borderRadius:
                                                    BorderRadius.circular(10),
                                                border: Border.all(
                                                  color: Colors.redAccent
                                                      .withAlpha(50),
                                                ),
                                              ),
                                              child: Column(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Text(
                                                    '${debtPatients.length}',
                                                    style: const TextStyle(
                                                      color: Colors.white,
                                                      fontSize: 14,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                    ),
                                                  ),
                                                  Text(
                                                    ref.tr('debt'),
                                                    style: const TextStyle(
                                                      color: Colors.white70,
                                                      fontSize: 8,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ],
                                ),
                              );
                            },
                            orElse: () => const SizedBox.shrink(),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
                  child: Row(
                    children: [
                      Expanded(
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.white.withAlpha(220),
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withAlpha(10),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: TextField(
                            controller: _searchController,
                            focusNode: _searchFocusNode,
                            onChanged: (value) => ref
                                .read(searchQueryProvider.notifier)
                                .update(value),
                            style: const TextStyle(
                              color: Color(0xFF1E293B),
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                            ),
                            decoration: InputDecoration(
                              hintText: ref.tr('search_hint'),
                              prefixIcon: Icon(
                                Icons.manage_search_rounded,
                                color: Colors.teal.shade700,
                                size: 28,
                              ),
                              suffixIcon:
                                  ref.watch(searchQueryProvider).isNotEmpty
                                  ? IconButton(
                                      icon: Icon(
                                        Icons.close_rounded,
                                        color: Colors.grey.shade600,
                                        size: 20,
                                      ),
                                      onPressed: _clearSearch,
                                    )
                                  : null,
                              border: InputBorder.none,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 20,
                                vertical: 16,
                              ),
                              hintStyle: TextStyle(
                                fontSize: 15,
                                color: Colors.blueGrey.shade300,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Container(
                        height: 56,
                        width: 56,
                        decoration: BoxDecoration(
                          color: Colors.white.withAlpha(220),
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: IconButton(
                          icon: Icon(
                            Icons.tune_rounded,
                            color: Colors.teal.shade700,
                          ),
                          onPressed: () => _showSortDialog(context, ref),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              ...patientsAsync.when(
                skipLoadingOnRefresh: true,
                skipLoadingOnReload: true,
                data: (patients) {
                  if (patients.isEmpty) {
                    return [SliverToBoxAdapter(child: _buildEmptyState())];
                  }
                  return [
                    SliverPadding(
                      padding: const EdgeInsets.symmetric(horizontal: 24.0),
                      sliver: SliverList(
                        delegate: SliverChildBuilderDelegate((context, index) {
                          final patient = patients[index];
                          return _buildPatientCard(context, ref, patient);
                        }, childCount: patients.length),
                      ),
                    ),
                  ];
                },
                loading: () => [
                  const SliverToBoxAdapter(
                    child: Center(
                      child: Padding(
                        padding: EdgeInsets.all(40.0),
                        child: CircularProgressIndicator(color: Colors.white),
                      ),
                    ),
                  ),
                ],
                error: (e, st) => [
                  SliverToBoxAdapter(
                    child: Center(
                      child: Text(
                        ref.tr('error_occurred', [e]),
                        style: const TextStyle(color: Colors.white),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBirthdayBadge(BuildContext context, List<dynamic> patients) {
    final now = DateTime.now();
    final birthdayPatients = patients.where((p) {
      return p.dateOfBirth.day == now.day && p.dateOfBirth.month == now.month;
    }).toList();

    if (birthdayPatients.isEmpty) return const SizedBox.shrink();

    return InkWell(
      onTap: () => _showBirthdaysDialog(context, birthdayPatients),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.orangeAccent.withAlpha(40),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.orangeAccent.withAlpha(50)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${birthdayPatients.length}',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              ref.tr('birthday'),
              style: const TextStyle(color: Colors.white70, fontSize: 8),
            ),
          ],
        ),
      ),
    );
  }

  void _showBirthdaysDialog(BuildContext context, List<dynamic> patients) {
    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          child: Container(
            constraints: const BoxConstraints(maxWidth: 400, maxHeight: 600),
            decoration: BoxDecoration(
              color: const Color(0xFF1A237E),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Colors.white12),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AppBar(
                  backgroundColor: Colors.transparent,
                  elevation: 0,
                  centerTitle: true,
                  title: Text(
                    ref.tr('birthdays_today'),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  automaticallyImplyLeading: false,
                  actions: [
                    IconButton(
                      icon: const Icon(
                        Icons.close_rounded,
                        color: Colors.white,
                      ),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
                const Divider(color: Colors.white12, height: 1),
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    padding: const EdgeInsets.all(16),
                    itemCount: patients.length,
                    separatorBuilder: (context, index) =>
                        const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final p = patients[index];

                      final clinic = ref.watch(clinicStreamProvider).value;
                      final admin = ref.watch(clinicAdminProvider).value;

                      final clinicName = clinic?.name ?? '';
                      final doctorName = admin?.name ?? '';

                      String signature = '';
                      if (clinicName.isNotEmpty || doctorName.isNotEmpty) {
                        signature = '\n\n';
                        if (clinicName.isNotEmpty) {
                          signature +=
                              '${ref.tr('clinic_prefix')} $clinicName\n';
                        }
                        if (doctorName.isNotEmpty) {
                          signature += '${ref.tr('dr_prefix')} $doctorName';
                        }
                      }

                      final bdayMsg = ref.tr('congratulations') + signature;

                      return Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white.withAlpha(10),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        p.name,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 15,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        '${p.age} ${ref.tr('years_old')}',
                                        style: const TextStyle(
                                          color: Colors.orangeAccent,
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Wrap(
                              spacing: 16,
                              runSpacing: 8,
                              alignment: WrapAlignment.center,
                              children: [
                                _buildActionIcon(
                                  icon: Icons.phone_enabled,
                                  color: Colors.blue,
                                  onTap: () => _makeCall(p.phone),
                                ),
                                _buildActionIcon(
                                  icon: Icons.message,
                                  color: Colors.blue,
                                  onTap: () => _sendSms(p.phone, bdayMsg),
                                ),
                                _buildActionIcon(
                                  icon: FontAwesomeIcons.whatsapp,
                                  isFontAwesome: true,
                                  color: Colors.green,
                                  onTap: () => _sendWhatsApp(p.phone, bdayMsg),
                                ),
                              ],
                            ),
                          ],
                        ),
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
  }

  Widget _buildActionIcon({
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
    bool isFontAwesome = false,
  }) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: color.withAlpha(40),
          shape: BoxShape.circle,
        ),
        child: isFontAwesome
            ? FaIcon(icon, color: color, size: 20)
            : Icon(icon, color: color, size: 20),
      ),
    );
  }

  Future<void> _sendWhatsApp(String phone, String message) async {
    final cleanPhone = phone.replaceAll(RegExp(r'\D'), '');
    final url =
        "https://wa.me/2$cleanPhone?text=${Uri.encodeComponent(message)}";
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _sendSms(String phone, String message) async {
    final uri = Uri(
      scheme: 'sms',
      path: phone,
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

  void _showOutstandingBalancesDialog(
    BuildContext context,
    List<dynamic> debtPatients,
  ) {
    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          child: Container(
            constraints: const BoxConstraints(maxWidth: 400, maxHeight: 600),
            decoration: BoxDecoration(
              color: const Color(0xFF1A237E),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Colors.white12),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AppBar(
                  backgroundColor: Colors.transparent,
                  elevation: 0,
                  centerTitle: true,
                  title: Text(
                    ref.tr('debt'),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  automaticallyImplyLeading: false,
                  actions: [
                    IconButton(
                      icon: const Icon(
                        Icons.close_rounded,
                        color: Colors.white,
                      ),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
                const Divider(color: Colors.white12, height: 1),
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    padding: const EdgeInsets.all(16),
                    itemCount: debtPatients.length,
                    separatorBuilder: (context, index) =>
                        const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final p = debtPatients[index];
                      return Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white.withAlpha(10),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    p.name,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 15,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '${ref.tr('remaining_amount')}: ${p.remainingAmount} ${ref.tr('currency')}',
                                    style: const TextStyle(
                                      color: Colors.redAccent,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Wrap(
                              spacing: 0,
                              runSpacing: 0,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                IconButton(
                                  icon: const Icon(
                                    Icons.payments_outlined,
                                    color: Colors.green,
                                  ),
                                  onPressed: () {
                                    try {
                                      final recordWithDebt = p.records.firstWhere(
                                        (r) => r.remainingAmount > 0,
                                      );
                                      showDialog(
                                        context: context,
                                        builder: (context) => DebtPaymentDialog(
                                          patient: p,
                                          record: recordWithDebt,
                                        ),
                                      );
                                    } catch (e) {
                                      // Fallback to profile if something is weird
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (context) =>
                                              PatientProfileScreen(patient: p),
                                        ),
                                      );
                                    }
                                  },
                                ),
                                IconButton(
                                  icon: const Icon(
                                    Icons.person_outline,
                                    color: Colors.blueAccent,
                                  ),
                                  onPressed: () {
                                    Navigator.pop(context);
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) =>
                                            PatientProfileScreen(patient: p),
                                      ),
                                    );
                                  },
                                ),
                              ],
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    ref.tr('total_outstanding', [
                      debtPatients.fold(
                        0.0,
                        (sum, p) => sum + p.remainingAmount,
                      ),
                    ]),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _showDeletePatientDialog(
    BuildContext context,
    WidgetRef ref,
    patient,
  ) async {
    showDialog(
      context: context,
      builder: (dialogContext) => DeleteConfirmationDialog(
        title: ref.tr('delete_patient'),
        content: ref.tr('delete_confirm_patient', [patient.name]),
        onDelete: () async {
          if (!context.mounted) return;

          final clinic = ref.read(clinicStreamProvider).value;
          if (clinic == null) return;

          final canWrite = await ref
              .read(permissionServiceProvider)
              .canWrite(clinic.id);
          if (!canWrite) {
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(ref.tr('delete_failed_subs'))),
              );
            }
            return;
          }

          try {
            await ref.read(patientRepositoryProvider).deletePatient(patient);
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(ref.tr('patient_deleted'))),
              );
            }
          } catch (e) {
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(ref.tr('error_occurred', [e]))),
              );
            }
          }
        },
      ),
    );
  }

  Widget _buildEmptyState() {
    return Padding(
      padding: const EdgeInsets.only(top: 100),
      child: Center(
        child: Column(
          children: [
            const ScaledIcon(
              Icons.person_search_outlined,
              size: 80,
              color: Colors.white60,
            ),
            const SizedBox(height: 16),
            Text(
              ref.tr('no_patients_found'),
              style: const TextStyle(color: Colors.white70, fontSize: 16),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPatientCard(BuildContext context, WidgetRef ref, patient) {
    final lastVisitFormatted = DateFormat(
      'yyyy/MM/dd',
      ref.watch(languageProvider).languageCode,
    ).format(patient.lastVisit);
    final visitCount = patient.records.length;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(25),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withAlpha(30)),
      ),
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => PatientProfileScreen(patient: patient),
          ),
        ),
        borderRadius: BorderRadius.circular(24),
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Row(
            children: [
              Container(
                width: 65,
                height: 65,
                decoration: BoxDecoration(
                  color: Colors.white.withAlpha(30),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const ScaledIcon(
                  Icons.person,
                  color: Colors.white,
                  size: 35,
                ),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerRight,
                      child: Text(
                        patient.name,
                        maxLines: 1,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 12,
                      runSpacing: 8,
                      children: [
                        _buildBadge(
                          context,
                          ref.tr('age_years', [patient.age.toString()]),
                          Colors.white.withAlpha(40),
                          Colors.white,
                        ),
                        _buildBadge(
                          context,
                          ref.tr('visit_count', [visitCount.toString()]),
                          Colors.white.withAlpha(40),
                          Colors.white,
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        const ScaledIcon(
                          Icons.calendar_month_outlined,
                          size: 14,
                          color: Colors.white70,
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            ref.tr('last_visit_formatted', [
                              lastVisitFormatted,
                            ]),
                            style: const TextStyle(
                              fontSize: 13,
                              color: Colors.white70,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                onPressed: () =>
                    _showDeletePatientDialog(context, ref, patient),
              ),
              const ScaledIcon(
                Icons.arrow_forward_ios_rounded,
                size: 16,
                color: Colors.white30,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBadge(
    BuildContext context,
    String label,
    Color bgColor,
    Color textColor,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          label,
          style: TextStyle(
            color: textColor,
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  void _showSortDialog(BuildContext context, WidgetRef ref) {
    final currentSort = ref.read(patientSortProvider);

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
              ref.tr('sort_patients'),
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 20),
            _buildSortOption(
              context,
              ref,
              title: ref.tr('sort_alphabetical'),
              icon: Icons.sort_by_alpha_rounded,
              isSelected: currentSort == PatientSort.name,
              onTap: () {
                ref
                    .read(patientSortProvider.notifier)
                    .setSort(PatientSort.name);
                Navigator.pop(context);
              },
            ),
            const Divider(color: Colors.white12, height: 1),
            _buildSortOption(
              context,
              ref,
              title: ref.tr('sort_last_visit'),
              icon: Icons.calendar_today_rounded,
              isSelected: currentSort == PatientSort.date,
              onTap: () {
                ref
                    .read(patientSortProvider.notifier)
                    .setSort(PatientSort.date);
                Navigator.pop(context);
              },
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildSortOption(
    BuildContext context,
    WidgetRef ref, {
    required String title,
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return ListTile(
      onTap: onTap,
      leading: Icon(
        icon,
        color: isSelected ? Colors.cyanAccent : Colors.white70,
      ),
      title: Text(
        title,
        style: TextStyle(
          color: isSelected ? Colors.cyanAccent : Colors.white,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        ),
      ),
      trailing: isSelected
          ? const Icon(Icons.check_circle_rounded, color: Colors.cyanAccent)
          : null,
    );
  }
}
