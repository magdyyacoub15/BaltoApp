import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../patients/presentation/add_patient_screen.dart';
import '../../patients/presentation/patient_profile_screen.dart';
import '../../appointments/domain/appointments_provider.dart';
import '../../appointments/data/appointment_repository.dart';
import '../../appointments/domain/appointment.dart';
import '../../auth/presentation/auth_providers.dart';
import '../../auth/data/auth_repository.dart';
import '../../accounts/domain/accounts_provider.dart';
import '../../accounts/data/transaction_repository.dart';
import '../../accounts/domain/transaction.dart';
import '../../patients/data/patient_repository.dart';
import '../../../core/presentation/widgets/scaled_icon.dart';
import '../../../core/presentation/widgets/animated_gradient_background.dart';
import '../../../core/presentation/widgets/delete_confirmation_dialog.dart';
import '../../../core/services/permission_service.dart';
import '../../../core/localization/language_provider.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final todayAppointmentsCount = ref.watch(todayAppointmentsCountProvider);
    final waitingNowCount = ref.watch(waitingPatientsCountProvider);
    final quickAppointmentsAsync = ref.watch(enrichedAppointmentsProvider);
    final dailyFinance = ref.watch(dailyFinanceProvider);

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
                ref.tr('dashboard_title'),
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 24,
                ),
              ),
              centerTitle: true,
            ),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 20.0),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  const SizedBox(height: 10),
                  _buildStatSection(
                    context,
                    ref,
                    todayAppointmentsCount,
                    waitingNowCount,
                    dailyFinance,
                  ),
                  const SizedBox(height: 24),
                  _buildDateHeader(context, ref),
                  const SizedBox(height: 32),
                  _buildLiveQueue(context, ref, quickAppointmentsAsync),
                  const SizedBox(height: 80), // Padding for FAB
                ]),
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: _buildDashboardFAB(context, ref),
    );
  }

  Widget _buildDateHeader(BuildContext context, WidgetRef ref) {
    final now = DateTime.now();
    final dateStr = DateFormat(
      'EEEE, d MMMM yyyy',
      ref.watch(languageProvider).languageCode,
    ).format(now);

    return Row(
      children: [
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white.withAlpha(30),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withAlpha(40)),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.calendar_month_rounded,
                  color: Colors.white,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerRight,
                    child: Text(
                      dateStr,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 8),
        InkWell(
          onTap: () {
            final user = ref.read(currentUserProvider).value;
            if (user?.clinicId != null) {
              _showEndWorkDialog(context, ref, user!.clinicId);
            }
          },
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.redAccent.withAlpha(40),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.redAccent.withAlpha(60)),
            ),
            child: Text(
              ref.tr('end_day'),
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStatSection(
    BuildContext context,
    WidgetRef ref,
    int appointments,
    int waiting,
    AsyncValue<Map<String, double>> dailyFinance,
  ) {
    return dailyFinance.when(
      data: (finance) => Row(
        children: [
          Expanded(
            child: _buildGradientCard(
              context,
              ref.tr('appointments'),
              '$appointments',
              Icons.calendar_today_rounded,
              [const Color(0xFF6441A5), const Color(0xFF2a0845)],
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: _buildGradientCard(
              context,
              ref.tr('waiting'),
              '$waiting',
              Icons.people_alt_rounded,
              [const Color(0xFFF2994A), const Color(0xFFF2C94C)],
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: InkWell(
              onTap: () => _showIncomeDetailsDialog(context, ref),
              borderRadius: BorderRadius.circular(24),
              child: _buildGradientCard(
                context,
                ref.tr('net_income'),
                '${finance['net']?.toInt() ?? 0}',
                Icons.account_balance_wallet_rounded,
                [const Color(0xFF11998e), const Color(0xFF38ef7d)],
              ),
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: InkWell(
              onTap: () => _showExpenseDetailsDialog(context, ref),
              borderRadius: BorderRadius.circular(24),
              child: _buildGradientCard(
                context,
                ref.tr('expenses'),
                '${finance['expense']?.toInt() ?? 0}',
                Icons.money_off_rounded,
                [const Color(0xFFE53935), const Color(0xFFE35D5B)],
              ),
            ),
          ),
        ],
      ),
      loading: () => Row(
        children: [
          Expanded(
            child: _buildGradientCard(
              context,
              ref.tr('appointments'),
              '$appointments',
              Icons.calendar_today_rounded,
              [const Color(0xFF6441A5), const Color(0xFF2a0845)],
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: _buildGradientCard(
              context,
              ref.tr('waiting'),
              '$waiting',
              Icons.people_alt_rounded,
              [const Color(0xFFF2994A), const Color(0xFFF2C94C)],
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: _buildGradientCard(
              context,
              ref.tr('net_income'),
              '...',
              Icons.account_balance_wallet_rounded,
              [const Color(0xFF11998e), const Color(0xFF38ef7d)],
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: _buildGradientCard(
              context,
              ref.tr('expenses'),
              '...',
              Icons.money_off_rounded,
              [const Color(0xFFE53935), const Color(0xFFE35D5B)],
            ),
          ),
        ],
      ),
      error: (e, _) => Row(
        children: [
          Expanded(
            child: _buildGradientCard(
              context,
              ref.tr('appointments'),
              '$appointments',
              Icons.calendar_today_rounded,
              [const Color(0xFF6441A5), const Color(0xFF2a0845)],
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: _buildGradientCard(
              context,
              ref.tr('waiting'),
              '$waiting',
              Icons.people_alt_rounded,
              [const Color(0xFFF2994A), const Color(0xFFF2C94C)],
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: _buildGradientCard(
              context,
              ref.tr('net_income'),
              '!',
              Icons.account_balance_wallet_rounded,
              [const Color(0xFF11998e), const Color(0xFF38ef7d)],
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: _buildGradientCard(
              context,
              ref.tr('expenses'),
              '!',
              Icons.money_off_rounded,
              [const Color(0xFFE53935), const Color(0xFFE35D5B)],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGradientCard(
    BuildContext context,
    String title,
    String value,
    IconData icon,
    List<Color> colors,
  ) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: colors,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ScaledIcon(icon, color: Colors.white, size: 16),
            const SizedBox(height: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    value,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(height: 2),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    title,
                    style: const TextStyle(color: Colors.white70, fontSize: 9),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLiveQueue(
    BuildContext context,
    WidgetRef ref,
    AsyncValue<List<Appointment>> appointmentsAsync,
  ) {
    return appointmentsAsync.when(
      data: (appointments) {
        if (appointments.isEmpty) {
          return Container(
            width: double.infinity,
            padding: const EdgeInsets.all(40),
            decoration: BoxDecoration(
              color: Colors.white.withAlpha(20),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Colors.white.withAlpha(30)),
            ),
            child: Column(
              children: [
                ScaledIcon(
                  Icons.event_busy_rounded,
                  size: 48,
                  color: Colors.white60,
                ),
                SizedBox(height: 16),
                Text(
                  ref.tr('no_appointments'),
                  style: const TextStyle(color: Colors.white70, fontSize: 16),
                ),
              ],
            ),
          );
        }
        return ReorderableListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: appointments.length,
          onReorder: (int oldIndex, int newIndex) async {
            if (oldIndex < newIndex) {
              newIndex -= 1;
            }
            final item = appointments.removeAt(oldIndex);
            appointments.insert(newIndex, item);

            // Update queueOrder for the reordered list
            final updatedAppointments = <Appointment>[];
            for (int i = 0; i < appointments.length; i++) {
              updatedAppointments.add(appointments[i].copyWith(queueOrder: i));
            }

            // Save new order to Firestore
            await ref
                .read(appointmentRepositoryProvider)
                .updateQueueOrder(updatedAppointments);
          },
          itemBuilder: (context, index) {
            final appt = appointments[index];
            final item = Container(
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: appt.isCompleted
                    ? Colors.green.withAlpha(20)
                    : Colors.white.withAlpha(25),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: appt.isCompleted
                      ? Colors.green.withAlpha(80)
                      : Colors.white.withAlpha(30),
                  width: appt.isCompleted ? 1.5 : 1,
                ),
              ),
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 4,
                ),
                onTap: appt.patient != null
                    ? () {
                        showDialog(
                          context: context,
                          builder: (context) =>
                              AddPatientScreen(patient: appt.patient),
                        );
                      }
                    : null,
                leading: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: Colors.white.withAlpha(20),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Center(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        '${index + 1}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ),
                ),
                title: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: Text(
                    appt.patient?.name ?? ref.tr('patient_not_known'),
                    maxLines: 1,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
                subtitle: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: Row(
                    children: [
                      Text(
                        DateFormat(
                          'hh:mm a',
                          ref.watch(languageProvider).languageCode,
                        ).format(appt.date),
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.white70,
                        ),
                      ),
                      const Text(
                        ' • ',
                        style: TextStyle(color: Colors.white30),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: _getStatusColor(appt).withAlpha(50),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: _getStatusColor(appt).withAlpha(100),
                            width: 1,
                          ),
                        ),
                        child: Text(
                          ref.tr(appt.type),
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: _getStatusColor(appt).withAlpha(255),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (appt.patient != null)
                      IconButton(
                        icon: const Icon(
                          Icons.contact_page_outlined,
                          color: Colors.white70,
                          size: 20,
                        ),
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) =>
                                  PatientProfileScreen(patient: appt.patient!),
                            ),
                          );
                        },
                      ),
                    const SizedBox(width: 4),
                    appt.isWaiting && !appt.isCompleted
                        ? SizedBox(
                            height: 32,
                            child: ElevatedButton(
                              onPressed: () =>
                                  _completeAppointment(context, ref, appt),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.green,
                                foregroundColor: Colors.white,
                                elevation: 0,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                              child: Text(
                                ref.tr('enter'),
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          )
                        : (appt.isCompleted
                              ? const Icon(
                                  Icons.check_circle,
                                  color: Colors.green,
                                  size: 20,
                                )
                              : const Icon(
                                  Icons.access_time,
                                  color: Colors.orange,
                                  size: 20,
                                )),
                  ],
                ),
              ),
            );

            return ReorderableDelayedDragStartListener(
              index: index,
              key: Key(appt.id),
              child: appt.isCompleted
                  ? item
                  : Dismissible(
                      key: Key('dismiss_${appt.id}'),
                      direction: DismissDirection.endToStart,
                      background: Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        decoration: BoxDecoration(
                          color: Colors.red.shade400,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        alignment: Alignment.centerLeft,
                        padding: const EdgeInsets.only(left: 20),
                        child: const Icon(
                          Icons.delete_outline,
                          color: Colors.white,
                        ),
                      ),
                      confirmDismiss: (direction) async {
                        return await showDialog<bool>(
                          context: context,
                          builder: (context) => DeleteConfirmationDialog(
                            title: ref.tr('delete_from_queue'),
                            content: ref.tr('delete_confirm_queue', [
                              appt.patient?.name ?? ref.tr('patient_not_known'),
                            ]),
                            onDelete: () {}, // Handled by Dismissible
                          ),
                        );
                      },
                      onDismissed: (direction) async {
                        final apptId = appt.id;
                        final patientName =
                            appt.patient?.name ?? ref.tr('unknown_patient');

                        await ref
                            .read(appointmentRepositoryProvider)
                            .deleteAppointment(apptId);

                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                ref.tr('deleted_from_queue', [patientName]),
                              ),
                              backgroundColor: Colors.red.shade400,
                              duration: const Duration(seconds: 2),
                            ),
                          );
                        }
                      },
                      child: item,
                    ),
            );
          },
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, st) => Center(child: Text('${ref.tr('error')}: $e')),
    );
  }

  // --- Helper Methods (Reused Logic) ---

  Color _getStatusColor(Appointment appt) {
    if (appt.isCompleted) return Colors.green;
    if (appt.type == 're_examination' ||
        appt.type == 'إعادة كشف' ||
        appt.type == 'Re-examination') {
      return Colors.orangeAccent;
    }
    if (appt.type == 'new_examination' ||
        appt.type == 'كشف جديد' ||
        appt.type == 'New Examination') {
      return Colors.cyanAccent;
    }
    return Colors.white70;
  }

  Future<void> _completeAppointment(
    BuildContext context,
    WidgetRef ref,
    Appointment appt,
  ) async {
    final user = ref.read(currentUserProvider).value;
    if (user == null) return;
    await ref
        .read(appointmentRepositoryProvider)
        .updateAppointment(appt.copyWith(isWaiting: false, isCompleted: true));

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
          content: Text(ref.tr('logged_in_success')),
        ),
      );
    }
  }

  void _showAddExpenseDialog(BuildContext context, WidgetRef ref) {
    final amountController = TextEditingController();
    final descController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Text(ref.tr('add_expense')),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: amountController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  label: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(ref.tr('amount')),
                  ),
                ),
              ),
              TextField(
                controller: descController,
                decoration: InputDecoration(
                  label: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(ref.tr('description')),
                  ),
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
              final user = ref.read(currentUserProvider).value;
              if (user == null || amountController.text.isEmpty) return;
              final expense = AppTransaction(
                id: '',
                amount: double.parse(amountController.text),
                description: descController.text,
                type: TransactionType.expense,
                date: DateTime.now(),
                clinicId: user.clinicId,
              );
              await ref
                  .read(transactionRepositoryProvider)
                  .addTransaction(expense);
              if (context.mounted) Navigator.pop(context);
            },
            child: Text(ref.tr('save')),
          ),
        ],
      ),
    );
  }

  void _showIncomeDetailsDialog(BuildContext context, WidgetRef ref) {
    final threshold = ref.read(clinicVisibilityThresholdProvider);
    final transactionsAsync = ref.watch(transactionsStreamProvider);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Text(
          ref.tr('income_details'),
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: transactionsAsync.when(
            data: (transactions) {
              final todayIncomes = transactions
                  .where(
                    (t) =>
                        (t.date.isAfter(threshold) ||
                            t.date.isAtSameMomentAs(threshold)) &&
                        t.type == TransactionType.revenue,
                  )
                  .toList();

              if (todayIncomes.isEmpty) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Text(ref.tr('no_income_today')),
                  ),
                );
              }

              return ListView.separated(
                shrinkWrap: true,
                itemCount: todayIncomes.length,
                separatorBuilder: (context, index) => const Divider(),
                itemBuilder: (context, index) {
                  final income = todayIncomes[index];
                  return ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 0,
                      vertical: 0,
                    ),
                    leading: CircleAvatar(
                      radius: 14,
                      backgroundColor: Colors.greenAccent.withValues(
                        alpha: 0.2,
                      ),
                      child: Text(
                        '${index + 1}',
                        style: const TextStyle(
                          color: Colors.green,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    title: Text(
                      income.description.isNotEmpty
                          ? income.description
                          : ref.tr('unspecified_revenue'),
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 4),
                        Text(
                          DateFormat(
                            'hh:mm a',
                            ref.watch(languageProvider).languageCode,
                          ).format(income.date),
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                    trailing: Text(
                      '+${income.amount.toInt()} ${ref.tr('currency')}',
                      style: const TextStyle(
                        color: Colors.green,
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                  );
                },
              );
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) =>
                Center(child: Text(ref.tr('error_occurred', [e.toString()]))),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(ref.tr('close')),
          ),
        ],
      ),
    );
  }

  void _showExpenseDetailsDialog(BuildContext context, WidgetRef ref) {
    final threshold = ref.read(clinicVisibilityThresholdProvider);
    final transactionsAsync = ref.watch(transactionsStreamProvider);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Text(
          ref.tr('expense_details'),
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: transactionsAsync.when(
            data: (transactions) {
              final todayExpenses = transactions
                  .where(
                    (t) =>
                        (t.date.isAfter(threshold) ||
                            t.date.isAtSameMomentAs(threshold)) &&
                        t.type == TransactionType.expense,
                  )
                  .toList();

              if (todayExpenses.isEmpty) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Text(ref.tr('no_expenses_today')),
                  ),
                );
              }

              return ListView.separated(
                shrinkWrap: true,
                itemCount: todayExpenses.length,
                separatorBuilder: (context, index) => const Divider(),
                itemBuilder: (context, index) {
                  final expense = todayExpenses[index];
                  return ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 0,
                      vertical: 0,
                    ),
                    leading: CircleAvatar(
                      radius: 14,
                      backgroundColor: Colors.redAccent.withValues(alpha: 0.2),
                      child: Text(
                        '${index + 1}',
                        style: const TextStyle(
                          color: Colors.red,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    title: Text(
                      expense.description.isNotEmpty
                          ? expense.description
                          : ref.tr('unspecified_expense'),
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 4),
                        Text(
                          DateFormat(
                            'hh:mm a',
                            ref.watch(languageProvider).languageCode,
                          ).format(expense.date),
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                    trailing: Text(
                      '-${expense.amount.toInt()} ${ref.tr('currency')}',
                      style: const TextStyle(
                        color: Colors.red,
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                  );
                },
              );
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) =>
                Center(child: Text(ref.tr('error_occurred', [e.toString()]))),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(ref.tr('close')),
          ),
        ],
      ),
    );
  }

  Widget _buildDashboardFAB(BuildContext context, WidgetRef ref) {
    return FloatingActionButton(
      onPressed: () {
        showModalBottomSheet(
          context: context,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          builder: (sheetContext) => SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(vertical: 24.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 40,
                    height: 5,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    ref.tr('quick_add'),
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  ListTile(
                    leading: const CircleAvatar(
                      backgroundColor: Colors.blueAccent,
                      child: Icon(
                        Icons.person_add_rounded,
                        color: Colors.white,
                      ),
                    ),
                    title: Text(
                      ref.tr('new_examination'),
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text(ref.tr('add_patient_to_queue_desc')),
                    onTap: () async {
                      Navigator.pop(sheetContext);
                      final clinic = ref.read(clinicStreamProvider).value;
                      if (clinic == null) return;

                      final canWrite = await ref
                          .read(permissionServiceProvider)
                          .canWrite(clinic.id);

                      if (!context.mounted) return;

                      if (!canWrite) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              ref.tr('add_restricted_subscription'),
                            ),
                          ),
                        );
                        return;
                      }

                      showDialog(
                        context: context,
                        builder: (ctx) => const AddPatientScreen(),
                      );
                    },
                  ),
                  ListTile(
                    leading: const CircleAvatar(
                      backgroundColor: Colors.redAccent,
                      child: Icon(
                        Icons.receipt_long_rounded,
                        color: Colors.white,
                      ),
                    ),
                    title: Text(
                      ref.tr('add_expense'),
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text(ref.tr('record_financial_entry_desc')),
                    onTap: () async {
                      Navigator.pop(sheetContext);
                      final clinic = ref.read(clinicStreamProvider).value;
                      if (clinic == null) return;

                      final canWrite = await ref
                          .read(permissionServiceProvider)
                          .canWrite(clinic.id);

                      if (!context.mounted) return;

                      if (!canWrite) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              ref.tr('add_restricted_subscription'),
                            ),
                          ),
                        );
                        return;
                      }

                      _showAddExpenseDialog(context, ref);
                    },
                  ),
                ],
              ),
            ),
          ),
        );
      },
      backgroundColor: Theme.of(context).primaryColor,
      child: const ScaledIcon(Icons.add, size: 28),
    );
  }

  void _showEndWorkDialog(
    BuildContext context,
    WidgetRef ref,
    String clinicId,
  ) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(ref.tr('end_day_confirm_title')),
        content: Text(ref.tr('end_day_confirm_content')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(ref.tr('cancel')),
          ),
          ElevatedButton(
            onPressed: () async {
              // Finalize all remaining patient records from today
              await ref
                  .read(patientRepositoryProvider)
                  .finalizeAllPendingRecords(clinicId);

              // Reset shift visibility threshold
              await ref.read(authRepositoryProvider).resetShift(clinicId);

              // Force invalidate relevant providers to ensure UI catches up immediately
              ref.invalidate(clinicStreamProvider);
              ref.invalidate(appointmentsStreamProvider);
              ref.invalidate(dailyFinanceProvider);

              if (context.mounted) {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(ref.tr('dashboard_reset_success'))),
                );
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: Text(
              ref.tr('confirm_end'),
              style: const TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}
