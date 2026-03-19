import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../auth/presentation/auth_providers.dart';
import '../../auth/data/auth_repository.dart';
import '../../auth/domain/models/app_user.dart';
import '../../../core/presentation/widgets/animated_gradient_background.dart';
import '../../../core/presentation/widgets/delete_confirmation_dialog.dart';
import '../../../core/services/permission_service.dart';
import '../../../core/localization/language_provider.dart';

class AdminManagementScreen extends ConsumerWidget {
  const AdminManagementScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userAsync = ref.watch(currentUserProvider);

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Text(
          ref.tr('admin_management_title'),
          style: const TextStyle(color: Colors.white),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: AnimatedGradientBackground(
        child: userAsync.when(
          data: (user) {
            if (user == null) {
              return Center(
                child: Text(
                  ref.tr('unauthorized'),
                  style: const TextStyle(color: Colors.white),
                ),
              );
            }
            if (!user.isAdmin) {
              return Center(
                child: Text(
                  ref.tr('admin_only_page'),
                  style: const TextStyle(color: Colors.white),
                ),
              );
            }

            return _buildAdminContent(context, ref, user);
          },
          loading: () => const Center(
            child: CircularProgressIndicator(color: Colors.white),
          ),
          error: (err, _) => Center(
            child: Text(
              ref.tr('error_label', [err.toString()]),
              style: const TextStyle(color: Colors.white),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAdminContent(
    BuildContext context,
    WidgetRef ref,
    AppUser adminUser,
  ) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16.0, 100.0, 16.0, 16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Pending Approvals Section
          _buildPendingApprovals(context, ref, adminUser),
          const SizedBox(height: 16),

          // Clinic Code Section
          Card(
            color: Colors.white.withAlpha(25),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    ref.tr('clinic_invitation_code'),
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    ref.tr('clinic_code_desc'),
                    style: const TextStyle(color: Colors.white70),
                  ),
                  const SizedBox(height: 16),
                  ref
                      .watch(clinicStreamProvider)
                      .when(
                        data: (clinic) {
                          final code =
                              clinic?.clinicCode ?? ref.tr('not_available');
                          return Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 24,
                                  vertical: 12,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: Colors.blue),
                                ),
                                child: SelectableText(
                                  code,
                                  style: const TextStyle(
                                    fontSize: 24,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 2.0,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 16),
                              IconButton(
                                icon: const Icon(Icons.refresh),
                                color: Colors.green,
                                tooltip: ref.tr('change_code'),
                                onPressed: () => _showChangeCodeDialog(
                                  context,
                                  ref,
                                  adminUser.clinicId,
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.copy),
                                color: Colors.blue,
                                onPressed: () {
                                  Clipboard.setData(ClipboardData(text: code));
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(ref.tr('code_copied')),
                                    ),
                                  );
                                },
                              ),
                            ],
                          );
                        },
                        loading: () =>
                            const Center(child: CircularProgressIndicator()),
                        error: (err, _) =>
                            Text(ref.tr('fetch_code_error', [err.toString()])),
                      ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 32),

          // Employees Section
          Text(
            ref.tr('staff_crew'),
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 16),

          StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('users')
                .where('clinicId', isEqualTo: adminUser.clinicId)
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Text(ref.tr('error_label', [snapshot.error.toString()]));
              }
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(
                  child: CircularProgressIndicator(color: Colors.white),
                );
              }

              final users = snapshot.data!.docs
                  .map(
                    (doc) => AppUser.fromMap(
                      doc.data() as Map<String, dynamic>,
                      doc.id,
                    ),
                  )
                  .toList();

              return ListView.builder(
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: users.length,
                itemBuilder: (context, index) {
                  final employee = users[index];
                  final isMe = employee.id == adminUser.id;

                  return Card(
                    color: Colors.white.withAlpha(25),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: ListTile(
                      leading: Icon(
                        employee.isAdmin
                            ? Icons.admin_panel_settings
                            : Icons.person_outline,
                        color: employee.isAdmin
                            ? Colors.orangeAccent
                            : Colors.white70,
                      ),
                      title: Text(
                        employee.name + (isMe ? ref.tr('you') : ''),
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      subtitle: Text(
                        '${employee.email} | ${employee.phone}',
                        style: const TextStyle(color: Colors.white60),
                      ),
                      trailing: isMe
                          ? Chip(label: Text(ref.tr('system_admin')))
                          : PopupMenuButton<String>(
                              onSelected: (newValue) async {
                                await FirebaseFirestore.instance
                                    .collection('users')
                                    .doc(employee.id)
                                    .update({'role': newValue});
                              },
                              itemBuilder: (context) => [
                                PopupMenuItem(
                                  value: 'admin',
                                  child: Text(ref.tr('promote_to_admin')),
                                ),
                                PopupMenuItem(
                                  value: 'secretary',
                                  child: Text(ref.tr('change_to_secretary')),
                                ),
                              ],
                              child: Chip(
                                label: Text(
                                  employee.isAdmin
                                      ? ref.tr('admin')
                                      : ref.tr('secretary'),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                  ),
                                ),
                                backgroundColor: employee.isAdmin
                                    ? Colors.orange.withAlpha(100)
                                    : Colors.blue.withAlpha(100),
                                side: BorderSide.none,
                              ),
                            ),
                    ),
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildPendingApprovals(
    BuildContext context,
    WidgetRef ref,
    AppUser adminUser,
  ) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .where('clinicId', isEqualTo: adminUser.clinicId)
          .where('isApproved', isEqualTo: false)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const SizedBox.shrink();
        }

        final pendingUsers = snapshot.data!.docs;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.orange.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.notification_important,
                        color: Colors.orange.shade800,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        ref.tr('pending_join_requests', [
                          pendingUsers.length.toString(),
                        ]),
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.orange.shade900,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  ...pendingUsers.map((doc) {
                    final user = AppUser.fromMap(
                      doc.data() as Map<String, dynamic>,
                      doc.id,
                    );
                    return Card(
                      color: Colors.white.withAlpha(40),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        title: Text(
                          user.name,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        subtitle: Text(
                          user.email,
                          style: const TextStyle(color: Colors.white70),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(
                                Icons.check_circle,
                                color: Colors.green,
                              ),
                              onPressed: () async {
                                final clinic = ref
                                    .read(clinicStreamProvider)
                                    .value;
                                if (clinic == null) return;

                                final canWrite = await ref
                                    .read(permissionServiceProvider)
                                    .canWrite(clinic.id);
                                if (!canWrite) {
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          ref.tr('accept_employee_error_subs'),
                                        ),
                                      ),
                                    );
                                  }
                                  return;
                                }

                                await ref
                                    .read(authRepositoryProvider)
                                    .approveUser(user.id);
                              },
                            ),
                            IconButton(
                              icon: const Icon(Icons.cancel, color: Colors.red),
                              onPressed: () =>
                                  _confirmReject(context, ref, user),
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
                ],
              ),
            ),
            const SizedBox(height: 24),
          ],
        );
      },
    );
  }

  Future<void> _confirmReject(
    BuildContext context,
    WidgetRef ref,
    AppUser user,
  ) async {
    showDialog(
      context: context,
      builder: (context) => DeleteConfirmationDialog(
        title: ref.tr('reject_request'),
        content: ref.tr('reject_confirm_msg', [user.name]),
        deleteButtonText: ref.tr('reject_and_delete'),
        onDelete: () async {
          final clinic = ref.read(clinicStreamProvider).value;
          if (clinic == null) return;

          final canWrite = await ref
              .read(permissionServiceProvider)
              .canWrite(clinic.id);
          if (!canWrite) {
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(ref.tr('reject_error_subs'))),
              );
            }
            return;
          }

          await ref.read(authRepositoryProvider).rejectUser(user.id);
        },
      ),
    );
  }

  Future<void> _showChangeCodeDialog(
    BuildContext context,
    WidgetRef ref,
    String clinicId,
  ) async {
    final authRepo = ref.read(authRepositoryProvider);
    final newCode = authRepo.generateRandomCode(6);

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(ref.tr('change_clinic_code_title')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(ref.tr('change_clinic_code_confirm')),
            const SizedBox(height: 16),
            Text(ref.tr('new_code_will_be')),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              width: double.infinity,
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                newCode,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 2,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              ref.tr('change_code_note'),
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(ref.tr('cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(ref.tr('change_now')),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final clinic = ref.read(clinicStreamProvider).value;
      if (clinic == null) return;

      final canWrite = await ref
          .read(permissionServiceProvider)
          .canWrite(clinic.id);
      if (!canWrite) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(ref.tr('change_code_error_subs'))),
          );
        }
        return;
      }

      await authRepo.updateClinicCode(clinicId, newCode);
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(ref.tr('code_updated_success'))));
      }
    }
  }
}
