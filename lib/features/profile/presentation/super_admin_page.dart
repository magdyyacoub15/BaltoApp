// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:appwrite/appwrite.dart';
import 'package:appwrite/models.dart' as models;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'dart:math';
import 'dart:ui';
import '../../../core/services/appwrite_client.dart';
import '../../../core/services/subscription_service.dart';
import '../../../core/localization/language_provider.dart';
import '../../../core/services/update_service.dart';

class SuperAdminPage extends ConsumerStatefulWidget {
  const SuperAdminPage({super.key});

  @override
  ConsumerState<SuperAdminPage> createState() => _SuperAdminPageState();
}

class _SuperAdminPageState extends ConsumerState<SuperAdminPage>
    with SingleTickerProviderStateMixin {
  List<models.Row> _clinics = [];
  List<models.Row> _filteredClinics = [];
  final TextEditingController _searchController = TextEditingController();
  bool _isLoading = true;
  AnimationController? _animationController;
  int _totalUsersCount = 0;
  int _totalClinicsCount = 0;
  Map<String, String> _adminEmails = {};

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 15),
    )..repeat();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _fetchClinics();
      _fetchTotalCounts();
    });
  }

  Future<void> _fetchTotalCounts() async {
    try {
      final databases = ref.read(appwriteTablesDBProvider);
      final clinicsSnapshot = await databases.listRows(
        databaseId: appwriteDatabaseId,
        tableId: 'clinics',
        queries: [Query.limit(1)],
      );
      final usersSnapshot = await databases.listRows(
        databaseId: appwriteDatabaseId,
        tableId: 'users',
        queries: [Query.limit(1)],
      );

      if (mounted) {
        setState(() {
          _totalClinicsCount = clinicsSnapshot.total;
          _totalUsersCount = usersSnapshot.total;
        });
      }
    } catch (e) {
      debugPrint("Error fetching counts: $e");
    }
  }

  Future<void> _fetchClinics({bool showLoading = true}) async {
    if (showLoading) setState(() => _isLoading = true);
    try {
      final databases = ref.read(appwriteTablesDBProvider);
      final snapshot = await databases.listRows(
        databaseId: appwriteDatabaseId,
        tableId: 'clinics',
        queries: [Query.orderDesc('createdAt')],
      );

      final adminIds = snapshot.rows
          .map((doc) => doc.data['adminId']?.toString())
          .where((id) => id != null && id.isNotEmpty)
          .toSet()
          .toList();

      Map<String, String> emailsMap = {};
      if (adminIds.isNotEmpty) {
        try {
          final usersSnapshot = await databases.listRows(
            databaseId: appwriteDatabaseId,
            tableId: 'users',
            queries: [Query.equal('\$id', adminIds), Query.limit(adminIds.length)],
          );
          for (var userDoc in usersSnapshot.rows) {
            emailsMap[userDoc.$id] = userDoc.data['email'] ?? '';
          }
        } catch (e) {
          debugPrint("Error fetching admin emails: $e");
        }
      }

      if (mounted) {
        setState(() {
          _adminEmails = emailsMap;
          _clinics = snapshot.rows;
          _filteredClinics = snapshot.rows;
          _isLoading = false;
        });
        _onSearchChanged(_searchController.text);
      }
    } catch (e) {
      debugPrint("Error fetching clinics: $e");
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(ref.tr('fetch_code_error', [e.toString()]))),
        );
      }
    }
  }

  @override
  void dispose() {
    _animationController?.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    setState(() {
      _filteredClinics = _clinics.where((doc) {
        final data = doc.data;
        final name = (data['name'] ?? '').toString().toLowerCase();
        final adminId = data['adminId']?.toString() ?? '';
        final email = (data['adminEmail'] ?? _adminEmails[adminId] ?? '')
            .toString()
            .toLowerCase();
        final code = (data['clinicCode'] ?? '').toString().toLowerCase();
        final searchLower = query.toLowerCase();

        return name.contains(searchLower) ||
            email.contains(searchLower) ||
            code.contains(searchLower);
      }).toList();
    });
  }

  Widget _buildStatCard(
    String title,
    String value,
    IconData icon,
    Color color,
  ) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: color.withAlpha(50),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: color.withAlpha(100)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: color, size: 28),
              const SizedBox(height: 8),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  title,
                  style: TextStyle(
                    color: color.withAlpha(200),
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  value,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          _buildPremiumBackground(),
          CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              SliverAppBar(
                expandedHeight: 80,
                floating: true,
                pinned: false,
                elevation: 0,
                backgroundColor: Colors.transparent,
                title: Text(
                  ref.tr('super_admin_title'),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                centerTitle: true,
                iconTheme: const IconThemeData(color: Colors.white),
                actions: [
                  IconButton(
                    icon: const Icon(Icons.system_update_alt, color: Colors.amber),
                    onPressed: () => _showOtaUpdateDialog(context),
                    tooltip: ref.tr('ota_management_title'),
                  ),
                  const SizedBox(width: 8),
                ],
              ),
              SliverToBoxAdapter(
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: _buildStatCard(
                              ref.tr('total_users'),
                              _totalUsersCount.toString(),
                              Icons.people_alt,
                              Colors.blue.shade300,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _buildStatCard(
                              ref.tr('total_clinics'),
                              _totalClinicsCount.toString(),
                              Icons.local_hospital,
                              Colors.orange.shade300,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(20),
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            decoration: BoxDecoration(
                              color: Colors.white.withAlpha(40),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: Colors.white.withAlpha(80),
                              ),
                            ),
                            child: TextField(
                              controller: _searchController,
                              textAlign: TextAlign.right,
                              style: const TextStyle(color: Colors.white),
                              decoration: InputDecoration(
                                hintText: ref.tr('search_clinics_hint'),
                                hintStyle: const TextStyle(
                                  color: Colors.white70,
                                ),
                                prefixIcon: const Icon(
                                  Icons.search,
                                  color: Colors.white70,
                                ),
                                border: InputBorder.none,
                                contentPadding: const EdgeInsets.symmetric(
                                  vertical: 15,
                                ),
                              ),
                              onChanged: _onSearchChanged,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
              if (_isLoading)
                const SliverToBoxAdapter(
                  child: Center(
                    child: Padding(
                      padding: EdgeInsets.all(32.0),
                      child: CircularProgressIndicator(color: Colors.white),
                    ),
                  ),
                )
              else if (_filteredClinics.isEmpty)
                SliverToBoxAdapter(
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32.0),
                      child: Text(
                        ref.tr('no_clinics_found'),
                        style: const TextStyle(color: Colors.white70),
                      ),
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate((context, index) {
                      final doc = _filteredClinics[index];
                      final data = doc.data;
                      final String name = data['name'] ?? ref.tr('no_name');
                      final String adminId = data['adminId']?.toString() ?? '';
                      final String email = data['adminEmail'] ??
                          _adminEmails[adminId] ??
                          ref.tr('no_email');
                      final String code =
                          data['clinicCode'] ?? ref.tr('not_available');
                      final bool isTrial = data['isTrial'] ?? false;

                      DateTime? endDate;
                      if (data['subscriptionEndDate'] != null) {
                        endDate = DateTime.tryParse(
                          data['subscriptionEndDate'].toString(),
                        )?.toLocal();
                      }

                      String statusText = ref.tr('not_set');
                      Color statusColor = Colors.grey;

                      if (endDate != null) {
                        if (endDate.isAfter(DateTime.now())) {
                          statusText = isTrial
                              ? ref.tr('trial_period')
                              : ref.tr('active_subscription');
                          statusColor = isTrial ? Colors.orange : Colors.green;
                        } else {
                          statusText = ref.tr('expired_subscription');
                          statusColor = Colors.red;
                        }
                      }

                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withAlpha(12),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(20),
                          child: ExpansionTile(
                            backgroundColor: Colors.white,
                            collapsedBackgroundColor: Colors.white,
                            shape: const RoundedRectangleBorder(
                              side: BorderSide.none,
                            ),
                            title: Text(
                              name,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 18,
                                color: Color(0xFF0D47A1),
                              ),
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  email,
                                  style: TextStyle(
                                    color: Colors.grey.shade600,
                                    fontSize: 13,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    const Icon(
                                      Icons.info_outline,
                                      size: 14,
                                      color: Colors.blueGrey,
                                    ),
                                    const SizedBox(width: 4),
                                    Expanded(
                                      child: Text(
                                        ref.tr('status_label', [statusText]),
                                        style: const TextStyle(
                                          color: Colors.blueGrey,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w500,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    Icon(
                                      Icons.event,
                                      size: 14,
                                      color: Colors.blue.shade700,
                                    ),
                                    const SizedBox(width: 4),
                                    Expanded(
                                      child: Text(
                                        ref.tr('expires_on', [
                                          endDate != null
                                              ? DateFormat(
                                                  'yyyy-MM-dd',
                                                ).format(endDate)
                                              : ref.tr('not_set'),
                                        ]),
                                        style: TextStyle(
                                          color: Colors.blue.shade700,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w500,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            leading: CircleAvatar(
                              backgroundColor: statusColor,
                              radius: 8,
                            ),
                            children: [
                              Padding(
                                padding: const EdgeInsets.all(20.0),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    _buildInfoRow(
                                      ref.tr('clinic_code_label'),
                                      code,
                                      Icons.vpn_key_outlined,
                                    ),
                                    _buildInfoRow(
                                      ref.tr('id_label'),
                                      doc.$id,
                                      Icons.perm_identity,
                                    ),
                                    const Divider(height: 30),
                                    Text(
                                      ref.tr('extend_subscription_title'),
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: Color(0xFF1565C0),
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    Wrap(
                                      spacing: 8,
                                      runSpacing: 8,
                                      children: [
                                        _buildExtendButton(
                                          doc.$id,
                                          ref.tr('one_month'),
                                          30,
                                        ),
                                        _buildExtendButton(
                                          doc.$id,
                                          ref.tr('three_months'),
                                          90,
                                        ),
                                        _buildExtendButton(
                                          doc.$id,
                                          ref.tr('six_months'),
                                          180,
                                        ),
                                        _buildExtendButton(
                                          doc.$id,
                                          ref.tr('full_year'),
                                          365,
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 25),
                                    Text(
                                      ref.tr('advanced_actions'),
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: Colors.red.shade900,
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    Wrap(
                                      spacing: 8,
                                      runSpacing: 8,
                                      alignment: WrapAlignment.start,
                                      children: [
                                        _buildEditDateButton(doc.$id, endDate),
                                        _buildCustomDaysButton(doc.$id),
                                        _buildCancelButton(doc.$id),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }, childCount: _filteredClinics.length),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value, IconData icon) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 16, color: Colors.grey),
          const SizedBox(width: 8),
          Text("$label: ", style: const TextStyle(fontWeight: FontWeight.w500)),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(color: Colors.black87),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }


  Widget _buildPremiumBackground() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF0D47A1), Color(0xFF1976D2), Color(0xFF42A5F5)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Stack(
        children: [
          if (_animationController != null)
            AnimatedBuilder(
              animation: _animationController!,
              builder: (context, child) {
                return Stack(
                  children: [
                    _buildAnimatedBlob(
                      top: -50,
                      left: -50,
                      offset: Offset(
                        sin(_animationController!.value * 2 * pi) * 60,
                        cos(_animationController!.value * 2 * pi) * 40,
                      ),
                      color: Colors.white.withAlpha(25),
                      size: 300,
                    ),
                    _buildAnimatedBlob(
                      top: 300,
                      left: 150,
                      offset: Offset(
                        cos(_animationController!.value * 2 * pi) * 70,
                        sin(_animationController!.value * 2 * pi) * 50,
                      ),
                      color: Colors.white.withAlpha(18),
                      size: 250,
                    ),
                    _buildAnimatedBlob(
                      top: 600,
                      left: -30,
                      offset: Offset(
                        sin(_animationController!.value * 2 * pi) * 40,
                        -cos(_animationController!.value * 2 * pi) * 60,
                      ),
                      color: Colors.white.withAlpha(13),
                      size: 200,
                    ),
                  ],
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _buildAnimatedBlob({
    double? top,
    double? left,
    required Offset offset,
    required Color color,
    required double size,
  }) {
    return Positioned(
      top: top,
      left: left,
      child: Transform.translate(
        offset: offset,
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(shape: BoxShape.circle, color: color),
        ),
      ),
    );
  }



  Widget _buildExtendButton(String clinicId, String label, int days) {
    final subService = ref.read(subscriptionServiceProvider);
    return ElevatedButton(
      onPressed: () async {
        final messenger = ScaffoldMessenger.of(context);
        try {
          await subService.extendSubscription(clinicId, days);
          if (mounted) {
            messenger.showSnackBar(
              SnackBar(content: Text(ref.tr('extend_success', [label]))),
            );
            _fetchClinics(showLoading: false);
          }
        } catch (e) {
          if (mounted) {
            messenger.showSnackBar(
              SnackBar(content: Text(ref.tr('extend_error', [e.toString()]))),
            );
          }
        }
      },
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.blue.shade100,
        foregroundColor: Colors.blue.shade900,
      ),
      child: Text(label),
    );
  }

  Widget _buildEditDateButton(String clinicId, DateTime? currentDate) {
    final subService = ref.read(subscriptionServiceProvider);
    return IconButton(
      icon: const Icon(Icons.calendar_today, color: Colors.blue),
      tooltip: ref.tr('edit_date_manual'),
      onPressed: () async {
        final messenger = ScaffoldMessenger.of(context);
        final DateTime? picked = await showDatePicker(
          context: context,
          initialDate: currentDate ?? DateTime.now(),
          firstDate: DateTime(2000),
          lastDate: DateTime(2100),
        );
        if (picked != null) {
          try {
            await subService.updateSubscriptionDate(clinicId, picked);
            if (mounted) {
              messenger.showSnackBar(
                SnackBar(content: Text(ref.tr('update_date_success'))),
              );
              _fetchClinics(showLoading: false);
            }
          } catch (e) {
            if (mounted) {
              messenger.showSnackBar(
                SnackBar(
                  content: Text(ref.tr('update_date_error', [e.toString()])),
                ),
              );
            }
          }
        }
      },
    );
  }

  Widget _buildCustomDaysButton(String clinicId) {
    final subService = ref.read(subscriptionServiceProvider);
    return IconButton(
      icon: const Icon(Icons.exposure, color: Colors.orange),
      tooltip: ref.tr('edit_days_manual'),
      onPressed: () {
        final TextEditingController controller = TextEditingController();
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(ref.tr('add_remove_days')),
            content: TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: ref.tr('days_count'),
                hintText: ref.tr('days_example'),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(ref.tr('cancel')),
              ),
              ElevatedButton(
                onPressed: () async {
                  final messenger = ScaffoldMessenger.of(context);
                  final days = int.tryParse(controller.text);
                  if (days != null) {
                    try {
                      await subService.extendSubscription(clinicId, days);
                      if (!context.mounted) return;
                      Navigator.pop(context);
                      messenger.showSnackBar(
                        SnackBar(content: Text(ref.tr('update_success'))),
                      );
                      _fetchClinics(showLoading: false);
                    } catch (e) {
                      if (mounted) {
                        messenger.showSnackBar(
                          SnackBar(
                            content: Text(
                              ref.tr('update_error', [e.toString()]),
                            ),
                          ),
                        );
                      }
                    }
                  }
                },
                child: Text(ref.tr('update')),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildCancelButton(String clinicId) {
    final subService = ref.read(subscriptionServiceProvider);
    return IconButton(
      icon: const Icon(Icons.cancel_outlined, color: Colors.red),
      tooltip: ref.tr('cancel_subscription'),
      onPressed: () => _confirmCancelSubscription(clinicId, subService),
    );
  }

  void _confirmCancelSubscription(String clinicId, dynamic subService) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(ref.tr('confirm_cancellation')),
        content: Text(ref.tr('confirm_cancellation_message')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(ref.tr('no')),
          ),
          ElevatedButton(
            onPressed: () async {
              final messenger = ScaffoldMessenger.of(context);
              try {
                await subService.cancelSubscription(clinicId);
                if (!context.mounted) return;
                Navigator.pop(context);
                messenger.showSnackBar(
                  SnackBar(content: Text(ref.tr('cancel_success'))),
                );
                _fetchClinics(showLoading: false);
              } catch (e) {
                if (mounted) {
                  messenger.showSnackBar(
                    SnackBar(
                      content: Text(ref.tr('cancel_error', [e.toString()])),
                    ),
                  );
                }
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: Text(ref.tr('yes_cancel')),
          ),
        ],
      ),
    );
  }

  void _showOtaUpdateDialog(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => const _OtaUpdateDialog(),
    );
  }
}


class _OtaUpdateDialog extends ConsumerStatefulWidget {
  const _OtaUpdateDialog();

  @override
  ConsumerState<_OtaUpdateDialog> createState() => __OtaUpdateDialogState();
}

class __OtaUpdateDialogState extends ConsumerState<_OtaUpdateDialog> {
  final _codeController = TextEditingController();
  final _urlController = TextEditingController();
  final _changelogController = TextEditingController();
  bool _isLoading = false;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _loadCurrentConfig();
  }

  Future<void> _loadCurrentConfig() async {
    setState(() => _isLoading = true);
    try {
      final updateInfo = await ref.read(updateServiceProvider).getUpdateInfo();
      if (updateInfo != null) {
        _codeController.text = updateInfo.updateCode.toString();
        _urlController.text = updateInfo.apkUrl;
        _changelogController.text = updateInfo.changelog;
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _saveConfig() async {
    final codeText = _codeController.text.trim();
    final code = int.tryParse(codeText) ?? 0;

    if (code == 0 || _urlController.text.trim().isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please enter valid data')),
        );
      }
      return;
    }

    setState(() => _isSaving = true);
    try {
      final databases = ref.read(appwriteTablesDBProvider);
      final updateData = {
        'updateCode': code,
        'apkUrl': _urlController.text.trim(),
        'changelog': _changelogController.text.trim(),
      };

      try {
        await databases.updateRow(
          databaseId: appwriteDatabaseId,
          tableId: 'config',
          rowId: 'update_info',
          data: updateData,
        );
      } catch (e) {
        if (e.toString().contains('404') || e.toString().contains('not_found')) {
          await databases.createRow(
            databaseId: appwriteDatabaseId,
            tableId: 'config',
            rowId: 'update_info',
            data: updateData,
          );
        } else {
          rethrow;
        }
      }
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(ref.tr('update_saved_success'))),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF0D47A1),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      title: Row(
        children: [
          const Icon(Icons.system_update_alt, color: Colors.amber),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              ref.tr('ota_management_title'),
              style: const TextStyle(color: Colors.white, fontSize: 18),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
      content: _isLoading
          ? const SizedBox(
              height: 200,
              child: Center(child: CircularProgressIndicator(color: Colors.white)),
            )
          : SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildField(_codeController, ref.tr('update_code_label'), true),
                  const SizedBox(height: 16),
                  _buildField(_urlController, ref.tr('apk_url_label'), false),
                  const SizedBox(height: 16),
                  _buildField(
                    _changelogController,
                    ref.tr('changelog_label'),
                    false,
                    maxLines: 4,
                  ),
                ],
              ),
            ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child:
              Text(ref.tr('cancel'), style: const TextStyle(color: Colors.white70)),
        ),
        ElevatedButton(
          onPressed: _isSaving ? null : _saveConfig,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.amber,
            foregroundColor: Colors.black,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          child: _isSaving
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(ref.tr('save_update_button')),
        ),
      ],
    );
  }

  Widget _buildField(
    TextEditingController controller,
    String label,
    bool isNumber, {
    int maxLines = 1,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Colors.amber,
            fontSize: 14,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          keyboardType: isNumber ? TextInputType.number : TextInputType.text,
          maxLines: maxLines,
          style: const TextStyle(color: Colors.white, fontSize: 14),
          decoration: InputDecoration(
            labelStyle: const TextStyle(color: Colors.white70),
            enabledBorder: OutlineInputBorder(
              borderSide: BorderSide(color: Colors.white.withAlpha(50)),
              borderRadius: BorderRadius.circular(12),
            ),
            focusedBorder: OutlineInputBorder(
              borderSide: const BorderSide(color: Colors.amber, width: 2),
              borderRadius: BorderRadius.circular(12),
            ),
            filled: true,
            fillColor: Colors.white.withAlpha(10),
          ),
        ),
      ],
    );
  }
}
