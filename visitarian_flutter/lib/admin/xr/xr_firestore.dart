import 'package:cloud_firestore/cloud_firestore.dart';

import 'xr_models.dart';

class XrFirestore {
  final FirebaseFirestore _db;

  XrFirestore({FirebaseFirestore? firestore})
    : _db = firestore ?? FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> _tourCollection() {
    return _db.collection('tours');
  }

  CollectionReference<Map<String, dynamic>> _nodesCollection(String tourId) {
    return _tourCollection().doc(tourId).collection('nodes');
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> nodesStream(String tourId) {
    return _nodesCollection(
      tourId,
    ).orderBy('updatedAt', descending: true).snapshots();
  }

  String createNodeId(String tourId) {
    return _nodesCollection(tourId).doc().id;
  }

  Future<DocumentSnapshot<Map<String, dynamic>>> getNode({
    required String tourId,
    required String nodeId,
  }) {
    return _nodesCollection(tourId).doc(nodeId).get();
  }

  Future<void> upsertNode({
    required String tourId,
    required String nodeId,
    required String name,
    required String panoUrl,
    required List<XrHotspot> hotspots,
  }) async {
    await _nodesCollection(tourId).doc(nodeId).set({
      'name': name.trim(),
      'panoUrl': panoUrl.trim(),
      'hotspots': hotspots.map((e) => e.toMap()).toList(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    await _tourCollection().doc(tourId).set({
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> setStartNode({
    required String tourId,
    required String startNodeId,
  }) async {
    await _tourCollection().doc(tourId).set({
      'startNodeId': startNodeId,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<Map<String, dynamic>> buildTourJson(String tourId) async {
    final tourDoc = await _tourCollection().doc(tourId).get();
    final nodesSnapshot = await _nodesCollection(tourId).get();

    final nodes = nodesSnapshot.docs
        .map((doc) => {'id': doc.id, ...doc.data()})
        .toList();

    return {
      'tourId': tourId,
      'startNodeId': (tourDoc.data()?['startNodeId'] ?? '').toString(),
      'nodes': nodes,
    };
  }
}
