import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

// ─── Box Names ───────────────────────────────────────────────────────────────
const _patientsBoxName = 'patients_cache';
const _appointmentsBoxName = 'appointments_cache';
const _transactionsBoxName = 'transactions_cache';
const _clinicBoxName = 'clinic_cache';
const _subscriptionBoxName = 'subscription_cache';

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
}

/// A simple JSON-based cache over Hive boxes.
/// Each clinic's data is stored under its clinicId as the key.
class HiveCacheService {
  // ─── Patients ──────────────────────────────────────────────────────────────

  void cachePatients(String clinicId, List<Map<String, dynamic>> patients) {
    final box = Hive.box<String>(_patientsBoxName);
    box.put(clinicId, json.encode(patients));
  }

  List<Map<String, dynamic>>? getCachedPatients(String clinicId) {
    final box = Hive.box<String>(_patientsBoxName);
    final raw = box.get(clinicId);
    if (raw == null) return null;
    final list = json.decode(raw) as List<dynamic>;
    return list.cast<Map<String, dynamic>>();
  }

  // ─── Appointments ──────────────────────────────────────────────────────────

  void cacheAppointments(
    String clinicId,
    List<Map<String, dynamic>> appointments,
  ) {
    final box = Hive.box<String>(_appointmentsBoxName);
    box.put(clinicId, json.encode(appointments));
  }

  List<Map<String, dynamic>>? getCachedAppointments(String clinicId) {
    final box = Hive.box<String>(_appointmentsBoxName);
    final raw = box.get(clinicId);
    if (raw == null) return null;
    final list = json.decode(raw) as List<dynamic>;
    return list.cast<Map<String, dynamic>>();
  }

  // ─── Transactions ──────────────────────────────────────────────────────────

  void cacheTransactions(
    String clinicId,
    List<Map<String, dynamic>> transactions,
  ) {
    final box = Hive.box<String>(_transactionsBoxName);
    box.put(clinicId, json.encode(transactions));
  }

  List<Map<String, dynamic>>? getCachedTransactions(String clinicId) {
    final box = Hive.box<String>(_transactionsBoxName);
    final raw = box.get(clinicId);
    if (raw == null) return null;
    final list = json.decode(raw) as List<dynamic>;
    return list.cast<Map<String, dynamic>>();
  }

  // ─── Clinic / User Data ────────────────────────────────────────────────────

  void cacheValue(String key, Map<String, dynamic> data) {
    final box = Hive.box<String>(_clinicBoxName);
    box.put(key, json.encode(data));
  }

  Map<String, dynamic>? getCachedValue(String key) {
    final box = Hive.box<String>(_clinicBoxName);
    final raw = box.get(key);
    if (raw == null) return null;
    return json.decode(raw) as Map<String, dynamic>;
  }

  void removeCachedValue(String key) {
    Hive.box<String>(_clinicBoxName).delete(key);
  }

  // ─── Subscription Config ───────────────────────────────────────────────────

  void cacheSubscription(Map<String, dynamic> data) {
    final box = Hive.box<String>(_subscriptionBoxName);
    box.put('config', json.encode(data));
  }

  Map<String, dynamic>? getCachedSubscription() {
    final box = Hive.box<String>(_subscriptionBoxName);
    final raw = box.get('config');
    if (raw == null) return null;
    return json.decode(raw) as Map<String, dynamic>;
  }

  // ─── Utilities ─────────────────────────────────────────────────────────────

  /// Clear all cached data for a specific clinic (e.g., after logout)
  Future<void> clearAll() async {
    await Hive.box<String>(_patientsBoxName).clear();
    await Hive.box<String>(_appointmentsBoxName).clear();
    await Hive.box<String>(_transactionsBoxName).clear();
    await Hive.box<String>(_clinicBoxName).clear();
    await Hive.box<String>(_subscriptionBoxName).clear();
  }
}
