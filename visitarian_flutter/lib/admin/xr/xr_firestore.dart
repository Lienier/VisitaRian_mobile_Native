import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:visitarian_flutter/admin/xr/xr_models.dart';

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
    // Do not order by updatedAt here because older nodes may not have this
    // field yet and would be excluded from ordered queries.
    return _nodesCollection(tourId).snapshots();
  }

  String createNodeId(String tourId) {
    return _nodesCollection(tourId).doc().id;
  }

  Future<void> createNodeDraft({
    required String tourId,
    required String nodeId,
  }) async {
    final existing = await _nodesCollection(tourId).get();
    var maxOrder = -1;
    for (final doc in existing.docs) {
      final raw = doc.data()['order'];
      final value = raw is num ? raw.toInt() : null;
      if (value != null && value > maxOrder) {
        maxOrder = value;
      }
    }

    await _nodesCollection(tourId).doc(nodeId).set({
      'name': 'Untitled Node',
      'panoUrl': '',
      'hotspots': const <Map<String, dynamic>>[],
      'order': maxOrder + 1,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    await _tourCollection().doc(tourId).set({
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
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
      'order': FieldValue.increment(0),
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

  Future<void> reorderNodes({
    required String tourId,
    required List<String> orderedNodeIds,
  }) async {
    final batch = _db.batch();
    for (var i = 0; i < orderedNodeIds.length; i++) {
      final nodeId = orderedNodeIds[i];
      batch.set(_nodesCollection(tourId).doc(nodeId), {
        'order': i,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }

    batch.set(_tourCollection().doc(tourId), {
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    await batch.commit();
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
