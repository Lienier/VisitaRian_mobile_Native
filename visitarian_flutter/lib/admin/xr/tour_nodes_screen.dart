import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:visitarian_flutter/admin/xr/admin_access.dart';
import 'package:visitarian_flutter/admin/xr/node_workspace_screen.dart';
import 'package:visitarian_flutter/admin/xr/xr_firestore.dart';
import 'package:visitarian_flutter/core/services/services.dart';

class TourNodesScreen extends StatefulWidget {
  final String placeId;
  final String tourId;
  final XrFirestore? xrFirestore;

  const TourNodesScreen({
    super.key,
    required this.placeId,
    required this.tourId,
    this.xrFirestore,
  });

  @override
  State<TourNodesScreen> createState() => _TourNodesScreenState();
}

class _TourNodesScreenState extends State<TourNodesScreen> {
  late final XrFirestore _xrFirestore;
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  final _placeFormKey = GlobalKey<FormState>();

  final _titleController = TextEditingController();
  final _locationController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _weatherController = TextEditingController();
  final _imageUrlController = TextEditingController();

  bool _loadingMeta = true;
  bool _savingPlace = false;
  bool _fetchingWeather = false;
  bool _isSigningOut = false;

  final WeatherService _weatherService = const WeatherService();
  final AuthService _authService = AuthService();
  bool _reorderingNodes = false;

  @override
  void initState() {
    super.initState();
    _xrFirestore = widget.xrFirestore ?? XrFirestore();
    _loadMeta();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _locationController.dispose();
    _descriptionController.dispose();
    _weatherController.dispose();
    _imageUrlController.dispose();
    super.dispose();
  }

