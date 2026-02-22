import 'package:cloud_firestore/cloud_firestore.dart';

Stream<bool> isAdminStream(String uid) {
  if (uid.trim().isEmpty) return Stream<bool>.value(false);
  return FirebaseFirestore.instance
      .collection('admins')
      .doc(uid)
      .snapshots()
      .map((doc) => doc.exists);
}

Future<bool> isAdmin(String uid) async {
  if (uid.trim().isEmpty) return false;
  final doc = await FirebaseFirestore.instance
      .collection('admins')
      .doc(uid)
      .get();
  return doc.exists;
}
