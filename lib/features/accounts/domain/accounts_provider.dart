import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/transaction_repository.dart';
import '../domain/transaction.dart';
import '../../auth/presentation/auth_providers.dart';

final transactionsStreamProvider = StreamProvider<List<AppTransaction>>((ref) {
  final userAsync = ref.watch(currentUserProvider);
  final repo = ref.watch(transactionRepositoryProvider);

  return userAsync.when(
    data: (user) {
      if (user != null) {
        return repo.getTransactions(user.clinicId);
      }
      return Stream.value([]);
    },
    loading: () => const Stream.empty(),
    error: (e, st) => Stream.error(e, st),
  );
});

final dailyFinanceProvider = Provider<AsyncValue<Map<String, double>>>((ref) {
  final threshold = ref.watch(clinicVisibilityThresholdProvider);
  final transactionsAsync = ref.watch(transactionsStreamProvider);

  return transactionsAsync.whenData((transactions) {
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
});
