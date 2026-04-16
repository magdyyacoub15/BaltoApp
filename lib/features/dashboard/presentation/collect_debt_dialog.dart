// ignore_for_file: use_build_context_synchronously
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../patients/domain/patient.dart';
import '../../patients/domain/patients_provider.dart';
import '../../patients/domain/models/medical_record.dart';
import '../../patients/data/patient_repository.dart';
import '../../accounts/data/transaction_repository.dart';
import '../../accounts/domain/transaction.dart';
import '../../accounts/domain/accounts_provider.dart';
import '../../auth/presentation/auth_providers.dart';
import '../../../core/localization/language_provider.dart';

class CollectDebtDialog extends ConsumerStatefulWidget {
  const CollectDebtDialog({super.key});

  @override
  ConsumerState<CollectDebtDialog> createState() => _CollectDebtDialogState();
}

class _CollectDebtDialogState extends ConsumerState<CollectDebtDialog> {
  Patient? _selectedPatient;
  MedicalRecord? _selectedRecord;
  final _amountController = TextEditingController();
  bool _isLoading = false;
  String _searchQuery = '';

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  List<Patient> _getPatientsWithDebt(List<Patient> all) {
    return all
        .where((p) => p.remainingAmount > 0)
        .toList()
      ..sort((a, b) => b.remainingAmount.compareTo(a.remainingAmount));
  }

  List<MedicalRecord> _getDebtsForPatient(Patient p) {
    return p.records
        .where((r) => r.remainingAmount > 0)
        .toList()
      ..sort((a, b) => b.date.compareTo(a.date));
  }

