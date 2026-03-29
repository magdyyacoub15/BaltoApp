import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../auth/presentation/auth_providers.dart';
import '../../auth/data/auth_repository.dart';
import '../../auth/domain/models/app_user.dart';
import '../../../core/presentation/widgets/animated_gradient_background.dart';
import '../../../core/presentation/widgets/delete_confirmation_dialog.dart';
import '../../../core/services/permission_service.dart';
import '../../../core/localization/language_provider.dart';
import '../../../core/services/appwrite_client.dart';

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
                        skipLoadingOnRefresh: true,
                        skipLoadingOnReload: true,
                        data: (clinic) {
                          final code =
                              clinic?.clinicCode ?? ref.tr('not_available');
                          return Wrap(
                            spacing: 8,
                            runSpacing: 12,
                            alignment: WrapAlignment.center,
                            crossAxisAlignment: WrapCrossAlignment.center,
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
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
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

          ref.watch(clinicEmployeesStreamProvider).when(
            skipLoadingOnRefresh: true,
            skipLoadingOnReload: true,
            data: (users) {
              return ListView.builder(
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: users.length,
                itemBuilder: (context, index) {
                  final employee = users[index];
                  final isMe = employee.id == adminUser.id;

                  return Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: Colors.white.withAlpha(20),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: Colors.white.withAlpha(30),
                        width: 1,
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(12.0),
                      child: Row(
                        children: [
                          // Left Section: Avatar/Icon
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: employee.isAdmin
                                  ? Colors.orange.withAlpha(40)
                                  : Colors.blue.withAlpha(40),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              employee.isAdmin
                                  ? Icons.admin_panel_settings
                                  : Icons.person_outline,
                              color: employee.isAdmin
                                  ? Colors.orangeAccent
                                  : Colors.blueAccent,
                              size: 24,
                            ),
                          ),
                          const SizedBox(width: 16),
                          
                          // Middle Section: Info
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Flexible(
                                      child: Text(
                                        employee.name,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    if (isMe)
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        margin: const EdgeInsets.only(left: 8),
                                        decoration: BoxDecoration(
                                          color: Colors.green.withAlpha(60),
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: Text(
                                          ref.tr('you'),
                                          style: const TextStyle(color: Colors.greenAccent, fontSize: 10),
                                        ),
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  employee.email,
                                  style: TextStyle(color: Colors.white.withAlpha(150), fontSize: 13),
                                ),
                                const SizedBox(height: 6),
                                
                                // Visibility Indicators
                                if (!employee.isAdmin)
                                Row(
                                  children: [
                                    Expanded(
                                      child: Wrap(
                                        spacing: 8,
                                        runSpacing: 4,
                                        children: [
                                          _buildPermissionBadge(
                                            icon: Icons.account_balance_wallet_outlined,
                                            label: ref.tr('permissions_accounts'),
                                            isActive: employee.canViewAccounts,
                                          ),
                                          _buildPermissionBadge(
                                            icon: Icons.people_outline,
                                            label: ref.tr('permissions_patients'),
                                            isActive: employee.canViewPatients,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          
                          // Right Section: Action
                          if (!isMe)
                            PopupMenuButton<String>(
                              icon: const Icon(Icons.more_vert, color: Colors.white70),
                              onSelected: (newValue) async {
                                if (newValue == 'remove') {
                                  _confirmRemoveUser(context, ref, employee, adminUser.clinicId);
                                  return;
                                }
                                if (newValue == 'toggle_accounts') {
                                  await ref.read(appwriteTablesDBProvider).updateRow(
                                    databaseId: appwriteDatabaseId,
                                    tableId: 'users',
                                    rowId: employee.id,
                                    data: {'canViewAccounts': !employee.canViewAccounts},
                                  );
                                  return;
                                }
                                if (newValue == 'toggle_patients') {
                                  await ref.read(appwriteTablesDBProvider).updateRow(
                                    databaseId: appwriteDatabaseId,
                                    tableId: 'users',
                                    rowId: employee.id,
                                    data: {'canViewPatients': !employee.canViewPatients},
                                  );
                                  return;
                                }
                                await ref.read(appwriteTablesDBProvider).updateRow(
                                  databaseId: appwriteDatabaseId,
                                  tableId: 'users',
                                  rowId: employee.id,
                                  data: {'role': newValue},
                                );
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
                                const PopupMenuDivider(),
                                PopupMenuItem(
                                  value: 'toggle_accounts',
                                  child: Text(
                                    employee.canViewAccounts
                                        ? ref.tr('hide_accounts_page')
                                        : ref.tr('show_accounts_page'),
                                    style: TextStyle(
                                      color: employee.canViewAccounts ? Colors.orange : Colors.green,
                                    ),
                                  ),
                                ),
                                PopupMenuItem(
                                  value: 'toggle_patients',
                                  child: Text(
                                    employee.canViewPatients
                                        ? ref.tr('hide_patients_page')
                                        : ref.tr('show_patients_page'),
                                    style: TextStyle(
                                      color: employee.canViewPatients ? Colors.orange : Colors.green,
                                    ),
                                  ),
                                ),
                                const PopupMenuDivider(),
                                PopupMenuItem(
                                  value: 'remove',
                                  child: Text(ref.tr('remove_employee'), style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                                ),
                              ],
                            )
                          else
                            Container(
                               padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                               decoration: BoxDecoration(
                                 color: Colors.orange.withAlpha(60),
                                 borderRadius: BorderRadius.circular(12),
                               ),
                               child: Text(ref.tr('admin'), style: const TextStyle(color: Colors.orangeAccent, fontSize: 12, fontWeight: FontWeight.bold)),
                            ),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
            loading: () => const Center(
              child: Padding(
                padding: EdgeInsets.all(20.0),
                child: CircularProgressIndicator(color: Colors.white),
              ),
            ),
            error: (err, _) =>
                Text(ref.tr('error_label', [err.toString()]), style: const TextStyle(color: Colors.white)),
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
    return ref.watch(pendingUsersStreamProvider).when(
          skipLoadingOnRefresh: true,
          skipLoadingOnReload: true,
          data: (pendingUsers) {
            if (pendingUsers.isEmpty) {
              return const SizedBox.shrink();
            }

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.orange.withAlpha(30),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: Colors.orangeAccent.withAlpha(50)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.group_add, color: Colors.orangeAccent),
                          const SizedBox(width: 12),
                          Text(
                            ref.tr('pending_join_requests', [
                              pendingUsers.length.toString(),
                            ]),
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      ...pendingUsers.map((user) {
                        return Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          decoration: BoxDecoration(
                            color: Colors.white.withAlpha(15),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: ListTile(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                            leading: CircleAvatar(
                              backgroundColor: Colors.orange.withAlpha(60),
                              child: const Icon(Icons.person, color: Colors.orangeAccent),
                            ),
                            title: Text(user.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                            subtitle: Text(user.phone, style: TextStyle(color: Colors.white.withAlpha(150), fontSize: 12)),
                            trailing: Wrap(
                              spacing: 0,
                              runSpacing: 0,
                              alignment: WrapAlignment.end,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.check_circle, color: Colors.greenAccent),
                                  onPressed: () => _confirmApprove(context, ref, user),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.cancel, color: Colors.redAccent),
                                  onPressed: () => _confirmReject(context, ref, user),
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
          loading: () => const Center(
            child: Padding(
              padding: EdgeInsets.all(20.0),
              child: CircularProgressIndicator(color: Colors.white),
            ),
          ),
          error: (err, _) => const SizedBox.shrink(),
        );
  }

  Future<void> _confirmApprove(
    BuildContext context,
    WidgetRef ref,
    AppUser user,
  ) async {
    final clinic = ref.read(clinicStreamProvider).value;
    if (clinic == null) return;

    final canWrite = await ref
        .read(permissionServiceProvider)
        .canWrite(clinic.id);
    if (!canWrite) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(ref.tr('accept_employee_error_subs'))),
        );
      }
      return;
    }

    await ref.read(authRepositoryProvider).approveUser(user.id);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(ref.tr('approve_employee_success', [user.name]))),
      );
    }
  }

  Future<void> _confirmReject(
    BuildContext context,
    WidgetRef ref,
    AppUser user,
  ) async {
    showDialog(
      context: context,
      builder: (dialogContext) => DeleteConfirmationDialog(
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

  Future<void> _confirmRemoveUser(
    BuildContext context,
    WidgetRef ref,
    AppUser user,
    String clinicId,
  ) async {
    showDialog(
      context: context,
      builder: (dialogContext) => DeleteConfirmationDialog(
        title: ref.tr('remove_employee_title'),
        content: ref.tr('remove_employee_confirm', [user.name]),
        deleteButtonText: ref.tr('remove_employee_permanently'),
        onDelete: () async {
          final canWrite = await ref
              .read(permissionServiceProvider)
              .canWrite(clinicId);
          if (!canWrite) {
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(ref.tr('remove_employee_subs_error'))),
              );
            }
            return;
          }

          try {
            await ref.read(authRepositoryProvider).removeUserFromClinic(user.id, clinicId);
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                 SnackBar(content: Text(ref.tr('remove_employee_success', [user.name]))),
              );
            }
          } catch (e) {
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                 SnackBar(content: Text(ref.tr('remove_employee_error', [e.toString()]))),
              );
            }
          }
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

  Widget _buildPermissionBadge({
    required IconData icon,
    required String label,
    required bool isActive,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: isActive
            ? Colors.green.withAlpha(40)
            : Colors.red.withAlpha(40),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isActive
              ? Colors.greenAccent.withAlpha(80)
              : Colors.redAccent.withAlpha(80),
          width: 0.5,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 14,
            color: isActive ? Colors.greenAccent : Colors.redAccent,
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: isActive ? Colors.greenAccent : Colors.redAccent,
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
