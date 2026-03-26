import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