  Future<void> _submitCollection() async {
    final amount = double.tryParse(_amountController.text.trim()) ?? 0;
    if (amount <= 0 || _selectedPatient == null || _selectedRecord == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(ref.tr('invalid_amount'))),
      );
      return;
    }
    if (amount > _selectedRecord!.remainingAmount) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(ref.tr('invalid_amount'))),
      );
      return;
    }

    setState(() => _isLoading = true);
    try {
      final user = ref.read(currentUserProvider).value;
      if (user == null) return;

      debugPrint('🟢 [TRACE][collectDebt] START — amount=$amount, patient=${_selectedPatient!.name} (${_selectedPatient!.id}), clinicId=${user.clinicId}');
      debugPrint('🟢 [TRACE][collectDebt] recordId=${_selectedRecord!.id}, recordRemaining=${_selectedRecord!.remainingAmount}');

      // 1. Deduct from patient debt
      await ref.read(patientRepositoryProvider).payMedicalRecordDebt(
            patient: _selectedPatient!,
            recordId: _selectedRecord!.id,
            amountPaid: amount,
          );
      debugPrint('🟢 [TRACE][collectDebt] ✅ Step 1: payMedicalRecordDebt done');

      // 2. Add revenue transaction for today's accounts
      final transaction = AppTransaction(
        id: '',
        amount: amount,
        description: '${ref.tr('collect_debt_desc')}: ${_selectedPatient!.name}',
        type: TransactionType.revenue,
        date: DateTime.now(),
        clinicId: user.clinicId,
      );
      final txId = await ref.read(transactionRepositoryProvider).addTransaction(transaction);
      debugPrint('🟢 [TRACE][collectDebt] ✅ Step 2: addTransaction returned txId=$txId, clinicId=${user.clinicId}');

      // 3. Refresh providers
      ref.read(transactionsRefreshProvider.notifier).refresh();
      debugPrint('🟢 [TRACE][collectDebt] ✅ Step 3: transactionsRefresh triggered');
      ref.read(patientsRefreshProvider.notifier).refresh();
      debugPrint('🟢 [TRACE][collectDebt] ✅ Step 3: patientsRefresh triggered');

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${ref.tr('collect_debt_success')}: ${amount.toInt()} ${ref.tr('currency')}',
            ),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      debugPrint('🔴 [TRACE][collectDebt] ❌ ERROR: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${ref.tr('error')}: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final patientsAsync = ref.watch(patientsStreamProvider);

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ─── Header ───────────────────────────────────────────
          Container(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.teal.shade700, Colors.teal.shade400],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Row(
              children: [
                const Icon(Icons.monetization_on_rounded,
                    color: Colors.white, size: 26),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    ref.tr('collect_debt'),
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white70),
                  onPressed: () => Navigator.of(context).pop(),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
          ),

          // ─── Body ─────────────────────────────────────────────
          Flexible(
            child: patientsAsync.when(
              loading: () =>
                  const Padding(
                    padding: EdgeInsets.all(40),
                    child: Center(child: CircularProgressIndicator()),
                  ),
              error: (e, _) => Padding(
                padding: const EdgeInsets.all(24),
                child: Text('${ref.tr('error')}: $e'),
              ),
              data: (allPatients) {
                final debtors = _getPatientsWithDebt(allPatients);
                final filtered = _searchQuery.isEmpty
                    ? debtors
                    : debtors
                        .where((p) => p.name
                            .toLowerCase()
                            .contains(_searchQuery.toLowerCase()))
                        .toList();

                if (debtors.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.all(40),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.check_circle_outline,
                            size: 64, color: Colors.green.shade300),
                        const SizedBox(height: 16),
                        Text(
                          ref.tr('no_debts'),
                          style: TextStyle(
                              fontSize: 16, color: Colors.grey.shade600),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  );
                }

                return SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Search field
                      TextField(
                        decoration: InputDecoration(
                          hintText: ref.tr('search_hint'),
                          prefixIcon: const Icon(Icons.search),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide.none,
                          ),
                          filled: true,
                          fillColor: Colors.grey.shade100,
                          contentPadding:
                              const EdgeInsets.symmetric(vertical: 0),
                        ),
                        onChanged: (v) => setState(() => _searchQuery = v),
                      ),
                      const SizedBox(height: 12),

                      // Patient list
                      if (_selectedPatient == null) ...[
                        Text(
                          ref.tr('select_patient_debt'),
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.grey.shade700),
                        ),
                        const SizedBox(height: 8),
                        ...filtered.map((p) => _buildPatientTile(p)),
                      ] else ...[
                        // Selected patient header
                        _buildSelectedPatientHeader(),
                        const SizedBox(height: 12),

                        // Record selection
                        if (_selectedRecord == null) ...[
                          Text(
                            ref.tr('select_record_debt'),
                            style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.grey.shade700),
                          ),
                          const SizedBox(height: 8),
                          ..._getDebtsForPatient(_selectedPatient!)
                              .map((r) => _buildRecordTile(r)),
                        ] else ...[
                          _buildCollectionForm(),
                        ],
                      ],
                    ],
                  ),
                );
              },
            ),
          ),

          // ─── Footer (submit) ──────────────────────────────────
          if (_selectedRecord != null)
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _isLoading
                          ? null
                          : () => setState(() {
                                _selectedRecord = null;
                                _amountController.clear();
                              }),
                      child: Text(ref.tr('back_action')),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton.icon(
                      onPressed: _isLoading ? null : _submitCollection,
                      icon: _isLoading
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.check_rounded),
                      label: Text(ref.tr('collect_now')),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.teal,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildPatientTile(Patient p) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.red.shade100),
      ),
      child: ListTile(
        onTap: () => setState(() {
          _selectedPatient = p;
          _selectedRecord = null;
          _amountController.clear();
        }),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: CircleAvatar(
          backgroundColor: Colors.red.shade100,
          child:
              const Icon(Icons.person_outline, color: Colors.redAccent),
        ),
        title: Text(
          p.name,
          style: const TextStyle(fontWeight: FontWeight.bold),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          '${ref.tr('remaining_amount')}: ${p.remainingAmount.toInt()} ${ref.tr('currency')}',
          style: const TextStyle(
              color: Colors.redAccent, fontWeight: FontWeight.w600),
        ),
        trailing: const Icon(Icons.chevron_right, color: Colors.redAccent),
      ),
    );
  }

  Widget _buildSelectedPatientHeader() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.teal.shade50,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.teal.shade200),
      ),
      child: Row(
        children: [
          const Icon(Icons.person, color: Colors.teal),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _selectedPatient!.name,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 15),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  '${ref.tr('total_debt')}: ${_selectedPatient!.remainingAmount.toInt()} ${ref.tr('currency')}',
                  style: TextStyle(
                      color: Colors.teal.shade700, fontSize: 12),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: () => setState(() {
              _selectedPatient = null;
              _selectedRecord = null;
              _amountController.clear();
            }),
            child: Text(ref.tr('change')),
          ),
        ],
      ),
    );
  }

  Widget _buildRecordTile(MedicalRecord r) {
    final dateStr = '${r.date.day}/${r.date.month}/${r.date.year}';
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.orange.shade100),
      ),
      child: ListTile(
        onTap: () => setState(() {
          _selectedRecord = r;
          _amountController.text = r.remainingAmount.toInt().toString();
        }),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: CircleAvatar(
          backgroundColor: Colors.orange.shade100,
          child: const Icon(Icons.receipt_long_outlined,
              color: Colors.orange),
        ),
        title: Text(
          r.diagnosis.isNotEmpty ? r.diagnosis : ref.tr('visit_details'),
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(dateStr,
            style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
        trailing: Text(
          '${r.remainingAmount.toInt()} ${ref.tr('currency')}',
          style: const TextStyle(
              color: Colors.orange,
              fontWeight: FontWeight.bold,
              fontSize: 14),
        ),
      ),
    );
  }

  Widget _buildCollectionForm() {
    final record = _selectedRecord!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Record info
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.orange.shade50,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.orange.shade200),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                record.diagnosis.isNotEmpty
                    ? record.diagnosis
                    : ref.tr('visit_details'),
                style: const TextStyle(fontWeight: FontWeight.bold),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              Text(
                '${ref.tr('remaining_amount')}: ${record.remainingAmount.toInt()} ${ref.tr('currency')}',
                style: const TextStyle(
                    color: Colors.orange, fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Amount input
        TextField(
          controller: _amountController,
          keyboardType:
              const TextInputType.numberWithOptions(decimal: false),
          autofocus: true,
          decoration: InputDecoration(
            labelText: ref.tr('collected_amount'),
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14)),
            prefixIcon:
                const Icon(Icons.attach_money, color: Colors.teal),
            suffixText: ref.tr('currency'),
            filled: true,
            fillColor: Colors.grey.shade50,
          ),
        ),
        const SizedBox(height: 8),

        // Quick amount buttons
        Wrap(
          spacing: 8,
          children: [50, 100, 200, 500].map((v) {
            final vDouble = v.toDouble();
            if (vDouble > record.remainingAmount) return const SizedBox();
            return ActionChip(
              label: Text('$v'),
              onPressed: () =>
                  _amountController.text = v.toString(),
              backgroundColor: Colors.teal.shade50,
              labelStyle: TextStyle(color: Colors.teal.shade700),
            );
          }).toList()
            ..add(
              ActionChip(
                label: Text(
                    '${ref.tr('full_amount')} (${record.remainingAmount.toInt()})'),
                onPressed: () => _amountController.text =
                    record.remainingAmount.toInt().toString(),
                backgroundColor: Colors.green.shade50,
                labelStyle: TextStyle(color: Colors.green.shade700),
              ),
            ),
        ),
      ],
    );
  }
}
