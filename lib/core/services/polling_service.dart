import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// ─── Page Refresh Provider ────────────────────────────────────────────────────
// Increment this whenever a page is navigated to.
// All data providers watch it → they re-run their cache-first fetch on every
// page open. Cache is yielded instantly; network is checked in background.
class PageRefreshNotifier extends Notifier<int> {
  @override
  int build() => 0;
  void refresh() => state++;
}

final pageRefreshProvider = NotifierProvider<PageRefreshNotifier, int>(
  PageRefreshNotifier.new,
);

// ─── Polling Tick Provider ────────────────────────────────────────────────────
// Emits a new integer every [intervalSeconds] seconds.
// All data providers watch this to auto-refresh for other devices.
final pollingTickProvider = StreamProvider<int>((ref) async* {
  int tick = 0;
  // Emit initial tick immediately
  yield tick;
  while (true) {
    await Future.delayed(const Duration(seconds: 10));
    yield ++tick;
  }
});
