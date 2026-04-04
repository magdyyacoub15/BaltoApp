// ignore_for_file: deprecated_member_use
import 'dart:math';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:appwrite/appwrite.dart';
import 'package:appwrite/models.dart' as models;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/services/appwrite_client.dart';
import '../../../core/services/hive_cache_service.dart';
import '../domain/models/app_user.dart';
import '../domain/models/clinic_group.dart';
import '../domain/models/clinic_membership.dart';

final authRepositoryProvider = Provider((ref) {
  final account = ref.watch(appwriteAccountProvider);
  final databases = ref.watch(appwriteTablesDBProvider);
  final cache = ref.watch(hiveCacheServiceProvider);
  return AuthRepository(account, databases, cache);
});

class AuthRepository {
  final Account _account;
  final TablesDB _databases;
  final HiveCacheService _cache;
  final _authStateController = StreamController<models.User?>.broadcast();

  AuthRepository(this._account, this._databases, this._cache) {
    _initAuthState();
  }

  static const String _kCachedUserKey = 'cached_user_data';

  void _initAuthState() async {
    debugPrint('🔄 [Auth] _initAuthState() — checking current session');
    try {
      final user = await _account.get();
      debugPrint('✅ [Auth] Session found — userId=${user.$id}, email=${user.email}');
      
      // Cache this user for offline access
      await _cacheUser(user);
      
      if (!_authStateController.isClosed) _authStateController.add(user);
    } catch (e) {
      debugPrint('ℹ️ [Auth] Session check failed/missing: $e');
      
      // If it's a network error, try to load from cache
      if (e.toString().contains('Network') || e.toString().contains('SocketException') || e.toString().contains('Failed host lookup')) {
        final cachedUser = await _loadCachedUser();
        if (cachedUser != null) {
          debugPrint('🌐 [Auth] Offline mode: loading cached user — email=${cachedUser.email}');
          if (!_authStateController.isClosed) _authStateController.add(cachedUser);
          return;
        }
      }
      
      if (!_authStateController.isClosed) _authStateController.add(null);
    }
  }

