import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// ─── Polling Tick Provider ────────────────────────────────────────────────────
// Emits a new integer every [intervalSeconds] seconds.
// All data providers watch this to auto-refresh for other devices.
final pollingTickProvider = StreamProvider<int>((ref) async* {
  int tick = 0;
  while (true) {
    await Future.delayed(const Duration(seconds: 8));
    yield ++tick;
  }
});
