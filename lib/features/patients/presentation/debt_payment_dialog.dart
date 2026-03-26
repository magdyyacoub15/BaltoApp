import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../domain/patient.dart';
import '../domain/models/medical_record.dart';
import '../data/patient_repository.dart';
import '../../accounts/data/transaction_repository.dart';
import '../../accounts/domain/transaction.dart';
import '../../accounts/domain/accounts_provider.dart';
import '../domain/patients_provider.dart';
import '../../../core/localization/language_provider.dart';
import '../../auth/presentation/auth_providers.dart';

class DebtPaymentDialog extends ConsumerStatefulWidget {
  final Patient patient;
  final MedicalRecord record;

  const DebtPaymentDialog({
    super.key,
    required this.patient,
    required this.record,
  });

  @override
  ConsumerState<DebtPaymentDialog> createState() => _DebtPaymentDialogState();
}

class _DebtPaymentDialogState extends ConsumerState<DebtPaymentDialog> {
  late TextEditingController _amountController;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _amountController = TextEditingController(
      text: widget.record.remainingAmount.toStringAsFixed(0),
    );
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  Future<void> _submitPayment() async {
    final amount = double.tryParse(_amountController.text) ?? 0.0;
    if (amount <= 0 || amount > widget.record.remainingAmount) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(ref.tr('invalid_amount'))),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final user = ref.read(currentUserProvider).value;
      if (user == null) return;

      // 1. Update Patient Debt
      await ref.read(patientRepositoryProvider).payMedicalRecordDebt(
            patient: widget.patient,
            recordId: widget.record.id,
            amountPaid: amount,
          );

      // 2. Add Income Transaction
      final transaction = AppTransaction(
        id: '',
        amount: amount,
        description: '${ref.tr('debt_payment')}: ${widget.patient.name}',
        type: TransactionType.revenue,
        date: DateTime.now(),
        clinicId: user.clinicId,
      );
      await ref.read(transactionRepositoryProvider).addTransaction(transaction);

      // 3. Refresh Providers
      ref.read(transactionsRefreshProvider.notifier).refresh();
      ref.read(patientsRefreshProvider.notifier).refresh();

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(ref.tr('payment_success')),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
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
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      title: Text(
        ref.tr('pay_debt'),
        style: const TextStyle(fontWeight: FontWeight.bold),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
             '${ref.tr('patient')}: ${widget.patient.name}',
            style: const TextStyle(fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 8),
          Text(
            '${ref.tr('remaining_amount')}: ${widget.record.remainingAmount} ${ref.tr('currency')}',
            style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _amountController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            autofocus: true,
            decoration: InputDecoration(
              labelText: ref.tr('payment_amount'),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              prefixIcon: const Icon(Icons.attach_money),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _isLoading ? null : () => Navigator.pop(context),
          child: Text(ref.tr('cancel')),
        ),
        ElevatedButton(
          onPressed: _isLoading ? null : _submitPayment,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.green,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          child: _isLoading
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : Text(ref.tr('confirm_payment')),
        ),
      ],
    );
  }
}
