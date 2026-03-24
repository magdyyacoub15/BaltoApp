import 'package:flutter/foundation.dart';
import 'package:appwrite/appwrite.dart';
// ignore_for_file: deprecated_member_use
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'appwrite_client.dart';

enum SubscriptionStatus { active, trial, expired, offline }

final subscriptionServiceProvider = Provider((ref) {
  return SubscriptionService(ref.read(appwriteTablesDBProvider));
});

class SubscriptionService {
  final TablesDB _databases;

  // Caching variables — keyed by clinicId to prevent cross-clinic leakage
  final Map<String, SubscriptionStatus> _cachedStatusMap = {};
  final Map<String, DateTime> _lastCheckTimeMap = {};
  static const Duration _cacheDuration = Duration(hours: 12);

  SubscriptionService(this._databases);

  // Securely fetch network time to prevent local clock manipulation
  Future<DateTime?> _fetchRealTime() async {
    try {
      final response = await http
          .get(Uri.parse('https://worldtimeapi.org/api/timezone/Etc/UTC'))
          .timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return DateTime.parse(data['utc_datetime']).toLocal();
      }
    } catch (e) {
      debugPrint("WorldTimeAPI fetch failed: $e");
    }

    try {
      final response = await http
          .get(
            Uri.parse('https://timeapi.io/api/Time/current/zone?timeZone=UTC'),
          )
          .timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return DateTime.parse(data['dateTime']).toLocal();
      }
    } catch (e) {
      debugPrint("TimeApi.io fetch failed: $e");
    }
    return null;
  }

  Future<SubscriptionStatus> checkSubscriptionStatus(
    String clinicId, {
    bool forceRefresh = false,
  }) async {
    final prefs = await SharedPreferences.getInstance();

    // 1. Return memory-cached status if valid (keyed by clinicId)
    final cachedStatus = _cachedStatusMap[clinicId];
    final lastCheckTime = _lastCheckTimeMap[clinicId];
    if (!forceRefresh &&
        cachedStatus != null &&
        lastCheckTime != null &&
        DateTime.now().difference(lastCheckTime) < _cacheDuration) {
      return cachedStatus;
    }

    try {
      // 2. Get Real Time
      final DateTime? networkNow = await _fetchRealTime();

      if (networkNow == null) {
        // Fallback to disk cache if network time fails (Offline)
        final statusStr = prefs.getString('sub_status_$clinicId');
        final lastCheckStr = prefs.getString('sub_last_check_$clinicId');

        if (statusStr != null && lastCheckStr != null) {
          final DateTime lastCheckData = DateTime.parse(lastCheckStr);
          // Security: 48-Hour Max Offline Limit
          if (DateTime.now().difference(lastCheckData) >
              const Duration(hours: 48)) {
            return SubscriptionStatus.expired;
          }
          return SubscriptionStatus.values.firstWhere(
            (e) => e.name == statusStr,
          );
        }
        return SubscriptionStatus.offline;
      }

      // 3. Fetch from Appwrite
      final doc = await _databases.getRow(
        databaseId: appwriteDatabaseId,
        tableId: 'clinics',
        rowId: clinicId,
      );

      final data = doc.data;
      if (!data.containsKey('subscriptionEndDate') ||
          data['subscriptionEndDate'] == null) {
        return SubscriptionStatus.expired;
      }

      final DateTime endDate = DateTime.parse(
        data['subscriptionEndDate'].toString(),
      ).toLocal();
      SubscriptionStatus status;

      if (endDate.isAfter(networkNow)) {
        final bool isTrial = data['isTrial'] ?? false;
        status = isTrial ? SubscriptionStatus.trial : SubscriptionStatus.active;
      } else {
        status = SubscriptionStatus.expired;
      }

      // Update Caches (keyed by clinicId)
      _cachedStatusMap[clinicId] = status;
      _lastCheckTimeMap[clinicId] = DateTime.now();

      await prefs.setString('sub_status_$clinicId', status.name);
      await prefs.setString(
        'sub_last_check_$clinicId',
        _lastCheckTimeMap[clinicId]!.toIso8601String(),
      );

      return status;
    } catch (e) {
      debugPrint("Error checking subscription: $e");
      return SubscriptionStatus.offline;
    }
  }

  Future<int> getDaysRemaining(String clinicId) async {
    try {
      final DateTime? networkNow = await _fetchRealTime();
      if (networkNow == null) return 0;

      final doc = await _databases.getRow(
        databaseId: appwriteDatabaseId,
        tableId: 'clinics',
        rowId: clinicId,
      );

      final data = doc.data;
      if (!data.containsKey('subscriptionEndDate') ||
          data['subscriptionEndDate'] == null) {
        return 0;
      }

      final DateTime endDate = DateTime.parse(
        data['subscriptionEndDate'].toString(),
      ).toLocal();
      if (endDate.isBefore(networkNow)) return 0;

      return endDate.difference(networkNow).inDays;
    } catch (e) {
      return 0;
    }
  }

  // Admin Methods

  Future<void> extendSubscription(String clinicId, int days) async {
    final doc = await _databases.getRow(
      databaseId: appwriteDatabaseId,
      tableId: 'clinics',
      rowId: clinicId,
    );

    final data = doc.data;
    DateTime newEndDate;

    if (data.containsKey('subscriptionEndDate') &&
        data['subscriptionEndDate'] != null) {
      final currentEndDate = DateTime.parse(
        data['subscriptionEndDate'].toString(),
      ).toLocal();
      // If expired, add from today. If active, extend from current end date.
      if (currentEndDate.isBefore(DateTime.now())) {
        newEndDate = DateTime.now().add(Duration(days: days));
      } else {
        newEndDate = currentEndDate.add(Duration(days: days));
      }
    } else {
      // No existing date, start from today
      newEndDate = DateTime.now().add(Duration(days: days));
    }

    await _databases.updateRow(
      databaseId: appwriteDatabaseId,
      tableId: 'clinics',
      rowId: clinicId,
      data: {
        'subscriptionEndDate': newEndDate.toUtc().toIso8601String(),
        'isTrial': false, // Extending clears trial status
      },
    );
  }

  Future<void> updateSubscriptionDate(String clinicId, DateTime newDate) async {
    await _databases.updateRow(
      databaseId: appwriteDatabaseId,
      tableId: 'clinics',
      rowId: clinicId,
      data: {
        'subscriptionEndDate': newDate.toUtc().toIso8601String(),
        'isTrial': false,
      },
    );
  }

  Future<void> cancelSubscription(String clinicId) async {
    await _databases.updateRow(
      databaseId: appwriteDatabaseId,
      tableId: 'clinics',
      rowId: clinicId,
      data: {
        // Set to yesterday to ensure it's immediately expired
        'subscriptionEndDate': DateTime.now()
            .subtract(const Duration(days: 1))
            .toUtc()
            .toIso8601String(),
      },
    );
  }
}
