// ignore_for_file: deprecated_member_use
import 'dart:math';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:appwrite/appwrite.dart';
import 'package:appwrite/models.dart' as models;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/services/appwrite_client.dart';
import '../domain/models/app_user.dart';
import '../domain/models/clinic_group.dart';
import '../domain/models/clinic_membership.dart';

final authRepositoryProvider = Provider((ref) {
  final account = ref.watch(appwriteAccountProvider);
  final databases = ref.watch(appwriteDatabasesProvider);
  return AuthRepository(account, databases);
});

class AuthRepository {
  final Account _account;
  final Databases _databases;
  final _authStateController = StreamController<models.User?>.broadcast();

  AuthRepository(this._account, this._databases) {
    _initAuthState();
  }

  void _initAuthState() async {
    try {
      final user = await _account.get();
      if (!_authStateController.isClosed) _authStateController.add(user);
    } catch (_) {
      if (!_authStateController.isClosed) _authStateController.add(null);
    }
  }

  Stream<models.User?> get authStateChanges => _authStateController.stream;

  // Get current AppUser data
  Future<AppUser?> getUserData(String uid) async {
    try {
      final doc = await _databases.getDocument(
        databaseId: appwriteDatabaseId,
        collectionId: 'users',
        documentId: uid,
      );
      return AppUser.fromMap(doc.data, doc.$id);
    } catch (e) {
      return null;
    }
  }

  // Get Clinic details
  Future<ClinicGroup?> getClinicData(String clinicId) async {
    try {
      final doc = await _databases.getDocument(
        databaseId: appwriteDatabaseId,
        collectionId: 'clinics',
        documentId: clinicId,
      );
      return ClinicGroup.fromMap(doc.data, doc.$id);
    } catch (e) {
      return null;
    }
  }

  // Manual Shift Reset
  Future<void> resetShift(String clinicId) async {
    await _databases.updateDocument(
      databaseId: appwriteDatabaseId,
      collectionId: 'clinics',
      documentId: clinicId,
      data: {'lastShiftReset': DateTime.now().toIso8601String()},
    );
  }

  Future<void> login(String email, String password) async {
    await _account.createEmailPasswordSession(email: email, password: password);
    // Emit updated user after successful login
    try {
      final user = await _account.get();
      if (!_authStateController.isClosed) _authStateController.add(user);
    } catch (_) {
      if (!_authStateController.isClosed) _authStateController.add(null);
    }
  }

