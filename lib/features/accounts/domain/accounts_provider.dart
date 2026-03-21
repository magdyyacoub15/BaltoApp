import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/transaction_repository.dart';
import '../domain/transaction.dart';
import '../../auth/presentation/auth_providers.dart';
import '../../../core/services/appwrite_client.dart';

// ─── Realtime Transactions Stream (for Dashboard Live Finance Totals) ─────────
final transactionsStreamProvider = StreamProvider<List<AppTransaction>>((
  ref,
) async* {
  final userAsync = ref.watch(currentUserProvider);
  final user = userAsync.value;
  if (user == null) {
    yield [];
    return;
  }

  final realtime = ref.watch(appwriteRealtimeProvider);
  final repo = ref.watch(transactionRepositoryProvider);
  final clinicId = user.clinicId;

  // Initial load
  yield await repo.getTransactions(clinicId);

  // Subscribe to Realtime changes
  final subscription = realtime.subscribe([
    'databases.$appwriteDatabaseId.collections.transactions.documents',
  ]);

  ref.onDispose(() {
    subscription.close();
  });

  // Listen for real-time events and refresh from the cache/network
  await for (final _ in subscription.stream) {
    try {
      final updated = await repo.refreshTransactions(clinicId);
      yield updated;
    } catch (_) {}
  }
});

// ─── Daily Finance Stats ──────────────────────────────────────────────────────
final dailyFinanceProvider = FutureProvider<Map<String, double>>((ref) async {
  final threshold = await ref.watch(clinicVisibilityThresholdProvider.future);

  // Watch the stream directly to trigger rebuilds on every new emission
  final transactionsAsync = ref.watch(transactionsStreamProvider);
  final transactions = transactionsAsync.value ?? [];

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
