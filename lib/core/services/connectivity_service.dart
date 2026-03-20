import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Stream of connectivity results — emits every time connectivity changes.
final connectivityStreamProvider = StreamProvider<List<ConnectivityResult>>((
  ref,
) {
  return Connectivity().onConnectivityChanged;
});

/// Simple bool provider: true = has internet, false = offline.
final isOnlineProvider = Provider<bool>((ref) {
  final conn = ref.watch(connectivityStreamProvider);
  return conn.when(
    data: (results) =>
        results.isNotEmpty && results.any((r) => r != ConnectivityResult.none),
    loading: () => true, // Assume online while checking
    error: (_, __) => false,
  );
});

/// One-shot async check for current connectivity status.
Future<bool> checkIsOnline() async {
  final results = await Connectivity().checkConnectivity();
  return results.isNotEmpty && results.any((r) => r != ConnectivityResult.none);
}