  Future<void> logOut() async {
    try {
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
    // 1. Create Auth User
    final user = await _account.create(
      userId: ID.unique(),
      email: email,
      password: password,
      name: name,
    );
    final uid = user.$id;

    // 2. Generate unique Clinic Code
    final clinicCode = _generateRandomCode(6);

    // 3. Create Clinic Document with 60-day Trial
    final trialEndDate = DateTime.now().add(const Duration(days: 60));
    final clinicDoc = await _databases.createDocument(
      databaseId: appwriteDatabaseId,
      collectionId: 'clinics',
      documentId: ID.unique(),
      data: {
        'name': clinicName,
        'clinicCode': clinicCode,
        'adminId': uid,
        'createdAt': DateTime.now().toIso8601String(),
        'subscriptionEndDate': trialEndDate.toIso8601String(),
        'isTrial': true,
      },
    );

    // 4. Create User Document with Admin role
    final appUser = AppUser(
      id: uid,
      name: name,
      email: email,
      phone: phone,
      clinicId: clinicDoc.$id,
      role: 'admin',
      isApproved: true,
    );

    await _databases.createDocument(
      databaseId: appwriteDatabaseId,
      collectionId: 'users',
      documentId: uid,
      data: appUser.toMap(),
    );

    // 5. Create Membership record for this clinic
    try {
      await ensureAdminMembership(uid, clinicDoc.$id);
    } catch (e) {
      debugPrint('⚠️ [SignUp] Membership step failed (non-fatal): $e');
    }

    // Automatically log in newly signed up user
    await login(email, password);
  }

  // Join Existing Clinic via Code (Secretary)
  Future<void> signUpAsSecretary({
    required String name,
    required String phone,
    required String email,
    required String password,
    required String clinicCode,
  }) async {
    // 1. Verify Clinic Code exists
    final clinicsQuery = await _databases.listDocuments(
      databaseId: appwriteDatabaseId,
      collectionId: 'clinics',
      queries: [Query.equal('clinicCode', clinicCode), Query.limit(1)],
    );

    if (clinicsQuery.documents.isEmpty) {
      throw Exception('invalid_clinic_code');
    }

    final clinicId = clinicsQuery.documents.first.$id;

    // 2. Create Auth User
    final user = await _account.create(
      userId: ID.unique(),
      email: email,
      password: password,
      name: name,
    );
    final uid = user.$id;

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

    await _databases.createDocument(
      databaseId: appwriteDatabaseId,
      collectionId: 'users',
      documentId: uid,
      data: appUser.toMap(),
    );

    // 4. Create Pending Membership record
    await _databases.createDocument(
      databaseId: appwriteDatabaseId,
      collectionId: 'memberships',
      documentId: ID.unique(),
      data: {
        'userId': uid,
        'clinicId': clinicId,
        'role': 'secretary',
        'status': 'pending',
        'joinedAt': DateTime.now().toIso8601String(),
      },
    );

    await login(email, password);
  }

  // --- Admin Approval Actions ---

  Future<void> approveUser(String uid) async {
    await _databases.updateDocument(
      databaseId: appwriteDatabaseId,
      collectionId: 'users',
      documentId: uid,
      data: {'isApproved': true},
    );
  }

  Future<void> rejectUser(String uid) async {
    await _databases.deleteDocument(
      databaseId: appwriteDatabaseId,
      collectionId: 'users',
      documentId: uid,
    );
  }

  // --- Clinic Management ---

  Future<void> updateClinicCode(String clinicId, String newCode) async {
    await _databases.updateDocument(
      databaseId: appwriteDatabaseId,
      collectionId: 'clinics',
      documentId: clinicId,
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
    final snap = await _databases.listDocuments(
      databaseId: appwriteDatabaseId,
      collectionId: 'memberships',
      queries: [Query.equal('userId', userId)],
    );

    final memberships = snap.documents
        .map((d) => ClinicMembership.fromMap(d.data, d.$id))
        .toList();

    // Enrich with clinic names
    if (memberships.isNotEmpty) {
      final clinicIds = memberships.map((m) => m.clinicId).toSet().toList();

      final Map<String, String> nameMap = {};

      // Unfortunately Appwrite limit in queries array values varies. A safer approach is to fetch all matching clinics or process them.
      // If clinicIds is less than 100, we can use Query.equal.
      if (clinicIds.isNotEmpty) {
        final clinicsSnap = await _databases.listDocuments(
          databaseId: appwriteDatabaseId,
          collectionId: 'clinics',
          queries: [
            Query.equal('\$id', clinicIds), // Search by document ID
          ],
        );
        for (var d in clinicsSnap.documents) {
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
    final memberSnap = await _databases.listDocuments(
      databaseId: appwriteDatabaseId,
      collectionId: 'memberships',
      queries: [
        Query.equal('userId', userId),
        Query.equal('clinicId', clinicId),
        Query.limit(1),
      ],
    );

    if (memberSnap.documents.isEmpty) {
      throw Exception('no_membership_found');
    }

    final memberData = memberSnap.documents.first.data;
    final status = memberData['status'] ?? 'approved';
    if (status == 'pending') {
      throw Exception('group_pending_admin_approval');
    }

    final role = memberData['role'] ?? 'secretary';

    // 2. Update user document
    await _databases.updateDocument(
      databaseId: appwriteDatabaseId,
      collectionId: 'users',
      documentId: userId,
      data: {'clinicId': clinicId, 'role': role, 'isApproved': true},
    );
  }

  Future<void> joinClinicByCode(String userId, String clinicCode) async {
    // 1. Find clinic by code
    final clinicsQuery = await _databases.listDocuments(
      databaseId: appwriteDatabaseId,
      collectionId: 'clinics',
      queries: [
        Query.equal('clinicCode', clinicCode.toUpperCase()),
        Query.limit(1),
      ],
    );

    if (clinicsQuery.documents.isEmpty) {
      throw Exception('invalid_clinic_code');
    }

    final clinicId = clinicsQuery.documents.first.$id;

    // 2. Check if already a member
    final existing = await _databases.listDocuments(
      databaseId: appwriteDatabaseId,
      collectionId: 'memberships',
      queries: [
        Query.equal('userId', userId),
        Query.equal('clinicId', clinicId),
        Query.limit(1),
      ],
    );

    if (existing.documents.isNotEmpty) {
      throw Exception('already_member_or_pending');
    }

    // 3. Create pending membership
    await _databases.createDocument(
      databaseId: appwriteDatabaseId,
      collectionId: 'memberships',
      documentId: ID.unique(),
      data: {
        'userId': userId,
        'clinicId': clinicId,
        'role': 'secretary',
        'status': 'pending',
        'joinedAt': DateTime.now().toIso8601String(),
      },
    );
  }

  Future<void> leaveMembership(String membershipId) async {
    await _databases.deleteDocument(
      databaseId: appwriteDatabaseId,
      collectionId: 'memberships',
      documentId: membershipId,
    );
  }

  Future<void> createClinicForExistingUser({
    required String userId,
    required String clinicName,
  }) async {
    // 1. Generate unique Clinic Code
    final clinicCode = generateRandomCode(6);

    // 2. Create Clinic Document with 60-day Trial
    final trialEndDate = DateTime.now().add(const Duration(days: 60));
    final clinicDoc = await _databases.createDocument(
      databaseId: appwriteDatabaseId,
      collectionId: 'clinics',
      documentId: ID.unique(),
      data: {
        'name': clinicName,
        'clinicCode': clinicCode,
        'adminId': userId,
        'createdAt': DateTime.now().toIso8601String(),
        'subscriptionEndDate': trialEndDate.toIso8601String(),
        'isTrial': true,
      },
    );

    // 3. Create Membership record for this clinic as Admin
    await ensureAdminMembership(userId, clinicDoc.$id);

    // 4. Update User Document to set this as the active clinic
    await _databases.updateDocument(
      databaseId: appwriteDatabaseId,
      collectionId: 'users',
      documentId: userId,
      data: {'clinicId': clinicDoc.$id, 'role': 'admin', 'isApproved': true},
    );
  }

  Future<void> ensureAdminMembership(String userId, String clinicId) async {
    final existing = await _databases.listDocuments(
      databaseId: appwriteDatabaseId,
      collectionId: 'memberships',
      queries: [
        Query.equal('userId', userId),
        Query.equal('clinicId', clinicId),
        Query.limit(1),
      ],
    );

    if (existing.documents.isEmpty) {
      await _databases.createDocument(
        databaseId: appwriteDatabaseId,
        collectionId: 'memberships',
        documentId: ID.unique(),
        data: {
          'userId': userId,
          'clinicId': clinicId,
          'role': 'admin',
          'status': 'approved',
          'joinedAt': DateTime.now().toIso8601String(),
        },
      );
    }
  }

  Future<void> selfHealMembership(String userId, String primaryClinicId) async {
    if (primaryClinicId.isEmpty) return;

    final existing = await _databases.listDocuments(
      databaseId: appwriteDatabaseId,
      collectionId: 'memberships',
      queries: [
        Query.equal('userId', userId),
        Query.equal('clinicId', primaryClinicId),
        Query.limit(1),
      ],
    );

    if (existing.documents.isEmpty) {
      try {
        final userDoc = await _databases.getDocument(
          databaseId: appwriteDatabaseId,
          collectionId: 'users',
          documentId: userId,
        );
        final role = userDoc.data['role'] ?? 'secretary';

        await _databases.createDocument(
          databaseId: appwriteDatabaseId,
          collectionId: 'memberships',
          documentId: ID.unique(),
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
    await _databases.updateDocument(
      databaseId: appwriteDatabaseId,
      collectionId: 'clinics',
      documentId: clinic.id,
      data: clinic.toMap(),
    );
  }
}