  Future<void> _loadMeta() async {
    try {
      final placeDoc = await _db.collection('places').doc(widget.placeId).get();
      final place = placeDoc.data() ?? const <String, dynamic>{};

      _titleController.text = (place['title'] ?? '').toString();
      _locationController.text = (place['location'] ?? '').toString();
      _descriptionController.text = (place['description'] ?? '').toString();
      _weatherController.text = (place['weatherCondition'] ?? '').toString();
      _imageUrlController.text = (place['imageUrl'] ?? '').toString();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load place details: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _loadingMeta = false;
        });
      }
    }
  }

  Future<void> _refreshWeatherFromApi() async {
    if (_fetchingWeather) return;

    final location = _locationController.text.trim();
    final title = _titleController.text.trim();
    final query = location.isNotEmpty ? location : title;

    if (query.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Enter location or title first to fetch weather.'),
        ),
      );
      return;
    }

    setState(() {
      _fetchingWeather = true;
    });

    try {
      final weather = await _weatherService.fetchCurrentCondition(query);
      if (!mounted) return;
      setState(() {
        _weatherController.text = weather;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Weather updated from API: $weather')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to fetch weather: $e')));
    } finally {
      if (mounted) {
        setState(() {
          _fetchingWeather = false;
        });
      }
    }
  }

  String? _required(String? value, String field) {
    if (value == null || value.trim().isEmpty) {
      return '$field is required';
    }
    return null;
  }

  Future<void> _savePlace() async {
    if (_savingPlace) return;
    if (!(_placeFormKey.currentState?.validate() ?? false)) return;

    var weather = _weatherController.text.trim();
    if (weather.isEmpty) {
      await _refreshWeatherFromApi();
      if (!mounted) return;
      weather = _weatherController.text.trim();
    }
    if (weather.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Weather is required.')));
      return;
    }

    setState(() {
      _savingPlace = true;
    });

    try {
      await _db.collection('places').doc(widget.placeId).set({
        'title': _titleController.text.trim(),
        'location': _locationController.text.trim(),
        'description': _descriptionController.text.trim(),
        'weatherCondition': weather,
        'imageUrl': _imageUrlController.text.trim(),
        'tourId': widget.tourId,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Place details updated.')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to save place: $e')));
    } finally {
      if (mounted) {
        setState(() {
          _savingPlace = false;
        });
      }
    }
  }

  Future<void> _setStartNode(String nodeId) async {
    await _xrFirestore.setStartNode(tourId: widget.tourId, startNodeId: nodeId);
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Start node updated.')));
  }

  Future<void> _openNodeWorkspace({String? initialNodeId}) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => NodeWorkspaceScreen(
          tourId: widget.tourId,
          initialNodeId: initialNodeId,
          xrFirestore: _xrFirestore,
        ),
      ),
    );
  }

  Future<void> _createNode() async {
    final newNodeId = _xrFirestore.createNodeId(widget.tourId);
    try {
      await _xrFirestore.createNodeDraft(
        tourId: widget.tourId,
        nodeId: newNodeId,
      );
      if (!mounted) return;
      await _openNodeWorkspace(initialNodeId: newNodeId);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to create node: $e')));
    }
  }

  int _compareNodeDocs(
    QueryDocumentSnapshot<Map<String, dynamic>> a,
    QueryDocumentSnapshot<Map<String, dynamic>> b,
  ) {
    final aOrder = (a.data()['order'] as num?)?.toInt();
    final bOrder = (b.data()['order'] as num?)?.toInt();
    if (aOrder != null && bOrder != null) return aOrder.compareTo(bOrder);
    if (aOrder != null) return -1;
    if (bOrder != null) return 1;

    final aTs = a.data()['updatedAt'] as Timestamp?;
    final bTs = b.data()['updatedAt'] as Timestamp?;
    if (aTs == null && bTs == null) return 0;
    if (aTs == null) return 1;
    if (bTs == null) return -1;
    return bTs.compareTo(aTs);
  }

  Future<void> _reorderNodes(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> sortedDocs,
    int oldIndex,
    int newIndex,
  ) async {
    if (_reorderingNodes) return;
    setState(() {
      _reorderingNodes = true;
    });

    try {
      final reordered = List<QueryDocumentSnapshot<Map<String, dynamic>>>.from(
        sortedDocs,
      );
      if (newIndex > oldIndex) {
        newIndex -= 1;
      }
      final item = reordered.removeAt(oldIndex);
      reordered.insert(newIndex, item);

      await _xrFirestore.reorderNodes(
        tourId: widget.tourId,
        orderedNodeIds: reordered.map((e) => e.id).toList(growable: false),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to reorder nodes: $e')));
    } finally {
      if (mounted) {
        setState(() {
          _reorderingNodes = false;
        });
      }
    }
  }

  Widget _buildPlaceForm() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _placeFormKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Place Details (Used by Place Detail)',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _titleController,
                decoration: const InputDecoration(labelText: 'Title'),
                validator: (v) => _required(v, 'Title'),
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _locationController,
                decoration: const InputDecoration(labelText: 'Location'),
                validator: (v) => _required(v, 'Location'),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _weatherController,
                      decoration: const InputDecoration(
                        labelText: 'Weather',
                        helperText: 'Auto from Open-Meteo API',
                      ),
                      validator: (v) => _required(v, 'Weather'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  OutlinedButton.icon(
                    onPressed: _fetchingWeather ? null : _refreshWeatherFromApi,
                    icon: _fetchingWeather
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.cloud_sync),
                    label: const Text('Auto'),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _imageUrlController,
                decoration: const InputDecoration(labelText: 'Image URL'),
                validator: (v) => _required(v, 'Image URL'),
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _descriptionController,
                decoration: const InputDecoration(labelText: 'Description'),
                minLines: 3,
                maxLines: 6,
                validator: (v) => _required(v, 'Description'),
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.icon(
                  onPressed: _savingPlace ? null : _savePlace,
                  icon: _savingPlace
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save),
                  label: const Text('Save Place'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNodeListPanel() {
    final tourDocStream = _db
        .collection('tours')
        .doc(widget.tourId)
        .snapshots();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'XR Nodes',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const Spacer(),
                FilledButton.icon(
                  onPressed: _createNode,
                  icon: const Icon(Icons.add),
                  label: const Text('Add Node'),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Expanded(
              child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                stream: tourDocStream,
                builder: (context, tourSnapshot) {
                  final startNodeId =
                      (tourSnapshot.data?.data()?['startNodeId'] ?? '')
                          .toString();

                  return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    stream: _xrFirestore.nodesStream(widget.tourId),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      }

                      if (snapshot.hasError) {
                        return Text('Failed to load nodes: ${snapshot.error}');
                      }

                      final docs = snapshot.data?.docs ?? const [];
                      final sortedDocs = docs.toList(growable: false)
                        ..sort(_compareNodeDocs);
                      if (sortedDocs.isEmpty) {
                        return const Center(
                          child: Text(
                            'No nodes yet. Click "Add Node" to create one.',
                          ),
                        );
                      }

                      return ReorderableListView.builder(
                        buildDefaultDragHandles: false,
                        itemCount: sortedDocs.length,
                        onReorder: (oldIndex, newIndex) =>
                            _reorderNodes(sortedDocs, oldIndex, newIndex),
                        itemBuilder: (context, index) {
                          final doc = sortedDocs[index];
                          final data = doc.data();
                          final name = (data['name'] ?? '').toString();
                          final panoUrl = (data['panoUrl'] ?? '').toString();
                          final hotspots =
                              (data['hotspots'] as List<dynamic>? ?? const []);
                          final isStartNode =
                              startNodeId.isNotEmpty && startNodeId == doc.id;

                          return ListTile(
                            key: ValueKey(doc.id),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                              side: BorderSide(color: Colors.grey.shade300),
                            ),
                            onTap: () =>
                                _openNodeWorkspace(initialNodeId: doc.id),
                            title: Text(name.isEmpty ? doc.id : name),
                            subtitle: Text(
                              'Hotspots: ${hotspots.length}\n$panoUrl',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            isThreeLine: true,
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (isStartNode)
                                  const Padding(
                                    padding: EdgeInsets.only(right: 6),
                                    child: Icon(
                                      Icons.flag,
                                      color: Colors.green,
                                    ),
                                  ),
                                IconButton(
                                  tooltip: 'Copy node ID',
                                  icon: const Icon(Icons.copy, size: 18),
                                  onPressed: () async {
                                    final messenger = ScaffoldMessenger.of(
                                      context,
                                    );
                                    await Clipboard.setData(
                                      ClipboardData(text: doc.id),
                                    );
                                    if (!mounted) return;
                                    messenger.showSnackBar(
                                      const SnackBar(
                                        content: Text('Node ID copied.'),
                                      ),
                                    );
                                  },
                                ),
                                PopupMenuButton<String>(
                                  onSelected: (value) {
                                    if (value == 'edit') {
                                      _openNodeWorkspace(initialNodeId: doc.id);
                                    } else if (value == 'setStart') {
                                      _setStartNode(doc.id);
                                    }
                                  },
                                  itemBuilder: (context) => const [
                                    PopupMenuItem<String>(
                                      value: 'edit',
                                      child: Text('Edit node'),
                                    ),
                                    PopupMenuItem<String>(
                                      value: 'setStart',
                                      child: Text('Set as start node'),
                                    ),
                                  ],
                                ),
                                ReorderableDragStartListener(
                                  index: index,
                                  child: Icon(
                                    Icons.drag_handle,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
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
    final isAdmin = isAdminEmail(FirebaseAuth.instance.currentUser?.email);
    if (!isAdmin) {
      return Scaffold(
        appBar: AppBar(title: const Text('XR Tour Nodes')),
        body: const Center(
          child: Text('Access denied. Admin account required.'),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Unified Place + XR Editor'),
        actions: [
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
      body: _loadingMeta
          ? const Center(child: CircularProgressIndicator())
          : Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1100),
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    _buildPlaceForm(),
                    const SizedBox(height: 12),
                    SizedBox(height: 360, child: _buildNodeListPanel()),
                  ],
                ),
              ),
            ),
    );
  }
}
