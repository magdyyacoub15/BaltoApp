import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/transaction_repository.dart';
import '../domain/transaction.dart';
import '../../auth/presentation/auth_providers.dart';
import '../../../core/services/appwrite_client.dart';

// --- Transactions Notifier (AsyncNotifier for Live Finance) -------------------
final transactionsStreamProvider =
    AsyncNotifierProvider<TransactionsNotifier, List<AppTransaction>>(() {
      return TransactionsNotifier();
    });

class TransactionsNotifier extends AsyncNotifier<List<AppTransaction>> {
  StreamSubscription? _subscription;
  Timer? _pollingTimer;
  bool _isDisposed = false;

  @override
  FutureOr<List<AppTransaction>> build() async {
    final user = ref.watch(currentUserProvider).value;
    if (user == null) return [];

    final repo = ref.watch(transactionRepositoryProvider);
    final clinicId = user.clinicId;

    // Initial fetch from cache/network
    final initialList = await repo.getTransactions(clinicId);

    // Start Realtime and Polling
    _subscribe(clinicId);
    _startPolling(clinicId, repo);

    ref.onDispose(() {
      _isDisposed = true;
      _subscription?.cancel();
      _pollingTimer?.cancel();
    });

    return initialList;
  }

  void _subscribe(String clinicId) {
    _subscription?.cancel();
    final realtime = ref.read(appwriteRealtimeProvider);

    _subscription = realtime
        .subscribe([
          'databases.$appwriteDatabaseId.collections.transactions.documents',
        ])
        .stream
        .listen(
          (event) async {
            debugPrint('REALTIME TRANSACTION EVENT: ${event.events}');
            final payload = event.payload;

            // Filter by clinicId if present in payload
            if (payload.isNotEmpty &&
                payload['clinicId']?.toString().trim() != clinicId.trim()) {
              return;
            }

            // For transactions, we usually just refresh the whole list to be safe with totals
            final repo = ref.read(transactionRepositoryProvider);
            state = AsyncData(await repo.refreshTransactions(clinicId));
          },
          onError: (e) {
            debugPrint('REALTIME TRANSACTION ERROR: $e');
            Future.delayed(const Duration(seconds: 10), () {
              if (!_isDisposed) _subscribe(clinicId);
            });
          },
          onDone: () {
            debugPrint('REALTIME TRANSACTION DONE');
            Future.delayed(const Duration(seconds: 10), () {
              if (!_isDisposed) _subscribe(clinicId);
            });
          },
        );
  }

  void _startPolling(String clinicId, TransactionRepository repo) {
    _pollingTimer?.cancel();
    _pollingTimer = Timer.periodic(const Duration(seconds: 10), (timer) async {
      if (_isDisposed) return;
      try {
        final updated = await repo.refreshTransactions(clinicId);
        state = AsyncData(updated);
      } catch (e) {
        debugPrint('POLLING TRANSACTIONS ERROR: $e');
      }
    });
  }
}

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
