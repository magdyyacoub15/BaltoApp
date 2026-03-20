import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/transaction_repository.dart';
import '../domain/transaction.dart';
import '../../auth/presentation/auth_providers.dart';
import '../../../core/services/appwrite_client.dart';
import '../../appointments/domain/appointments_provider.dart';

// ─── Realtime Transactions Stream (for Dashboard Live Finance Totals) ─────────
final transactionsStreamProvider = StreamProvider<List<AppTransaction>>((ref) {
  final userAsync = ref.watch(authStateProvider);
  final user = userAsync.value;
  if (user == null) return Stream.value([]);

  final realtime = ref.watch(appwriteRealtimeProvider);
  final repo = ref.watch(transactionRepositoryProvider);
  final controller = StreamController<List<AppTransaction>>();

  ref.read(currentUserProvider.future).then((appUser) async {
    if (appUser == null) return;
    final clinicId = appUser.clinicId;

    // Initial data
    final initial = await repo.getTransactions(clinicId);
    if (!controller.isClosed) controller.add(initial);

    // Subscribe to Realtime changes
    final subscription = realtime.subscribe([
      'databases.$appwriteDatabaseId.collections.transactions.documents',
    ]);

    subscription.stream.listen((_) async {
      final updated = await repo.refreshTransactions(clinicId);
      if (!controller.isClosed) controller.add(updated);
    });

    ref.onDispose(() {
      subscription.close();
      controller.close();
    });
  });

  return controller.stream;
});

// ─── Daily Finance Stats ──────────────────────────────────────────────────────
final dailyFinanceProvider = FutureProvider<Map<String, double>>((ref) async {
  final threshold = await ref.watch(clinicVisibilityThresholdProvider.future);
  final transactions = await ref.watch(transactionsStreamProvider.future);

  final todayTransactions = transactions.where((t) {
    return t.date.isAfter(threshold) || t.date.isAtSameMomentAs(threshold);
  });

  double revenue = 0;
  double expense = 0;

  for (var t in todayTransactions) {
    if (t.type == TransactionType.revenue) {
      revenue += t.amount;
    } else {
      expense += t.amount;
    }
  }

  return {'revenue': revenue, 'expense': expense, 'net': revenue - expense};
});
