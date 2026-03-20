import 'package:appwrite/appwrite.dart';
// ignore_for_file: deprecated_member_use
import 'package:appwrite/models.dart' as models;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../domain/models/app_user.dart';
import '../domain/models/clinic_group.dart';
import '../domain/models/clinic_membership.dart';
import '../data/auth_repository.dart';
import '../../../core/services/appwrite_client.dart';

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

// FutureProvider of Clinic Data based on the currentUser's clinicId
final clinicStreamProvider = FutureProvider<ClinicGroup?>((ref) async {
  final user = await ref.watch(currentUserProvider.future);
  final authRepo = ref.watch(authRepositoryProvider);
  if (user != null) {
    return await authRepo.getClinicData(user.clinicId);
  }
  return null;
});

// Provider for the visibility threshold (24 hours ago OR last manual reset)
final clinicVisibilityThresholdProvider = FutureProvider<DateTime>((ref) async {
  final clinic = await ref.watch(clinicStreamProvider.future);
  final now = DateTime.now();
  final twentyFourHoursAgo = now.subtract(const Duration(hours: 24));

  if (clinic?.lastShiftReset != null) {
    // If reset happened more than 24 hours ago, it's irrelevant, use 24h as base
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
    final databases = ref.read(appwriteDatabasesProvider);

    try {
      final result = await databases.listDocuments(
        databaseId: appwriteDatabaseId,
        collectionId: 'users',
        queries: [
          Query.equal('clinicId', user.clinicId),
          Query.equal('role', 'admin'),
          Query.limit(1),
        ],
      );
      if (result.documents.isNotEmpty) {
        final doc = result.documents.first;
        return AppUser.fromMap(doc.data, doc.$id);
      }
    } catch (e) {
      return null;
    }
  }
  return null;
});
