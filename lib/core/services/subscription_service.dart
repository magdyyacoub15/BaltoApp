import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

enum SubscriptionStatus { active, trial, expired, offline }

class SubscriptionService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Caching variables
  SubscriptionStatus? _cachedStatus;
  DateTime? _lastCheckTime;
  static const Duration _cacheDuration = Duration(hours: 12);

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

    // 1. Return memory-cached status if valid
    if (!forceRefresh &&
        _cachedStatus != null &&
        _lastCheckTime != null &&
        DateTime.now().difference(_lastCheckTime!) < _cacheDuration) {
      return _cachedStatus!;
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

      // 3. Fetch from Firestore
      final doc = await _firestore.collection('clinics').doc(clinicId).get();
      if (!doc.exists) return SubscriptionStatus.expired;

      final data = doc.data()!;
      if (!data.containsKey('subscriptionEndDate') ||
          data['subscriptionEndDate'] == null) {
        return SubscriptionStatus.expired;
      }

      final DateTime endDate = (data['subscriptionEndDate'] as Timestamp)
          .toDate();
      SubscriptionStatus status;

      if (endDate.isAfter(networkNow)) {
        final bool isTrial = data['isTrial'] ?? false;
        status = isTrial ? SubscriptionStatus.trial : SubscriptionStatus.active;
      } else {
        status = SubscriptionStatus.expired;
      }

      // Update Caches
      _cachedStatus = status;
      _lastCheckTime = DateTime.now();

      await prefs.setString('sub_status_$clinicId', status.name);
      await prefs.setString(
        'sub_last_check_$clinicId',
        _lastCheckTime!.toIso8601String(),
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

      final doc = await _firestore.collection('clinics').doc(clinicId).get();
      if (!doc.exists || doc.data()?['subscriptionEndDate'] == null) return 0;

      final DateTime endDate = (doc.data()!['subscriptionEndDate'] as Timestamp)
          .toDate();
      if (endDate.isBefore(networkNow)) return 0;

      return endDate.difference(networkNow).inDays;
    } catch (e) {
      return 0;
    }
  }

  // Admin Methods

  Future<void> extendSubscription(String clinicId, int days) async {
    final docRef = _firestore.collection('clinics').doc(clinicId);

    await _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(docRef);
      if (!snapshot.exists) {
        throw Exception("Clinic not found");
      }

      final data = snapshot.data()!;
      DateTime newEndDate;

      if (data.containsKey('subscriptionEndDate') &&
          data['subscriptionEndDate'] != null) {
        final currentEndDate = (data['subscriptionEndDate'] as Timestamp)
            .toDate();
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

      transaction.update(docRef, {
        'subscriptionEndDate': Timestamp.fromDate(newEndDate),
        'isTrial': false, // Extending clears trial status
      });
    });
  }

  Future<void> updateSubscriptionDate(String clinicId, DateTime newDate) async {
    await _firestore.collection('clinics').doc(clinicId).update({
      'subscriptionEndDate': Timestamp.fromDate(newDate),
      'isTrial': false,
    });
  }

  Future<void> cancelSubscription(String clinicId) async {
    await _firestore.collection('clinics').doc(clinicId).update({
      // Set to yesterday to ensure it's immediately expired
      'subscriptionEndDate': Timestamp.fromDate(
        DateTime.now().subtract(const Duration(days: 1)),
      ),
    });
  }
}
