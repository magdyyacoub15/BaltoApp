import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../domain/accounts_provider.dart';
import '../domain/transaction.dart';
import '../../auth/presentation/auth_providers.dart';
import '../data/transaction_repository.dart';
import '../../../core/presentation/widgets/animated_gradient_background.dart';
import '../../../core/presentation/widgets/delete_confirmation_dialog.dart';
import '../../../core/services/permission_service.dart';
import '../../../core/localization/language_provider.dart';

class AccountsScreen extends ConsumerWidget {
  const AccountsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final transactionsAsync = ref.watch(allTransactionsStreamProvider);

    return Scaffold(
      body: AnimatedGradientBackground(
        child: transactionsAsync.when(
          skipLoadingOnRefresh: true,
          skipLoadingOnReload: true,
          data: (transactions) {
            if (transactions.isEmpty) {
              return Center(
                child: Text(
                  ref.tr('no_financial_records'),
                  style: const TextStyle(color: Colors.white70),
                ),
              );
            }

            final grouped = _groupTransactions(transactions, ref);

            return CustomScrollView(
              physics: const BouncingScrollPhysics(),
              slivers: [
                SliverAppBar(
                  expandedHeight: 80,
                  floating: true,
                  pinned: false,
                  elevation: 0,
                  backgroundColor: Colors.transparent,
                  title: Text(
                    ref.tr('accounts_and_finances'),
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 20,
                    ),
                  ),
                  centerTitle: true,
                ),
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final monthKey = grouped.keys.elementAt(index);
                        final monthData = grouped[monthKey]!;

                        return Container(
                          margin: const EdgeInsets.only(bottom: 16),
                          decoration: BoxDecoration(
                            color: Colors.white.withAlpha(20),
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(color: Colors.white.withAlpha(30)),
                          ),
                          child: ExpansionTile(
                            shape: const RoundedRectangleBorder(side: BorderSide.none),
                            collapsedIconColor: Colors.white70,
                            iconColor: Colors.white,
                            title: Text(
                              monthKey,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 18,
                                color: Colors.white,
                              ),
                            ),
                            subtitle: _buildMonthSummary(monthData, ref),
                            children: monthData.keys.map((dayKey) {
                              final dayData = monthData[dayKey]!;
                              return Container(
                                margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.white.withAlpha(15),
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: ExpansionTile(
                                  shape: const RoundedRectangleBorder(side: BorderSide.none),
                                  collapsedIconColor: Colors.white60,
                                  iconColor: Colors.white70,
                                  title: Text(
                                    ref.tr('day_format', [dayKey]),
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  subtitle: _buildDaySummary(dayData, ref),
                                  children: dayData
                                      .map((t) => _buildTransactionTile(context, ref, t))
                                      .toList(),
                                ),
                              );
                            }).toList(),
                          ),
                        );
                      },
                      childCount: grouped.keys.length,
                    ),
                  ),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 80)),
              ],
            );
          },
          loading: () => const Center(child: CircularProgressIndicator(color: Colors.white)),
          error: (e, st) => Center(
            child: Text(
              ref.tr('error_label', [e.toString()]),
              style: const TextStyle(color: Colors.white),
            ),
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddTransactionDialog(context, ref),
        backgroundColor: Colors.white,
        foregroundColor: Colors.blue.shade900,
        child: const Icon(Icons.add, size: 32),
      ),
    );
  }

  Map<String, Map<String, List<AppTransaction>>> _groupTransactions(
    List<AppTransaction> transactions,
    WidgetRef ref,
  ) {
    final Map<String, Map<String, List<AppTransaction>>> grouped = {};

    for (var t in transactions) {
      final lang = ref.read(languageProvider);
      final month = DateFormat('MMMM yyyy', lang.languageCode).format(t.date);
      final day = DateFormat('dd/MM', lang.languageCode).format(t.date);

      grouped.putIfAbsent(month, () => {});
      grouped[month]!.putIfAbsent(day, () => []);
      grouped[month]![day]!.add(t);
    }

    return grouped;
  }

  Widget _buildMonthSummary(
    Map<String, List<AppTransaction>> monthData,
    WidgetRef ref,
  ) {
    double rev = 0;
    double exp = 0;
    for (var day in monthData.values) {
      for (var t in day) {
        if (t.type == TransactionType.revenue) {
          rev += t.amount;
        } else {
          exp += t.amount;
        }
      }
    }
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerRight,
      child: Text(
        ref.tr('month_summary', [rev.toString(), exp.toString()]),
        style: const TextStyle(fontSize: 12, color: Colors.white70),
      ),
    );
  }

  Widget _buildDaySummary(List<AppTransaction> dayData, WidgetRef ref) {
    double rev = 0;
    double exp = 0;
    for (var t in dayData) {
      if (t.type == TransactionType.revenue) {
        rev += t.amount;
      } else {
        exp += t.amount;
      }
    }
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerRight,
      child: Text(
        ref.tr('day_summary', [(rev - exp).toString()]),
        style: const TextStyle(fontSize: 12, color: Colors.white60),
      ),
    );
  }

  Widget _buildTransactionTile(
    BuildContext context,
    WidgetRef ref,
    AppTransaction t,
  ) {
    final isAdmin = ref.read(currentUserProvider).value?.isAdmin == true;
    final isRev = t.type == TransactionType.revenue;
    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.white.withAlpha(20),
          shape: BoxShape.circle,
        ),
        child: Icon(
          isRev ? Icons.trending_up : Icons.trending_down,
          color: isRev ? Colors.lightGreenAccent : Colors.redAccent.shade100,
          size: 20,
        ),
      ),
      title: Text(
        t.description,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w500,
        ),
      ),
      subtitle: Text(
        DateFormat('hh:mm a').format(t.date),
        style: const TextStyle(color: Colors.white60),
      ),
      trailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.white.withAlpha(20),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          ref.tr('amount_egp', [isRev ? '+' : '-', t.amount.toString()]),
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: isRev ? Colors.lightGreenAccent : Colors.redAccent.shade100,
          ),
        ),
      ),
      onLongPress: isAdmin ? () => _confirmDelete(context, ref, t) : null,
    );
  }

  void _confirmDelete(BuildContext context, WidgetRef ref, AppTransaction t) {
    showDialog(
      context: context,
      builder: (dialogContext) => DeleteConfirmationDialog(
        title: ref.tr('delete_transaction_title'),
        content: ref.tr('delete_transaction_confirm'),
        onDelete: () async {
          final clinic = ref.read(clinicStreamProvider).value;
          if (clinic == null) return;

          final canWrite = await ref.read(permissionServiceProvider).canWrite(clinic.id);
          if (!canWrite) {
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(ref.tr('delete_transaction_error_subs'))),
              );
            }
            return;
          }

          await ref.read(transactionRepositoryProvider).deleteTransaction(t.id, clinic.id);
          ref.invalidate(allTransactionsStreamProvider);
        },
      ),
    );
  }

  void _showAddTransactionDialog(BuildContext context, WidgetRef ref) {
    final amountController = TextEditingController();
    final descController = TextEditingController();
    TransactionType selectedType = TransactionType.expense;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(ref.tr('add_new_transaction')),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<TransactionType>(
                  initialValue: selectedType,
                  items: [
                    DropdownMenuItem(
                      value: TransactionType.revenue,
                      child: Text(ref.tr('revenue_pos')),
                    ),
                    DropdownMenuItem(
                      value: TransactionType.expense,
                      child: Text(ref.tr('expense_neg')),
                    ),
                  ],
                  onChanged: (val) => setState(() => selectedType = val!),
                  decoration: InputDecoration(
                    label: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(ref.tr('transaction_type')),
                    ),
                  ),
                ),
                TextField(
                  controller: amountController,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    label: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(ref.tr('amount_egp_label')),
                    ),
                  ),
                ),
                TextField(
                  controller: descController,
                  decoration: InputDecoration(
                    label: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(ref.tr('transaction_desc_hint')),
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

                final transaction = AppTransaction(
                  id: '',
                  amount: double.parse(amountController.text),
                  description: descController.text,
                  type: selectedType,
                  date: DateTime.now(),
                  clinicId: user.clinicId,
                );

                await ref.read(transactionRepositoryProvider).addTransaction(transaction);
                if (context.mounted) Navigator.pop(context);
              },
              child: Text(ref.tr('save_record')),
            ),
          ],
        ),
      ),
    );
  }
}
