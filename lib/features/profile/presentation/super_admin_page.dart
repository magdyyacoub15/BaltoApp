// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:appwrite/appwrite.dart';
import 'package:appwrite/models.dart' as models;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'dart:math';
import 'dart:ui';
import '../../../core/services/cleanup_service.dart';
import '../../../core/services/appwrite_client.dart';
import '../../../core/services/subscription_service.dart';
import '../../../core/localization/language_provider.dart';

class SuperAdminPage extends ConsumerStatefulWidget {
  const SuperAdminPage({super.key});

  @override
  ConsumerState<SuperAdminPage> createState() => _SuperAdminPageState();
}

class _SuperAdminPageState extends ConsumerState<SuperAdminPage>
    with SingleTickerProviderStateMixin {
  List<models.Document> _clinics = [];
  List<models.Document> _filteredClinics = [];
  final TextEditingController _searchController = TextEditingController();
  bool _isLoading = true;
  AnimationController? _animationController;
  int _totalUsersCount = 0;
  int _totalClinicsCount = 0;

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
      final databases = ref.read(appwriteDatabasesProvider);
      final clinicsSnapshot = await databases.listDocuments(
        databaseId: appwriteDatabaseId,
        collectionId: 'clinics',
        queries: [Query.limit(1)],
      );
      final usersSnapshot = await databases.listDocuments(
        databaseId: appwriteDatabaseId,
        collectionId: 'users',
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
      final databases = ref.read(appwriteDatabasesProvider);
      final snapshot = await databases.listDocuments(
        databaseId: appwriteDatabaseId,
        collectionId: 'clinics',
        queries: [Query.orderDesc('createdAt')],
      );

      if (mounted) {
        setState(() {
          _clinics = snapshot.documents;
          _filteredClinics = snapshot.documents;
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
        final email = (data['adminEmail'] ?? '').toString().toLowerCase();
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
              Text(
                title,
                style: TextStyle(
                  color: color.withAlpha(200),
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                value,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
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
                    const SizedBox(height: 16),
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
                      final String email =
                          data['adminEmail'] ?? ref.tr('no_email');
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
                                    Text(
                                      ref.tr('status_label', [statusText]),
                                      style: const TextStyle(
                                        color: Colors.blueGrey,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w500,
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
                                    Text(
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
                                    Row(
                                      children: [
                                        _buildEditDateButton(doc.$id, endDate),
                                        _buildCustomDaysButton(doc.$id),
                                        _buildCancelButton(doc.$id),
                                        const Spacer(),
                                        _buildDeleteSystemButton(doc.$id, name),
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

  Widget _buildDeleteSystemButton(String clinicId, String clinicName) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(10),
      ),
      child: IconButton(
        icon: const Icon(Icons.delete_forever, color: Colors.red, size: 28),
        tooltip: ref.tr('delete_entire_system'),
        onPressed: () => _showDeleteConfirmation(clinicId, clinicName),
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

  void _showDeleteConfirmation(String clinicId, String clinicName) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => _DeleteConfirmationDialog(
        clinicId: clinicId,
        clinicName: clinicName,
        onDelete: _deleteEntireSystemData,
      ),
    );
  }

  Future<void> _deleteEntireSystemData(
    String clinicId, {
    required Function(String) onProgress,
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final subcollections = [
        'patients',
        'appointments',
        'expenses', // Let's pretend expenses is transactions or we just delete users
        'users_roles',
      ];

      int currentStep = 0;
      final totalSteps = subcollections.length + 1;
      final databases = ref.read(appwriteDatabasesProvider);

      // 1. Delete Patients
      currentStep++;
      onProgress(
        ref.tr('deleting_patients_records', [
          currentStep.toString(),
          totalSteps.toString(),
        ]),
      );

      final patientsSnapshot = await databases.listDocuments(
        databaseId: appwriteDatabaseId,
        collectionId: 'patients',
        queries: [Query.equal('clinicId', clinicId), Query.limit(100)],
      );

      int deletedPatients = 0;
      for (var patient in patientsSnapshot.documents) {
        await databases.deleteDocument(
          databaseId: appwriteDatabaseId,
          collectionId: 'patients',
          documentId: patient.$id,
        );
        deletedPatients++;
        onProgress(
          ref.tr('deleting_patients_count', [deletedPatients.toString()]),
        );
      }

      // 2. Delete Appointments
      currentStep++;
      onProgress(
        ref.tr('deleting_appointments', [
          currentStep.toString(),
          totalSteps.toString(),
        ]),
      );
      final appointmentsSnapshot = await databases.listDocuments(
        databaseId: appwriteDatabaseId,
        collectionId: 'appointments',
        queries: [Query.equal('clinicId', clinicId), Query.limit(100)],
      );
      for (var doc in appointmentsSnapshot.documents) {
        await databases.deleteDocument(
          databaseId: appwriteDatabaseId,
          collectionId: 'appointments',
          documentId: doc.$id,
        );
      }

      // 3. Delete Expenses / Transactions
      currentStep++;
      onProgress(
        ref.tr('deleting_expenses', [
          currentStep.toString(),
          totalSteps.toString(),
        ]),
      );
      final expensesSnapshot = await databases.listDocuments(
        databaseId: appwriteDatabaseId,
        collectionId: 'transactions',
        queries: [Query.equal('clinicId', clinicId), Query.limit(100)],
      );
      for (var doc in expensesSnapshot.documents) {
        await databases.deleteDocument(
          databaseId: appwriteDatabaseId,
          collectionId: 'transactions',
          documentId: doc.$id,
        );
      }

      // 4. Reset User Roles (detach users from this clinic)
      currentStep++;
      onProgress(
        ref.tr('resetting_permissions', [
          currentStep.toString(),
          totalSteps.toString(),
        ]),
      );
      final usersSnapshot = await databases.listDocuments(
        databaseId: appwriteDatabaseId,
        collectionId: 'users',
        queries: [Query.equal('clinicId', clinicId), Query.limit(100)],
      );
      for (var user in usersSnapshot.documents) {
        // Here we just mark them as unapproved and remove clinicId if possible
        await databases.updateDocument(
          databaseId: appwriteDatabaseId,
          collectionId: 'users',
          documentId: user.$id,
          data: {'clinicId': '', 'isApproved': false},
        );
      }

      // 5. Delete Clinic Final Store Data (Images, Backups, etc.)
      currentStep++;
      onProgress(
        ref.tr('cleaning_up_storage', [
          currentStep.toString(),
          totalSteps.toString(),
        ]),
      );
      // Assuming storage path is organized by clinicId
      await ref
          .read(cleanupServiceProvider)
          .deleteStorageFolder('clinics/$clinicId');

      // 6. Delete Clinic Document
      await databases.deleteDocument(
        databaseId: appwriteDatabaseId,
        collectionId: 'clinics',
        documentId: clinicId,
      );

      if (mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(ref.tr('delete_clinic_success')),
            backgroundColor: Colors.green,
          ),
        );
        _fetchClinics(showLoading: false);
      }
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(ref.tr('delete_clinic_error', [e.toString()])),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
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
}

class _DeleteConfirmationDialog extends ConsumerStatefulWidget {
  final String clinicId;
  final String clinicName;
  final Future<void> Function(String, {required Function(String) onProgress})
  onDelete;

  const _DeleteConfirmationDialog({
    required this.clinicId,
    required this.clinicName,
    required this.onDelete,
  });

  @override
  ConsumerState<_DeleteConfirmationDialog> createState() =>
      _DeleteConfirmationDialogState();
}

class _DeleteConfirmationDialogState
    extends ConsumerState<_DeleteConfirmationDialog> {
  bool _isDeleting = false;
  String _progressMessage = '';
  final TextEditingController _confirmController = TextEditingController();

  @override
  void dispose() {
    _confirmController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer(
      builder: (context, ref, child) {
        return AlertDialog(
          title: Text(
            ref.tr('extreme_caution'),
            style: const TextStyle(
              color: Colors.red,
              fontWeight: FontWeight.bold,
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(ref.tr('delete_system_warning', [widget.clinicName])),
              const SizedBox(height: 15),
              Text(
                ref.tr('irreversible_action'),
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 15),
              if (!_isDeleting) ...[
                Text(ref.tr('type_to_confirm', [widget.clinicName])),
                const SizedBox(height: 8),
                TextField(
                  controller: _confirmController,
                  decoration: InputDecoration(
                    hintText: widget.clinicName,
                    border: const OutlineInputBorder(),
                  ),
                ),
              ] else ...[
                const Center(
                  child: CircularProgressIndicator(color: Colors.red),
                ),
                const SizedBox(height: 12),
                Center(
                  child: Text(
                    _progressMessage,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ],
          ),
          actions: _isDeleting
              ? []
              : [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(ref.tr('cancel')),
                  ),
                  ElevatedButton(
                    onPressed: _confirmController.text == widget.clinicName
                        ? () async {
                            setState(() {
                              _isDeleting = true;
                              _progressMessage = ref.tr('initializing_delete');
                            });
                            try {
                              await widget.onDelete(
                                widget.clinicId,
                                onProgress: (msg) {
                                  if (mounted) {
                                    setState(() => _progressMessage = msg);
                                  }
                                },
                              );
                              if (!context.mounted) return;
                              Navigator.pop(context);
                            } catch (e) {
                              if (mounted) {
                                setState(() {
                                  _isDeleting = false;
                                  _progressMessage = '';
                                });
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      ref.tr('delete_error', [e.toString()]),
                                    ),
                                  ),
                                );
                              }
                            }
                          }
                        : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                    ),
                    child: Text(ref.tr('delete_everything')),
                  ),
                ],
        );
      },
    );
  }
}
