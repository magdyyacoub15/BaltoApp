import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../domain/models/app_user.dart';
import '../domain/models/clinic_group.dart';
import '../domain/models/clinic_membership.dart';

final authRepositoryProvider = Provider((ref) => AuthRepository());

class AuthRepository {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Stream<User?> get authStateChanges => _auth.authStateChanges();

  // Get current AppUser data from Firestore
  Stream<AppUser?> getUserData(String uid) {
    return _firestore.collection('users').doc(uid).snapshots().map((doc) {
      if (doc.exists) {
        return AppUser.fromMap(doc.data()!, doc.id);
      }
      return null;
    });
  }

  // Get Clinic details
  Stream<ClinicGroup?> getClinicData(String clinicId) {
    return _firestore.collection('clinics').doc(clinicId).snapshots().map((
      doc,
    ) {
      if (doc.exists) {
        return ClinicGroup.fromMap(doc.data()!, doc.id);
      }
      return null;
    });
  }

  // Manual Shift Reset
  Future<void> resetShift(String clinicId) async {
    await _firestore.collection('clinics').doc(clinicId).update({
      'lastShiftReset': FieldValue.serverTimestamp(),
    });
  }

  Future<void> login(String email, String password) async {
    await _auth.signInWithEmailAndPassword(email: email, password: password);
  }

  Future<void> logOut() async {
    await _auth.signOut();
  }

  Future<void> resetPassword(String email) async {
    await _auth.sendPasswordResetEmail(email: email);
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
    final userCredential = await _auth.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );

    final uid = userCredential.user!.uid;

    // 2. Generate unique Clinic Code
    final clinicCode = _generateRandomCode(6);

    // 3. Create Clinic Document with 60-day Trial
    final trialEndDate = DateTime.now().add(const Duration(days: 60));
    final clinicRef = await _firestore.collection('clinics').add({
      'name': clinicName,
      'clinicCode': clinicCode,
      'createdAt': FieldValue.serverTimestamp(),
      'subscriptionEndDate': Timestamp.fromDate(trialEndDate),
      'isTrial': true,
    });

    // 4. Create User Document with Admin role
    final user = AppUser(
      id: uid,
      name: name,
      email: email,
      phone: phone,
      clinicId: clinicRef.id,
      role: 'admin',
      isApproved: true,
    );

    await _firestore.collection('users').doc(uid).set(user.toMap());

