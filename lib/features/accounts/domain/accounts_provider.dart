import 'package:flutter/foundation.dart';
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

// ─── Transactions Stream ─────────────────────────────────────────────────────
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

  // Watch triggers that force a rebuild
  ref.watch(transactionsRefreshProvider);
  ref.watch(pollingTickProvider);
  ref.watch(pageRefreshProvider);

  // 1. Yield cached data immediately
  final cached = await repo.getTransactions(clinicId);
  final cachedFiltered = cached.where((t) {
    final isMatched = t.date.toUtc().isAfter(threshold);
    if (!isMatched) {
       // debugPrint("ℹ️ [Tracer] tx filtered out: ${t.id} date=${t.date.toUtc().toIso8601String()} threshold=${threshold.toIso8601String()}");
    }
    return isMatched;
  }).toList();
      
  debugPrint("🔄 [Tracer] txStream(cached): showing=${cachedFiltered.length}, totalCached=${cached.length} (Threshold: ${threshold.toIso8601String()})");
  for (final t in cachedFiltered) {
     debugPrint("✅ [Tracer] tx PASS filter: ${t.id} date=${t.date.toUtc().toIso8601String()}");
  }
  
  yield cachedFiltered;

  // 2. Fetch fresh from network
  try {
    final fresh = await repo.fetchLiveTransactions(clinicId);
    final freshFiltered = fresh.where((t) => t.date.toUtc().isAfter(threshold)).toList();
    debugPrint("🔄 [Tracer] txStream(network): showing=${freshFiltered.length}, totalNetwork=${fresh.length}");
    yield freshFiltered;
  } catch (_) {
    // Silently ignore network errors if cache is already shown
  }
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
  ref.watch(pageRefreshProvider);

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
  // Use the ALREADY filtered stream
  final transactions = ref.watch(transactionsStreamProvider).value ?? [];
  final threshold = ref.watch(clinicVisibilityThresholdProvider);
  
  double revenue = 0.0;
  double expense = 0.0;

  for (final t in transactions) {
    if (t.type == TransactionType.revenue) {
      revenue += t.amount;
    } else {
      expense += t.amount;
    }
  }

  debugPrint("🔄 [Tracer] dailyFinance: calculated from ${transactions.length} items (Threshold: $threshold)");
  return {'revenue': revenue, 'expense': expense, 'net': revenue - expense};
});