  Future<void> _cacheUser(models.User user) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kCachedUserKey, json.encode(user.toMap()));
    } catch (e) {
      debugPrint('⚠️ [Auth] Error caching user: $e');
    }
  }

  Future<models.User?> _loadCachedUser() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kCachedUserKey);
      if (raw == null) return null;
      final map = json.decode(raw) as Map<String, dynamic>;
      
      // Use the built-in fromMap factory if available (Appwrite 12+)
      // Otherwise, the cached data is just for Auth state, we only need basic fields
      return models.User.fromMap(map);
    } catch (e) {
      debugPrint('⚠️ [Auth] Error loading cached user: $e');
      return null;
    }
  }

  Stream<models.User?> get authStateChanges => _authStateController.stream;

  // Get current AppUser data
  Future<AppUser?> getUserData(String uid) async {
    try {
      final doc = await _databases.getRow(
        databaseId: appwriteDatabaseId,
        tableId: 'users',
        rowId: uid,
      );
      final user = AppUser.fromMap(doc.data, doc.$id);
      
      // Cache for offline
      _cache.cacheValue('user_$uid', user.toMap());
      
      return user;
    } on AppwriteException catch (e) {
      // CRITICAL: If the document is NOT found (404), it means the user was removed/deleted.
      // We must clear the cache and return null to trigger immediate logout/redirect.
      if (e.code == 404) {
        debugPrint('🚫 [Auth] getUserData — User document deleted (404). Clearing cache.');
        _cache.removeCachedValue('user_$uid');
        return null;
      }
      
      debugPrint('ℹ️ [Auth] getUserData failed (AppwriteException ${e.code}): $e');
      return _tryGetCachedUser(uid);
    } catch (e) {
      debugPrint('ℹ️ [Auth] getUserData failed (General): $e');
      return _tryGetCachedUser(uid);
    }
  }

  AppUser? _tryGetCachedUser(String uid) {
    final cached = _cache.getCachedValue('user_$uid');
    if (cached != null) {
      return AppUser.fromMap(cached, uid);
    }
    return null;
  }

  // Get Clinic details
  Future<ClinicGroup?> getClinicData(String clinicId) async {
    try {
      final doc = await _databases.getRow(
        databaseId: appwriteDatabaseId,
        tableId: 'clinics',
        rowId: clinicId,
      );
      final clinic = ClinicGroup.fromMap(doc.data, doc.$id);
      
      // Cache for offline
      _cache.cacheValue('clinic_$clinicId', clinic.toMap());
      
      return clinic;
    } catch (e) {
      debugPrint('ℹ️ [Auth] getClinicData failed, checking cache: $e');
      final cached = _cache.getCachedValue('clinic_$clinicId');
      if (cached != null) {
        return ClinicGroup.fromMap(cached, clinicId);
      }
      return null;
    }
  }

  // Manual Shift Reset
  Future<void> resetShift(String clinicId) async {
    final newResetTime = DateTime.now().toUtc();
    final newResetStr = newResetTime.toIso8601String();
    debugPrint('▶ [Tracer] resetShift() — clinicId=$clinicId, newTime=$newResetStr');
    
    // 1. Update Appwrite
    await _databases.updateRow(
      databaseId: appwriteDatabaseId,
      tableId: 'clinics',
      rowId: clinicId,
      data: {'lastShiftReset': newResetStr},
    );

    // 2. Update Local Cache IMMEDIATELY so StreamProvider picks it up
    final cacheKey = 'clinic_$clinicId';
    final cached = _cache.getCachedValue(cacheKey);
    if (cached != null) {
      final updatedMap = Map<String, dynamic>.from(cached as Map);
      updatedMap['lastShiftReset'] = newResetStr;
      _cache.cacheValue(cacheKey, updatedMap);
      debugPrint('✅ [Tracer] resetShift() — local cache updated');
    }
    
    debugPrint('✅ [Tracer] resetShift() — update complete');
  }

  Future<void> login(String email, String password) async {
    debugPrint('▶ [Auth] login() — email=$email');
    // Delete any existing session first to avoid user_session_already_exists error
    try {
      await _account.deleteSession(sessionId: 'current');
      debugPrint('ℹ️ [Auth] login — cleared existing session');
    } catch (_) {
      // No active session, that's fine
    }
    try {
      await _account.createEmailPasswordSession(email: email, password: password);
      debugPrint('✅ [Auth] createEmailPasswordSession succeeded');
    } catch (e) {
      debugPrint('❌ [Auth] login createEmailPasswordSession failed: $e');
      rethrow;
    }
    // Emit updated user after successful login
    try {
      final user = await _account.get();
      debugPrint('✅ [Auth] login — got user: ${user.$id}');
      if (!_authStateController.isClosed) _authStateController.add(user);
    } catch (e) {
      debugPrint('⚠️ [Auth] login — could not get user after session: $e');
      if (!_authStateController.isClosed) _authStateController.add(null);
    }
  }

  Future<void> logOut() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_kCachedUserKey);
      await _account.deleteSession(sessionId: 'current');
    } catch (_) {}
    if (!_authStateController.isClosed) _authStateController.add(null);
  }

  Future<void> resetPassword(String email) async {
    // Appwrite requires a callback URL for password recovery
    await _account.createRecovery(
      email: email,
      url: 'https://balto.pro/reset-password',
    );
  }

  // Create new Clinic (Admin)
  Future<void> signUpAsAdmin({
    required String name,
    required String phone,
    required String email,
    required String password,
    required String clinicName,
  }) async {
    debugPrint('▶ [Auth] signUpAsAdmin() — email=$email, clinicName=$clinicName');

    // 1. Create Auth User
    late final String uid;
    try {
      final user = await _account.create(
        userId: ID.unique(),
        email: email,
        password: password,
        name: name,
      );
      uid = user.$id;
      debugPrint('✅ [Auth] signUpAsAdmin — auth user created: uid=$uid');
    } catch (e) {
      debugPrint('❌ [Auth] signUpAsAdmin — account.create failed: $e');
      rethrow;
    }

    // 2. Generate unique Clinic Code
    final clinicCode = _generateRandomCode(6);
    debugPrint('🔑 [Auth] signUpAsAdmin — generated clinicCode=$clinicCode');

    // 3. Create Clinic Document with 60-day Trial
    final trialEndDate = DateTime.now().toUtc().add(const Duration(days: 60));
    late final String clinicDocId;
    try {
      // 3a. Generate a unique clinic ID (no Appwrite Team needed — app uses its own memberships table)
      clinicDocId = ID.unique();
      debugPrint('🔑 [Auth] signUpAsAdmin — generated clinicDocId=$clinicDocId');

      await _databases.createRow(
        databaseId: appwriteDatabaseId,
        tableId: 'clinics',
        rowId: clinicDocId,
        data: {
          'name': clinicName,
          'clinicCode': clinicCode,
          'adminId': uid,
          'createdAt': DateTime.now().toUtc().toIso8601String(),
          'subscriptionEndDate': trialEndDate.toIso8601String(),
          'isTrial': true,
        },
      );
      debugPrint('✅ [Auth] signUpAsAdmin — clinic document created: clinicId=$clinicDocId');
    } catch (e) {
      debugPrint('❌ [Auth] signUpAsAdmin — create clinic/team failed: $e');
      rethrow;
    }

    // 4. Create User Document with Admin role
    final appUser = AppUser(
      id: uid,
      name: name,
      email: email,
      phone: phone,
      clinicId: clinicDocId,
      role: 'admin',
      isApproved: true,
    );
    try {
      await _databases.createRow(
        databaseId: appwriteDatabaseId,
        tableId: 'users',
        rowId: uid,
        data: appUser.toMap(),
      );
      debugPrint('✅ [Auth] signUpAsAdmin — user document created in DB');
    } catch (e) {
      debugPrint('❌ [Auth] signUpAsAdmin — create user document failed: $e');
      rethrow;
    }

    // 5. Create Membership record for this clinic
    try {
      await ensureAdminMembership(uid, clinicDocId);
      debugPrint('✅ [Auth] signUpAsAdmin — membership created');
    } catch (e) {
      debugPrint('⚠️ [Auth] signUpAsAdmin — membership step failed (non-fatal): $e');
    }

    // Automatically log in newly signed up user
    debugPrint('▶ [Auth] signUpAsAdmin — auto-login');
    await login(email, password);
    debugPrint('🎉 [Auth] signUpAsAdmin() — completed successfully');
  }

  // Join Existing Clinic via Code (Secretary)
  Future<void> signUpAsSecretary({
    required String name,
    required String phone,
    required String email,
    required String password,
    required String clinicCode,
  }) async {
    debugPrint('▶ [Auth] signUpAsSecretary() — email=$email, clinicCode=$clinicCode');

    // 1. Verify Clinic Code exists
    late final String clinicId;
    try {
      final clinicsQuery = await _databases.listRows(
        databaseId: appwriteDatabaseId,
        tableId: 'clinics',
        queries: [Query.equal('clinicCode', clinicCode), Query.limit(1)],
      );
      if (clinicsQuery.rows.isEmpty) {
        debugPrint('❌ [Auth] signUpAsSecretary — invalid clinic code: $clinicCode');
        throw Exception('invalid_clinic_code');
      }
      clinicId = clinicsQuery.rows.first.$id;
      debugPrint('✅ [Auth] signUpAsSecretary — clinic found: clinicId=$clinicId');
    } catch (e) {
      debugPrint('❌ [Auth] signUpAsSecretary — clinic lookup failed: $e');
      rethrow;
    }

    // 2. Create Auth User
    late final String uid;
    try {
      final user = await _account.create(
        userId: ID.unique(),
        email: email,
        password: password,
        name: name,
      );
      uid = user.$id;
      debugPrint('✅ [Auth] signUpAsSecretary — auth user created: uid=$uid');
    } catch (e) {
      debugPrint('❌ [Auth] signUpAsSecretary — account.create failed: $e');
      rethrow;
    }

    // 3. Create User Document with Secretary role
    final appUser = AppUser(
      id: uid,
      name: name,
      email: email,
      phone: phone,
      clinicId: clinicId,
      role: 'secretary',
      isApproved: false,
    );
    try {
      await _databases.createRow(
        databaseId: appwriteDatabaseId,
        tableId: 'users',
        rowId: uid,
        data: appUser.toMap(),
      );
      debugPrint('✅ [Auth] signUpAsSecretary — user document created in DB');
    } catch (e) {
      debugPrint('❌ [Auth] signUpAsSecretary — create user document failed: $e');
      rethrow;
    }

    // 4. Create Pending Membership record
    try {
      await _databases.createRow(
        databaseId: appwriteDatabaseId,
        tableId: 'memberships',
        rowId: ID.unique(),
        data: {
          'userId': uid,
          'clinicId': clinicId,
          'role': 'secretary',
          'status': 'pending',
          'joinedAt': DateTime.now().toUtc().toIso8601String(),
        },
      );
      debugPrint('✅ [Auth] signUpAsSecretary — pending membership created');
    } catch (e) {
      debugPrint('❌ [Auth] signUpAsSecretary — create membership failed: $e');
      rethrow;
    }

    debugPrint('▶ [Auth] signUpAsSecretary — auto-login');
    await login(email, password);
    debugPrint('🎉 [Auth] signUpAsSecretary() — completed successfully');
  }

  // --- Admin Approval Actions ---

  Future<void> approveUser(String uid) async {
    await _databases.updateRow(
      databaseId: appwriteDatabaseId,
      tableId: 'users',
      rowId: uid,
      data: {'isApproved': true},
    );
  }

  Future<void> rejectUser(String uid) async {
    // 1. Get user data to know clinicId for team removal
    final user = await getUserData(uid);
    
    // 2. Delete user document
    try {
      await _databases.deleteRow(
        databaseId: appwriteDatabaseId,
        tableId: 'users',
        rowId: uid,
      );
    } catch (e) {
      debugPrint('Error deleting user doc: $e');
    }

    // 3. Note: Removal from team requires membershipId in Appwrite Client SDK.
    if (user != null) {
      debugPrint('👥 [Auth] rejectUser — Note: Removal from team necessitates manual cleanup or server-side function if membershipId is not cached.');
    }
  }

  Future<void> removeUserFromClinic(String uid, String clinicId) async {
    await rejectUser(uid);
  }

  // --- Clinic Management ---

  Future<void> updateClinicCode(String clinicId, String newCode) async {
    await _databases.updateRow(
      databaseId: appwriteDatabaseId,
      tableId: 'clinics',
      rowId: clinicId,
      data: {'clinicCode': newCode},
    );
  }

  String generateRandomCode(int length) {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final rnd = Random();
    return String.fromCharCodes(
      Iterable.generate(
        length,
        (_) => chars.codeUnitAt(rnd.nextInt(chars.length)),
      ),
    );
  }

  String _generateRandomCode(int length) => generateRandomCode(length);

  // ─── Groups / Multi-Clinic Membership System ───────────────────────────────

  Future<List<ClinicMembership>> getUserMemberships(String userId) async {
    final snap = await _databases.listRows(
      databaseId: appwriteDatabaseId,
      tableId: 'memberships',
      queries: [Query.equal('userId', userId)],
    );

    final memberships = snap.rows
        .map((d) => ClinicMembership.fromMap(d.data, d.$id))
        .toList();

    // Enrich with clinic names
    if (memberships.isNotEmpty) {
      final clinicIds = memberships.map((m) => m.clinicId).toSet().toList();

      final Map<String, String> nameMap = {};

      // Unfortunately Appwrite limit in queries array values varies. A safer approach is to fetch all matching clinics or process them.
      // If clinicIds is less than 100, we can use Query.equal.
      if (clinicIds.isNotEmpty) {
        final clinicsSnap = await _databases.listRows(
          databaseId: appwriteDatabaseId,
          tableId: 'clinics',
          queries: [
            Query.equal('\$id', clinicIds), // Search by document ID
          ],
        );
        for (var d in clinicsSnap.rows) {
          nameMap[d.$id] = d.data['name'] ?? '';
        }
      }

      return memberships
          .map(
            (m) => ClinicMembership(
              id: m.id,
              userId: m.userId,
              clinicId: m.clinicId,
              clinicName: nameMap[m.clinicId] ?? m.clinicId,
              role: m.role,
              status: m.status,
              joinedAt: m.joinedAt,
            ),
          )
          .toList();
    }
    return memberships;
  }

  Future<void> switchClinic(String userId, String clinicId) async {
    // 1. Get membership to retrieve role & status
    final memberSnap = await _databases.listRows(
      databaseId: appwriteDatabaseId,
      tableId: 'memberships',
      queries: [
        Query.equal('userId', userId),
        Query.equal('clinicId', clinicId),
        Query.limit(1),
      ],
    );

    if (memberSnap.rows.isEmpty) {
      throw Exception('no_membership_found');
    }

    final memberData = memberSnap.rows.first.data;
    final status = memberData['status'] ?? 'approved';
    if (status == 'pending') {
      throw Exception('group_pending_admin_approval');
    }

    final role = memberData['role'] ?? 'secretary';

    // 2. Update user document
    await _databases.updateRow(
      databaseId: appwriteDatabaseId,
      tableId: 'users',
      rowId: userId,
      data: {'clinicId': clinicId, 'role': role, 'isApproved': true},
    );
  }

  Future<void> joinClinicByCode(String userId, String clinicCode) async {
    debugPrint('▶ [Auth] joinClinicByCode() — userId=$userId, code=$clinicCode');

    // 1. Find clinic by code
    late final String clinicId;
    try {
      final clinicsQuery = await _databases.listRows(
        databaseId: appwriteDatabaseId,
        tableId: 'clinics',
        queries: [
          Query.equal('clinicCode', clinicCode.toUpperCase()),
          Query.limit(1),
        ],
      );
      if (clinicsQuery.rows.isEmpty) {
        debugPrint('❌ [Auth] joinClinicByCode — invalid code: $clinicCode');
        throw Exception('invalid_clinic_code');
      }
      clinicId = clinicsQuery.rows.first.$id;
      debugPrint('✅ [Auth] joinClinicByCode — clinic found: clinicId=$clinicId');
    } catch (e) {
      debugPrint('❌ [Auth] joinClinicByCode — clinic lookup failed: $e');
      rethrow;
    }

    // 2. Check if already a member
    try {
      final existing = await _databases.listRows(
        databaseId: appwriteDatabaseId,
        tableId: 'memberships',
        queries: [
          Query.equal('userId', userId),
          Query.equal('clinicId', clinicId),
          Query.limit(1),
        ],
      );
      if (existing.rows.isNotEmpty) {
        debugPrint('⚠️ [Auth] joinClinicByCode — already member or pending for clinicId=$clinicId');
        throw Exception('already_member_or_pending');
      }
      debugPrint('✅ [Auth] joinClinicByCode — no existing membership, proceeding');
    } catch (e) {
      debugPrint('❌ [Auth] joinClinicByCode — membership check failed: $e');
      rethrow;
    }

    // 3. Create pending membership
    try {
      await _databases.createRow(
        databaseId: appwriteDatabaseId,
        tableId: 'memberships',
        rowId: ID.unique(),
        data: {
          'userId': userId,
          'clinicId': clinicId,
          'role': 'secretary',
          'status': 'pending',
          'joinedAt': DateTime.now().toIso8601String(),
        },
      );
      debugPrint('🎉 [Auth] joinClinicByCode() — pending membership created successfully');
    } catch (e) {
      debugPrint('❌ [Auth] joinClinicByCode — create membership failed: $e');
      rethrow;
    }
  }

  Future<void> leaveMembership(String membershipId) async {
    await _databases.deleteRow(
      databaseId: appwriteDatabaseId,
      tableId: 'memberships',
      rowId: membershipId,
    );
  }

  Future<void> createClinicForExistingUser({
    required String userId,
    required String adminEmail,
    required String clinicName,
  }) async {
    // 1. Generate unique Clinic Code
    final clinicCode = generateRandomCode(6);

    // 2. Create Clinic Document with 60-day Trial
    final trialEndDate = DateTime.now().toUtc().add(const Duration(days: 60));
    final clinicDoc = await _databases.createRow(
      databaseId: appwriteDatabaseId,
      tableId: 'clinics',
      rowId: ID.unique(),
      data: {
        'name': clinicName,
        'clinicCode': clinicCode,
        'adminId': userId,
        'createdAt': DateTime.now().toUtc().toIso8601String(),
        'subscriptionEndDate': trialEndDate.toUtc().toIso8601String(),
        'isTrial': true,
      },
    );

    // 3. Create Membership record for this clinic as Admin
    await ensureAdminMembership(userId, clinicDoc.$id);

    // 4. Update User Document to set this as the active clinic
    await _databases.updateRow(
      databaseId: appwriteDatabaseId,
      tableId: 'users',
      rowId: userId,
      data: {'clinicId': clinicDoc.$id, 'role': 'admin', 'isApproved': true},
    );
  }

  Future<void> ensureAdminMembership(String userId, String clinicId) async {
    final existing = await _databases.listRows(
      databaseId: appwriteDatabaseId,
      tableId: 'memberships',
      queries: [
        Query.equal('userId', userId),
        Query.equal('clinicId', clinicId),
        Query.limit(1),
      ],
    );

    if (existing.rows.isEmpty) {
      await _databases.createRow(
        databaseId: appwriteDatabaseId,
        tableId: 'memberships',
        rowId: ID.unique(),
        data: {
          'userId': userId,
          'clinicId': clinicId,
          'role': 'admin',
          'status': 'approved',
          'joinedAt': DateTime.now().toUtc().toIso8601String(),
        },
      );
    }
  }

  Future<void> selfHealMembership(String userId, String primaryClinicId) async {
    if (primaryClinicId.isEmpty) return;

    final existing = await _databases.listRows(
      databaseId: appwriteDatabaseId,
      tableId: 'memberships',
      queries: [
        Query.equal('userId', userId),
        Query.equal('clinicId', primaryClinicId),
        Query.limit(1),
      ],
    );

    if (existing.rows.isEmpty) {
      try {
        final userDoc = await _databases.getRow(
          databaseId: appwriteDatabaseId,
          tableId: 'users',
          rowId: userId,
        );
        final role = userDoc.data['role'] ?? 'secretary';

        await _databases.createRow(
          databaseId: appwriteDatabaseId,
          tableId: 'memberships',
          rowId: ID.unique(),
          data: {
            'userId': userId,
            'clinicId': primaryClinicId,
            'role': role,
            'status': 'approved',
            'joinedAt': DateTime.now().toIso8601String(),
          },
        );
      } catch (e) {
        // Ignore
      }
    }
  }

  Future<void> updateClinic(ClinicGroup clinic) async {
    await _databases.updateRow(
      databaseId: appwriteDatabaseId,
      tableId: 'clinics',
      rowId: clinic.id,
      data: clinic.toMap(),
    );
  }
}
