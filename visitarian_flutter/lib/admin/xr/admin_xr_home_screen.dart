import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'admin_access.dart';
import 'tour_nodes_screen.dart';
import '../../services/auth_service.dart';

class AdminXrHomeScreen extends StatefulWidget {
  const AdminXrHomeScreen({super.key});

  @override
  State<AdminXrHomeScreen> createState() => _AdminXrHomeScreenState();
}

class _AdminXrHomeScreenState extends State<AdminXrHomeScreen> {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  bool _isCreatingTour = false;
  bool _isCreatingPlace = false;
  bool _isSigningOut = false;

  final AuthService _authService = AuthService();

  Future<void> _createTourForPlace(String placeId) async {
    if (_isCreatingTour) return;

    setState(() {
      _isCreatingTour = true;
    });

    try {
      final tourRef = _db.collection('tours').doc();
      final tourId = tourRef.id;

      await tourRef.set({
        'placeId': placeId,
        'startNodeId': '',
        'updatedAt': FieldValue.serverTimestamp(),
      });

      await _db.collection('places').doc(placeId).set({
        'tourId': tourId,
      }, SetOptions(merge: true));

      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Tour created for place.')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to create tour: $e')));
    } finally {
      if (mounted) {
        setState(() {
          _isCreatingTour = false;
        });
      }
    }
  }

  Future<void> _showAddPlaceDialog() async {
    if (_isCreatingPlace) return;

    final formKey = GlobalKey<FormState>();
    final titleController = TextEditingController();
    final locationController = TextEditingController();
    final descriptionController = TextEditingController();
    final imageUrlController = TextEditingController();

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Add New Place'),
          content: SizedBox(
            width: 520,
            child: Form(
              key: formKey,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextFormField(
                      controller: titleController,
                      decoration: const InputDecoration(labelText: 'Title'),
                      validator: (v) => (v == null || v.trim().isEmpty)
                          ? 'Title is required'
                          : null,
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: locationController,
                      decoration: const InputDecoration(labelText: 'Location'),
                      validator: (v) => (v == null || v.trim().isEmpty)
                          ? 'Location is required'
                          : null,
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: imageUrlController,
                      decoration: const InputDecoration(labelText: 'Image URL'),
                      validator: (v) => (v == null || v.trim().isEmpty)
                          ? 'Image URL is required'
                          : null,
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: descriptionController,
                      minLines: 3,
                      maxLines: 5,
                      decoration: const InputDecoration(
                        labelText: 'Description',
                      ),
                      validator: (v) => (v == null || v.trim().isEmpty)
                          ? 'Description is required'
                          : null,
                    ),
                  ],
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton.icon(
              onPressed: () async {
                if (_isCreatingPlace) return;
                final messenger = ScaffoldMessenger.of(context);
                if (!(formKey.currentState?.validate() ?? false)) return;

                setState(() {
                  _isCreatingPlace = true;
                });

                try {
                  final placeRef = _db.collection('places').doc();
                  final tourRef = _db.collection('tours').doc();

                  await tourRef.set({
                    'placeId': placeRef.id,
                    'startNodeId': '',
                    'updatedAt': FieldValue.serverTimestamp(),
                  });

                  await placeRef.set({
                    'title': titleController.text.trim(),
                    'location': locationController.text.trim(),
                    'description': descriptionController.text.trim(),
                    'weatherCondition': 'Unknown',
                    'imageUrl': imageUrlController.text.trim(),
                    'tourId': tourRef.id,
                    'createdAt': FieldValue.serverTimestamp(),
                    'updatedAt': FieldValue.serverTimestamp(),
                  });

                  if (!dialogContext.mounted) return;
                  Navigator.of(dialogContext).pop();
                  messenger.showSnackBar(
                    const SnackBar(content: Text('New place created.')),
                  );
                } catch (e) {
                  if (!mounted) return;
                  messenger.showSnackBar(
                    SnackBar(content: Text('Failed to create place: $e')),
                  );
                } finally {
                  if (mounted) {
                    setState(() {
                      _isCreatingPlace = false;
                    });
                  }
                }
              },
              icon: _isCreatingPlace
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.add_location_alt),
              label: const Text('Create Place'),
            ),
          ],
        );
      },
    );

    titleController.dispose();
    locationController.dispose();
    descriptionController.dispose();
    imageUrlController.dispose();
  }

  Future<void> _logout() async {
    if (_isSigningOut) return;

    final shouldLogout = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm Logout'),
        content: const Text('Sign out from admin account?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Logout'),
          ),
        ],
      ),
    );

    if (shouldLogout != true) return;

    setState(() {
      _isSigningOut = true;
    });

    try {
      await _authService.signOut();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to logout: $e')));
    } finally {
      if (mounted) {
        setState(() {
          _isSigningOut = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!isAdminEmail(FirebaseAuth.instance.currentUser?.email)) {
      return Scaffold(
        appBar: AppBar(title: const Text('Admin XR')),
        body: const Center(
          child: Text('Access denied. Admin account required.'),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin XR Editor'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: FilledButton.icon(
              onPressed: _isCreatingPlace ? null : _showAddPlaceDialog,
              icon: const Icon(Icons.add_location_alt),
              label: const Text('Add Place'),
            ),
          ),
          IconButton(
            onPressed: _isSigningOut ? null : _logout,
            tooltip: 'Logout',
            icon: _isSigningOut
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.logout),
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _db.collection('places').orderBy('title').snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(
              child: Text('Failed to load places: ${snapshot.error}'),
            );
          }

          final docs = snapshot.data?.docs ?? const [];
          if (docs.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('No places found.'),
                  const SizedBox(height: 10),
                  FilledButton.icon(
                    onPressed: _showAddPlaceDialog,
                    icon: const Icon(Icons.add_location_alt),
                    label: const Text('Add First Place'),
                  ),
                ],
              ),
            );
          }

          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1100),
              child: ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: docs.length,
                separatorBuilder: (context, index) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final doc = docs[index];
                  final data = doc.data();
                  final placeTitle = (data['title'] ?? '').toString();
                  final location = (data['location'] ?? '').toString();
                  final tourId = (data['tourId'] ?? '').toString();
                  final hasTour = tourId.trim().isNotEmpty;

                  return Card(
                    child: ListTile(
                      title: Text(placeTitle.isEmpty ? doc.id : placeTitle),
                      subtitle: Text(
                        'Location: $location\nTour ID: ${hasTour ? tourId : 'Not set'}',
                      ),
                      isThreeLine: true,
                      trailing: hasTour
                          ? FilledButton(
                              onPressed: () {
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => TourNodesScreen(
                                      placeId: doc.id,
                                      tourId: tourId,
                                    ),
                                  ),
                                );
                              },
                              child: const Text('Open Editor'),
                            )
                          : OutlinedButton(
                              onPressed: _isCreatingTour
                                  ? null
                                  : () => _createTourForPlace(doc.id),
                              child: const Text('Create Tour'),
                            ),
                    ),
                  );
                },
              ),
            ),
          );
        },
      ),
    );
  }
}