    // 5. Create Membership record for this clinic
    await ensureAdminMembership(uid, clinicRef.id);
  }

  // Join Existing Clinic via Code (Secretary)
  Future<void> signUpAsSecretary({
    required String name,
    required String phone,
    required String email,
    required String password,
    required String clinicCode,
  }) async {
    // 1. Verify Clinic Code exists before creating user
    final clinicsQuery = await _firestore
        .collection('clinics')
        .where('clinicCode', isEqualTo: clinicCode)
        .limit(1)
        .get();

    if (clinicsQuery.docs.isEmpty) {
      throw Exception('invalid_clinic_code');
    }

    final clinicId = clinicsQuery.docs.first.id;

    // 2. Create Auth User
    final userCredential = await _auth.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );
    final uid = userCredential.user!.uid;

    // 3. Create User Document with Secretary role
    final user = AppUser(
      id: uid,
      name: name,
      email: email,
      phone: phone,
      clinicId: clinicId,
      role: 'secretary', // Default to secretary for joiners
      isApproved: false,
    );

    await _firestore.collection('users').doc(uid).set(user.toMap());

    // 4. Create Pending Membership record for this clinic
    await _firestore.collection('memberships').add({
      'userId': uid,
      'clinicId': clinicId,
      'role': 'secretary',
      'status': 'pending',
      'joinedAt': FieldValue.serverTimestamp(),
    });
  }

  // --- Admin Approval Actions ---

  Future<void> approveUser(String uid) async {
    await _firestore.collection('users').doc(uid).update({'isApproved': true});
  }

  Future<void> rejectUser(String uid) async {
    // We delete the user document.
    // Note: This doesn't delete the Firebase Auth account,
    // but without a document, they will be effectively blocked or forced to re-register
    // depending on how we handle null getUserData.
    await _firestore.collection('users').doc(uid).delete();
  }

  // --- Clinic Management ---

  Future<void> updateClinicCode(String clinicId, String newCode) async {
    await _firestore.collection('clinics').doc(clinicId).update({
      'clinicCode': newCode,
    });
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

  /// Returns all memberships for [userId], enriched with clinic name.
  Future<List<ClinicMembership>> getUserMemberships(String userId) async {
    final snap = await _firestore
        .collection('memberships')
        .where('userId', isEqualTo: userId)
        .get();

    final memberships = snap.docs
        .map((d) => ClinicMembership.fromMap(d.data(), d.id))
        .toList();

    // Enrich with clinic names
    if (memberships.isNotEmpty) {
      final clinicIds = memberships.map((m) => m.clinicId).toSet().toList();
      final clinicsSnap = await _firestore
          .collection('clinics')
          .where(FieldPath.documentId, whereIn: clinicIds)
          .get();

      final nameMap = <String, String>{
        for (var d in clinicsSnap.docs) d.id: d.data()['name'] ?? '',
      };

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

  /// Switches the active clinic for [userId] to [clinicId].
  /// Fetches role from the membership document and updates the user doc.
  Future<void> switchClinic(String userId, String clinicId) async {
    // 1. Get membership to retrieve role & status
    final memberSnap = await _firestore
        .collection('memberships')
        .where('userId', isEqualTo: userId)
        .where('clinicId', isEqualTo: clinicId)
        .limit(1)
        .get();

    if (memberSnap.docs.isEmpty) {
      throw Exception('no_membership_found');
    }

    final memberData = memberSnap.docs.first.data();
    final status = memberData['status'] ?? 'approved';
    if (status == 'pending') {
      throw Exception('group_pending_admin_approval');
    }

    final role = memberData['role'] ?? 'secretary';

    // 2. Update user document
    await _firestore.collection('users').doc(userId).update({
      'clinicId': clinicId,
      'role': role,
      'isApproved': true,
    });
  }

  /// Joins a new clinic by [clinicCode] — creates a pending membership.
  /// Throws if code is invalid or user is already a member.
  Future<void> joinClinicByCode(String userId, String clinicCode) async {
    // 1. Find clinic by code
    final clinicsQuery = await _firestore
        .collection('clinics')
        .where('clinicCode', isEqualTo: clinicCode.toUpperCase())
        .limit(1)
        .get();

    if (clinicsQuery.docs.isEmpty) {
      throw Exception('invalid_clinic_code');
    }

    final clinicId = clinicsQuery.docs.first.id;

    // 2. Check if already a member
    final existing = await _firestore
        .collection('memberships')
        .where('userId', isEqualTo: userId)
        .where('clinicId', isEqualTo: clinicId)
        .limit(1)
        .get();

    if (existing.docs.isNotEmpty) {
      throw Exception('already_member_or_pending');
    }

    // 3. Create pending membership
    await _firestore.collection('memberships').add({
      'userId': userId,
      'clinicId': clinicId,
      'role': 'secretary',
      'status': 'pending',
      'joinedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Removes a membership document (leave a clinic).
  Future<void> leaveMembership(String membershipId) async {
    await _firestore.collection('memberships').doc(membershipId).delete();
  }

  /// Creates a new clinic for an existing user and sets it as active.
  Future<void> createClinicForExistingUser({
    required String userId,
    required String clinicName,
  }) async {
    // 1. Generate unique Clinic Code
    final clinicCode = generateRandomCode(6);

    // 2. Create Clinic Document with 60-day Trial
    final trialEndDate = DateTime.now().add(const Duration(days: 60));
    final clinicRef = await _firestore.collection('clinics').add({
      'name': clinicName,
      'clinicCode': clinicCode,
      'createdAt': FieldValue.serverTimestamp(),
      'subscriptionEndDate': Timestamp.fromDate(trialEndDate),
      'isTrial': true,
    });

    // 3. Create Membership record for this clinic as Admin
    await ensureAdminMembership(userId, clinicRef.id);

    // 4. Update User Document to set this as the active clinic
    await _firestore.collection('users').doc(userId).update({
      'clinicId': clinicRef.id,
      'role': 'admin',
      'isApproved': true,
    });
  }

  /// Creates an admin membership document. Called after signUpAsAdmin.
  Future<void> ensureAdminMembership(String userId, String clinicId) async {
    final existing = await _firestore
        .collection('memberships')
        .where('userId', isEqualTo: userId)
        .where('clinicId', isEqualTo: clinicId)
        .limit(1)
        .get();

    if (existing.docs.isEmpty) {
      await _firestore.collection('memberships').add({
        'userId': userId,
        'clinicId': clinicId,
        'role': 'admin',
        'status': 'approved',
        'joinedAt': FieldValue.serverTimestamp(),
      });
    }
  }

  /// Self-healing: Ensures that the user has a membership record for their primary clinicId.
  /// Used to fix data gaps during login or membership loading.
  Future<void> selfHealMembership(String userId, String primaryClinicId) async {
    if (primaryClinicId.isEmpty) return;

    final existing = await _firestore
        .collection('memberships')
        .where('userId', isEqualTo: userId)
        .where('clinicId', isEqualTo: primaryClinicId)
        .limit(1)
        .get();

    if (existing.docs.isEmpty) {
      final userDoc = await _firestore.collection('users').doc(userId).get();
      final role = userDoc.data()?['role'] ?? 'secretary';

      await _firestore.collection('memberships').add({
        'userId': userId,
        'clinicId': primaryClinicId,
        'role': role,
        'status': 'approved',
        'joinedAt': FieldValue.serverTimestamp(),
      });
    }
  }

  Future<void> updateClinic(ClinicGroup clinic) async {
    await _firestore
        .collection('clinics')
        .doc(clinic.id)
        .update(clinic.toMap());
  }
}
