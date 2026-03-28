import 'package:cloud_firestore/cloud_firestore.dart';

const Set<String> _adminRoleNames = <String>{
  'admin',
  'superadmin',
  'super_admin',
};

bool userDataHasAdminRole(Map<String, dynamic>? data) {
  if (data == null || data.isEmpty) return false;

  if (data['admin'] == true || data['isAdmin'] == true) {
    return true;
  }

  final role = data['role'];
  if (role is String && _adminRoleNames.contains(role.trim().toLowerCase())) {
    return true;
  }

  return false;
}

Stream<bool> isAdminStream(String uid, {String? email}) {
  if (uid.trim().isEmpty) return Stream<bool>.value(false);
  return FirebaseFirestore.instance
      .collection('users')
      .doc(uid)
      .snapshots()
      .asyncMap((userDoc) => isAdmin(uid, email: email, userData: userDoc.data()));
}

Future<bool> isAdmin(
  String uid, {
  String? email,
  Map<String, dynamic>? userData,
}) async {
  if (uid.trim().isEmpty) return false;

  try {
    if (userDataHasAdminRole(userData)) {
      return true;
    }

    final db = FirebaseFirestore.instance;

    final adminDoc = await db.collection('admins').doc(uid).get();
    if (adminDoc.exists || userDataHasAdminRole(adminDoc.data())) {
      return true;
    }

    final userDoc = await db.collection('users').doc(uid).get();
    if (userDataHasAdminRole(userDoc.data())) {
      return true;
    }

    try {
      final byUid =
          await db.collection('admins').where('uid', isEqualTo: uid).limit(1).get();
      if (byUid.docs.isNotEmpty) {
        return true;
      }
    } on FirebaseException {
      // Keep auth flow usable when legacy collection queries are blocked.
    }

    final normalizedEmail = email?.trim().toLowerCase() ?? '';
    if (normalizedEmail.isEmpty) {
      return false;
    }

    try {
      final byEmail = await db
          .collection('admins')
          .where('email', isEqualTo: normalizedEmail)
          .limit(1)
          .get();
      return byEmail.docs.isNotEmpty;
    } on FirebaseException {
      return false;
    }
  } on FirebaseException {
    return false;
  }
}
