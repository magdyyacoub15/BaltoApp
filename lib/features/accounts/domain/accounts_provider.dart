import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/transaction_repository.dart';
import '../domain/transaction.dart';
import '../../auth/presentation/auth_providers.dart';
import '../../../core/services/polling_service.dart';

// ─── Manual Refresh Trigger for Transactions ─────────────────────────────────
class TransactionsRefreshNotifier extends Notifier<int> {
  @override
  int build() => 0;
  void refresh() => state++;
}

final transactionsRefreshProvider =
    NotifierProvider<TransactionsRefreshNotifier, int>(
      TransactionsRefreshNotifier.new,
    );

// ─── Transactions Stream Provider ────────────────────────────────────────────
// Reacts to:
//   1. transactionsRefreshProvider increments (local writes → immediate)
//   2. pollingTickProvider (every 5 sec → other devices)
//   3. clinicVisibilityThresholdProvider changes (end-of-day reset)
final transactionsStreamProvider =
    StreamProvider<List<AppTransaction>>((ref) async* {
  final user = await ref.watch(currentUserProvider.future);
  if (user == null) {
    yield [];
    return;
  }

  final clinicId = user.clinicId;
  final repo = ref.watch(transactionRepositoryProvider);
  final threshold = ref.watch(clinicVisibilityThresholdProvider);

  ref.watch(transactionsRefreshProvider);
  ref.watch(pollingTickProvider);

  final data = await repo.fetchLiveTransactions(clinicId);
  // This one STAYS filtered for the Dashboard (Today's Stats)
  final filtered = data
      .where((t) => t.date.isAfter(threshold) || t.date.isAtSameMomentAs(threshold))
      .toList();
  yield filtered;
});

// ─── ALL Transactions (Unfiltered for Accounts Screen) ───────────────────────
// Cache-first: yields cached data instantly, then refreshes from network in background.
final allTransactionsStreamProvider =
    StreamProvider<List<AppTransaction>>((ref) async* {
  final user = await ref.watch(currentUserProvider.future);
  if (user == null) {
    yield [];
    return;
  }

  final clinicId = user.clinicId;
  final repo = ref.watch(transactionRepositoryProvider);

  ref.watch(transactionsRefreshProvider);
  ref.watch(pollingTickProvider);

  // 1. Yield cached data immediately (no loading spinner)
  final cached = await repo.getTransactions(clinicId);
  if (cached.isNotEmpty) yield cached;

  // 2. Fetch fresh from network in background and yield update
  try {
    final fresh = await repo.fetchLiveTransactions(clinicId);
    yield fresh;
  } catch (_) {
    // If network fails, cached data already shown — silently skip
  }
});

// ─── Daily Finance Stats ──────────────────────────────────────────────────────
final dailyFinanceProvider = Provider<Map<String, double>>((ref) {
  final transactions = ref.watch(transactionsStreamProvider).value ?? [];

  double revenue = 0;
  double expense = 0;

  for (var t in transactions) {
    if (t.type == TransactionType.revenue) {
      revenue += t.amount;
    } else {
      expense += t.amount;
    }
  }

  return {'revenue': revenue, 'expense': expense, 'net': revenue - expense};
});
