import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'offline_queue_service.dart';

// ─── Box Names ───────────────────────────────────────────────────────────────
const _patientsBoxName = 'patients_cache';
const _appointmentsBoxName = 'appointments_cache';
const _transactionsBoxName = 'transactions_cache';
const _clinicBoxName = 'clinic_cache';
const _subscriptionBoxName = 'subscription_cache';

/// Cache TTL: entries older than this are treated as stale and re-fetched.
const _cacheTtl = Duration(minutes: 30);

// ─── Provider ────────────────────────────────────────────────────────────────
final hiveCacheServiceProvider = Provider<HiveCacheService>((ref) {
  return HiveCacheService();
});

/// Opens all required Hive boxes. Call once from main() before runApp().
Future<void> initHive() async {
  await Hive.initFlutter();
  await Hive.openBox<String>(_patientsBoxName);
  await Hive.openBox<String>(_appointmentsBoxName);
  await Hive.openBox<String>(_transactionsBoxName);
  await Hive.openBox<String>(_clinicBoxName);
  await Hive.openBox<String>(_subscriptionBoxName);
  await OfflineQueueService.openBox(); // offline write queue
}

/// Wraps data with a timestamp for TTL-aware caching.
Map<String, dynamic> _wrap(dynamic data) => {
  'ts': DateTime.now().millisecondsSinceEpoch,
  'data': data,
};

/// Returns null if the entry is missing or older than [_cacheTtl].
dynamic _unwrap(String? raw) {
  if (raw == null) return null;
  try {
    final map = json.decode(raw) as Map<String, dynamic>;
    final ts = map['ts'] as int? ?? 0;
    final age = DateTime.now().millisecondsSinceEpoch - ts;
    if (age > _cacheTtl.inMilliseconds) return null; // stale
    return map['data'];
  } catch (_) {
    return null;
  }
}

/// A simple JSON-based cache over Hive boxes with TTL support.
/// Each clinic's data is stored under its clinicId as the key.
class HiveCacheService {
  // ─── Patients ──────────────────────────────────────────────────────────────

  void cachePatients(String clinicId, List<Map<String, dynamic>> patients) {
    Hive.box<String>(_patientsBoxName).put(
      clinicId,
      json.encode(_wrap(patients)),
    );
  }

  List<Map<String, dynamic>>? getCachedPatients(String clinicId) {
    final raw = Hive.box<String>(_patientsBoxName).get(clinicId);
    final data = _unwrap(raw);
    if (data == null) return null;
    return (data as List).cast<Map<String, dynamic>>();
  }

  // ─── Appointments ──────────────────────────────────────────────────────────

  void cacheAppointments(
    String clinicId,
    List<Map<String, dynamic>> appointments,
  ) {
    Hive.box<String>(_appointmentsBoxName).put(
      clinicId,
      json.encode(_wrap(appointments)),
    );
  }

  List<Map<String, dynamic>>? getCachedAppointments(String clinicId) {
    final raw = Hive.box<String>(_appointmentsBoxName).get(clinicId);
    final data = _unwrap(raw);
    if (data == null) return null;
    return (data as List).cast<Map<String, dynamic>>();
  }

  // ─── Transactions ──────────────────────────────────────────────────────────

  void cacheTransactions(
    String clinicId,
    List<Map<String, dynamic>> transactions,
  ) {
    Hive.box<String>(_transactionsBoxName).put(
      clinicId,
      json.encode(_wrap(transactions)),
    );
  }

  List<Map<String, dynamic>>? getCachedTransactions(String clinicId) {
    final raw = Hive.box<String>(_transactionsBoxName).get(clinicId);
    final data = _unwrap(raw);
    if (data == null) return null;
    return (data as List).cast<Map<String, dynamic>>();
  }

  // ─── Clinic / User Data ────────────────────────────────────────────────────

  void cacheValue(String key, Map<String, dynamic> data) {
    Hive.box<String>(_clinicBoxName).put(key, json.encode(_wrap(data)));
  }

  Map<String, dynamic>? getCachedValue(String key) {
    final raw = Hive.box<String>(_clinicBoxName).get(key);
    final data = _unwrap(raw);
    if (data == null) return null;
    return data as Map<String, dynamic>;
  }

  void removeCachedValue(String key) {
    Hive.box<String>(_clinicBoxName).delete(key);
  }

  // ─── Subscription Config ───────────────────────────────────────────────────

  void cacheSubscription(Map<String, dynamic> data) {
    Hive.box<String>(_subscriptionBoxName).put(
      'config',
      json.encode(_wrap(data)),
    );
  }

  Map<String, dynamic>? getCachedSubscription() {
    final raw = Hive.box<String>(_subscriptionBoxName).get('config');
    final data = _unwrap(raw);
    if (data == null) return null;
    return data as Map<String, dynamic>;
  }

  // ─── Utilities ─────────────────────────────────────────────────────────────

  /// Clear all cached data (e.g., after logout)
  Future<void> clearAll() async {
    await Hive.box<String>(_patientsBoxName).clear();
    await Hive.box<String>(_appointmentsBoxName).clear();
    await Hive.box<String>(_transactionsBoxName).clear();
    await Hive.box<String>(_clinicBoxName).clear();
    await Hive.box<String>(_subscriptionBoxName).clear();
  }
}
