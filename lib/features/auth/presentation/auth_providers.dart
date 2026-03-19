import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../domain/models/app_user.dart';
import '../domain/models/clinic_group.dart';
import '../domain/models/clinic_membership.dart';
import '../data/auth_repository.dart';

// Stream of Firebase Auth State
final authStateProvider = StreamProvider<User?>((ref) {
  final authRepo = ref.watch(authRepositoryProvider);
  return authRepo.authStateChanges;
});

// Stream of Custom AppUser Data based on the logged in Auth ID
final currentUserProvider = StreamProvider<AppUser?>((ref) {
  final authState = ref.watch(authStateProvider);
  final authRepo = ref.watch(authRepositoryProvider);

  return authState.when(
    data: (user) {
      if (user != null) {
        return authRepo.getUserData(user.uid);
      }
      return Stream.value(null);
    },
    loading: () => Stream.value(null),
    error: (_, __) => Stream.value(null),
  );
});

// Stream of Clinic Data based on the currentUser's clinicId
final clinicStreamProvider = StreamProvider<ClinicGroup?>((ref) {
  final userAsync = ref.watch(currentUserProvider);
  final authRepo = ref.watch(authRepositoryProvider);

  return userAsync.when(
    data: (user) {
      if (user != null) {
        return authRepo.getClinicData(user.clinicId);
      }
      return Stream.value(null);
    },
    loading: () => Stream.value(null),
    error: (_, __) => Stream.value(null),
  );
});

// Provider for the visibility threshold (24 hours ago OR last manual reset)
final clinicVisibilityThresholdProvider = Provider<DateTime>((ref) {
  final clinic = ref.watch(clinicStreamProvider).value;
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
final isAdminProvider = Provider<bool>((ref) {
  final userAsyncValue = ref.watch(currentUserProvider);

  return userAsyncValue.maybeWhen(
    data: (user) => user?.isAdmin ?? false,
    orElse: () => false,
  );
});

// Provider to load all memberships for the currently logged-in user
final userMembershipsProvider =
    FutureProvider.autoDispose<List<ClinicMembership>>((ref) async {
      final userAsync = ref.watch(currentUserProvider);
      final authRepo = ref.watch(authRepositoryProvider);

      return userAsync.when(
        data: (user) {
          if (user != null) {
            return authRepo.getUserMemberships(user.id);
          }
          return Future.value([]);
        },
        loading: () => Future.value([]),
        error: (_, __) => Future.value([]),
      );
    });

// Stream of Admin User for the current clinic (The Doctor)
final clinicAdminProvider = StreamProvider<AppUser?>((ref) {
  final userAsync = ref.watch(currentUserProvider);

  return userAsync.when(
    data: (user) {
      if (user != null) {
        return FirebaseFirestore.instance
            .collection('users')
            .where('clinicId', isEqualTo: user.clinicId)
            .where('role', isEqualTo: 'admin')
            .limit(1)
            .snapshots()
            .map(
              (snap) => snap.docs.isNotEmpty
                  ? AppUser.fromMap(snap.docs.first.data(), snap.docs.first.id)
                  : null,
            );
      }
      return Stream.value(null);
    },
    loading: () => Stream.value(null),
    error: (_, __) => Stream.value(null),
  );
});
