import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

const Set<String> _adminRoleNames = <String>{
  'admin',
  'superadmin',
  'super_admin',
};

const Set<String> _superAdminRoleNames = <String>{'superadmin', 'super_admin'};

bool _matchesRole(dynamic value, Set<String> allowed) {
  if (value is! String) return false;
  return allowed.contains(value.trim().toLowerCase());
}

bool userDataHasAdminRole(Map<String, dynamic>? data) {
  if (data == null || data.isEmpty) return false;

  if (data['admin'] == true || data['isAdmin'] == true) {
    return true;
  }

  return _matchesRole(data['role'], _adminRoleNames);
}

bool userDataHasSuperAdminRole(Map<String, dynamic>? data) {
  if (data == null || data.isEmpty) return false;
  return _matchesRole(data['role'], _superAdminRoleNames);
}

class AccessSnapshot {
  final bool isAdmin;
  final bool isSuperAdmin;
  final String role;
  final String email;

  const AccessSnapshot({
    required this.isAdmin,
    required this.isSuperAdmin,
    required this.role,
    required this.email,
  });

  const AccessSnapshot.none()
    : isAdmin = false,
      isSuperAdmin = false,
      role = '',
      email = '';

  bool get hasManagedRole => role.trim().isNotEmpty;
}

String _normalizedClaimRole(Map<String, dynamic> claims) {
  final role = claims['role'];
  return role is String ? role.trim().toLowerCase() : '';
}

bool _claimsHaveSuperAdmin(Map<String, dynamic> claims) {
  return claims['super_admin'] == true ||
      _superAdminRoleNames.contains(_normalizedClaimRole(claims));
}

bool _claimsHaveAdmin(Map<String, dynamic> claims) {
  return _claimsHaveSuperAdmin(claims) ||
      claims['admin'] == true ||
      _adminRoleNames.contains(_normalizedClaimRole(claims));
}

Future<AccessSnapshot> getAccessSnapshot({
  String? uid,
  String? email,
  Map<String, dynamic>? userData,
  bool forceRefreshToken = false,
}) async {
  final currentUser = FirebaseAuth.instance.currentUser;
  final resolvedUid = (uid?.trim().isNotEmpty ?? false)
      ? uid!.trim()
      : currentUser?.uid ?? '';

  if (resolvedUid.isEmpty) {
    return const AccessSnapshot.none();
  }

  final normalizedEmail = (email ?? currentUser?.email ?? '')
      .trim()
      .toLowerCase();
  final claimsUser = currentUser != null && currentUser.uid == resolvedUid
      ? currentUser
      : null;

  if (claimsUser != null) {
    final tokenResult = await claimsUser.getIdTokenResult(forceRefreshToken);
    final claims = tokenResult.claims ?? const <String, dynamic>{};
    final claimRole = _normalizedClaimRole(claims);

    if (_claimsHaveSuperAdmin(claims)) {
      return AccessSnapshot(
        isAdmin: true,
        isSuperAdmin: true,
        role: claimRole.isEmpty ? 'super_admin' : claimRole,
        email: normalizedEmail,
      );
    }

    if (_claimsHaveAdmin(claims)) {
      return AccessSnapshot(
        isAdmin: true,
        isSuperAdmin: false,
        role: claimRole.isEmpty ? 'admin' : claimRole,
        email: normalizedEmail,
      );
    }

    if (claimRole.isNotEmpty) {
      return AccessSnapshot(
        isAdmin: false,
        isSuperAdmin: false,
        role: claimRole,
        email: normalizedEmail,
      );
    }
  }

  try {
    final db = FirebaseFirestore.instance;
    final adminDoc = await db.collection('admins').doc(resolvedUid).get();
    final resolvedUserData =
        userData ??
        (await db.collection('users').doc(resolvedUid).get()).data();
    final adminData = adminDoc.data();

    final isSuperAdmin =
        userDataHasSuperAdminRole(adminData) ||
        userDataHasSuperAdminRole(resolvedUserData);
    final isAdmin =
        isSuperAdmin ||
        userDataHasAdminRole(adminData) ||
        userDataHasAdminRole(resolvedUserData);
    final role = isSuperAdmin
        ? 'super_admin'
        : _matchesRole(adminData?['role'], _adminRoleNames)
        ? (adminData?['role'] ?? '').toString().trim().toLowerCase()
        : (resolvedUserData?['role'] ?? '').toString().trim().toLowerCase();

    return AccessSnapshot(
      isAdmin: isAdmin,
      isSuperAdmin: isSuperAdmin,
      role: role,
      email: normalizedEmail,
    );
  } on FirebaseException {
    return AccessSnapshot(
      isAdmin: false,
      isSuperAdmin: false,
      role: '',
      email: normalizedEmail,
    );
  }
}

Stream<bool> isAdminStream(String uid, {String? email}) {
  if (uid.trim().isEmpty) return Stream<bool>.value(false);
  return FirebaseFirestore.instance
      .collection('users')
      .doc(uid)
      .snapshots()
      .asyncMap(
        (userDoc) async => (await getAccessSnapshot(
          uid: uid,
          email: email,
          userData: userDoc.data(),
        )).isAdmin,
      );
}

Future<bool> isAdmin(
  String uid, {
  String? email,
  Map<String, dynamic>? userData,
}) async {
  final snapshot = await getAccessSnapshot(
    uid: uid,
    email: email,
    userData: userData,
  );
  return snapshot.isAdmin;
}
