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
import '../../../core/services/hive_cache_service.dart';

// Stream of Appwrite Auth State (Session)
final authStateProvider = StreamProvider<models.User?>((ref) {
  final authRepo = ref.watch(authRepositoryProvider);
  return authRepo.authStateChanges;
});

// FutureProvider of Custom AppUser Data based on the logged in Auth ID
final currentUserProvider = FutureProvider<AppUser?>((ref) async {
  final authState = await ref.watch(authStateProvider.future);
  final authRepo = ref.watch(authRepositoryProvider);
  
  // Fetch user data once at startup (removed polling watch to prevent UI reset)
  if (authState != null) {
    return await authRepo.getUserData(authState.$id);
  }
  return null;
});

// StreamProvider of Clinic Data based on the currentUser's clinicId
final clinicStreamProvider = StreamProvider<ClinicGroup?>((ref) async* {
  final user = await ref.watch(currentUserProvider.future);
  if (user == null) {
    yield null;
    return;
  }
  
  final authRepo = ref.read(authRepositoryProvider);
  final cache = ref.read(hiveCacheServiceProvider);
  final cacheKey = 'clinic_${user.clinicId}';

  // Fetch clinic data once at startup

  // 1. Yield cached (Immediate)
  final cached = cache.getCachedValue(cacheKey);
  if (cached != null) {
    try {
      yield ClinicGroup.fromMap(Map<String, dynamic>.from(cached as Map), user.clinicId);
    } catch (_) {}
  }

  // 2. Fetch fresh
  try {
    final clinic = await authRepo.getClinicData(user.clinicId);
    if (clinic != null) {
      cache.cacheValue(cacheKey, clinic.toMap());
      yield clinic;
    }
  } catch (e) {
    // Ignore error on polling to keep showing the last known state
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

// StreamProvider for Approved Employees
final clinicEmployeesStreamProvider = StreamProvider.autoDispose<List<AppUser>>((ref) async* {
  final user = await ref.watch(currentUserProvider.future);
  if (user == null) {
    yield [];
    return;
  }
  
  final databases = ref.read(appwriteTablesDBProvider);
  final cache = ref.read(hiveCacheServiceProvider);
  final cacheKey = 'employees_${user.clinicId}';

  // Background polling trigger
  ref.watch(pollingTickProvider);

  // 1. Yield cached data immediately (no loading spinner)
  final cachedData = cache.getCachedValue(cacheKey);
  if (cachedData != null && cachedData is List) {
    try {
      final cachedUsers = cachedData.map((m) => AppUser.fromMap(Map<String, dynamic>.from(m as Map), '')).toList();
      if (cachedUsers.isNotEmpty) yield cachedUsers;
    } catch (_) {}
  }

  // 2. Fetch fresh from network
  try {
    final result = await databases.listRows(
      databaseId: appwriteDatabaseId,
      tableId: 'users',
      queries: [
        Query.equal('clinicId', user.clinicId),
      ],
    );
    
    final allUsers = result.rows.map((doc) => AppUser.fromMap(doc.data, doc.$id)).toList();
    
    // DATA PROTECTION: Mask sensitive fields if the viewer is NOT an admin
    final isAdmin = user.isAdmin;
    final processedUsers = allUsers.map((u) {
      if (isAdmin || u.id == user.id) return u;
      return u.copyWith(
        email: '***@***.***',
        phone: '*******',
      );
    }).toList();

    final approved = processedUsers.where((u) => u.isApproved).toList();
    
    // Update Cache
    cache.cacheValue(cacheKey, approved.map((u) => u.toMap()).toList());
    
    yield approved;
  } catch (e) {
    // Silently skip on polling failure to prevent flicker
  }
});

// StreamProvider for Pending Users
final pendingUsersStreamProvider = StreamProvider.autoDispose<List<AppUser>>((ref) async* {
  final user = await ref.watch(currentUserProvider.future);
  if (user == null) {
    yield [];
    return;
  }
  
  final databases = ref.read(appwriteTablesDBProvider);
  final cache = ref.read(hiveCacheServiceProvider);
  final cacheKey = 'pending_${user.clinicId}';

  ref.watch(pollingTickProvider);

  // 1. Yield cached
  final cachedData = cache.getCachedValue(cacheKey);
  if (cachedData != null && cachedData is List) {
    try {
      final cached = cachedData.map((m) => AppUser.fromMap(Map<String, dynamic>.from(m as Map), '')).toList();
      if (cached.isNotEmpty) yield cached;
    } catch (_) {}
  }

  // 2. Fetch
  try {
    final result = await databases.listRows(
      databaseId: appwriteDatabaseId,
      tableId: 'users',
      queries: [
        Query.equal('clinicId', user.clinicId),
        Query.equal('isApproved', false),
      ],
    );
    final users = result.rows.map((doc) => AppUser.fromMap(doc.data, doc.$id)).toList();
    
    // Update Cache
    cache.cacheValue(cacheKey, users.map((u) => u.toMap()).toList());
    
    yield users;
  } catch (e) {
    // Ignore
  }
});
