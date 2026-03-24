import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:appwrite/appwrite.dart';
// ignore_for_file: deprecated_member_use
import 'package:appwrite/models.dart' as models;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../domain/models/app_user.dart';
import '../domain/models/clinic_group.dart';
import '../domain/models/clinic_membership.dart';
import '../data/auth_repository.dart';
import '../../../core/services/appwrite_client.dart';
import '../../../core/services/polling_service.dart';

// Stream of Appwrite Auth State (Session)
final authStateProvider = StreamProvider<models.User?>((ref) {
  final authRepo = ref.watch(authRepositoryProvider);
  return authRepo.authStateChanges;
});

// FutureProvider of Custom AppUser Data based on the logged in Auth ID
final currentUserProvider = FutureProvider<AppUser?>((ref) async {
  final authState = await ref.watch(authStateProvider.future);
  final authRepo = ref.watch(authRepositoryProvider);
  if (authState != null) {
    return await authRepo.getUserData(authState.$id);
  }
  return null;
});

// StreamProvider of Clinic Data based on the currentUser's clinicId
final clinicStreamProvider = StreamProvider<ClinicGroup?>((ref) async* {
  final user = await ref.watch(currentUserProvider.future);
  final authRepo = ref.watch(authRepositoryProvider);
  if (user == null) {
    yield null;
    return;
  }

  // REFRESH TRIGGER: This causes the entire StreamProvider to re-run every 15 seconds
  // ensuring that visibilityThreshold (lastShiftReset) is updated on all devices.
  ref.watch(pollingTickProvider);

  try {
    final updatedClinic = await authRepo.getClinicData(user.clinicId);
    yield updatedClinic;
  } catch (e) {
    // Ignore network errors on background polling to keep showing the last known state
  }
});

// Provider for the visibility threshold (24 hours ago OR last manual reset)
final clinicVisibilityThresholdProvider = Provider<DateTime>((ref) {
  final clinic = ref.watch(clinicStreamProvider).value;
  final now = DateTime.now();
  final twentyFourHoursAgo = now.subtract(const Duration(hours: 24));

  if (clinic?.lastShiftReset != null) {
    return clinic!.lastShiftReset!.isAfter(twentyFourHoursAgo)
        ? clinic.lastShiftReset!
        : twentyFourHoursAgo;
  }
  return twentyFourHoursAgo;
});

// Helper check for Admins
final isAdminProvider = FutureProvider<bool>((ref) async {
  final user = await ref.watch(currentUserProvider.future);
  return user?.isAdmin ?? false;
});

// Provider to load all memberships for the currently logged-in user
final userMembershipsProvider =
    FutureProvider.autoDispose<List<ClinicMembership>>((ref) async {
      final user = await ref.watch(currentUserProvider.future);
      final authRepo = ref.watch(authRepositoryProvider);
      if (user != null) {
        return await authRepo.getUserMemberships(user.id);
      }
      return [];
    });

// FutureProvider of Admin User for the current clinic (The Doctor)
final clinicAdminProvider = FutureProvider<AppUser?>((ref) async {
  final user = await ref.watch(currentUserProvider.future);

  if (user != null) {
    final databases = ref.read(appwriteTablesDBProvider);

    try {
      final result = await databases.listRows(
        databaseId: appwriteDatabaseId,
        tableId: 'users',
        queries: [
          Query.equal('clinicId', user.clinicId),
          Query.equal('role', 'admin'),
          Query.limit(1),
        ],
      );
      if (result.rows.isNotEmpty) {
        final doc = result.rows.first;
        return AppUser.fromMap(doc.data, doc.$id);
      }
    } catch (e) {
      return null;
    }
  }
  return null;
});
