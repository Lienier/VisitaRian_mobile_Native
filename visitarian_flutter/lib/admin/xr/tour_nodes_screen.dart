import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'admin_access.dart';
import 'node_editor_screen.dart';
import 'xr_firestore.dart';
import '../../services/weather_service.dart';

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
  final _headerFormKey = GlobalKey<FormState>();

  final _titleController = TextEditingController();
  final _locationController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _temperatureController = TextEditingController();
  final _imageUrlController = TextEditingController();

  final _discoverTitleController = TextEditingController();
  final _discoverSubtitleController = TextEditingController();
  final _searchHintController = TextEditingController();

  bool _loadingMeta = true;
  bool _savingPlace = false;
  bool _savingHeader = false;
  bool _fetchingTemperature = false;

  final WeatherService _weatherService = const WeatherService();

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
    _temperatureController.dispose();
    _imageUrlController.dispose();
    _discoverTitleController.dispose();
    _discoverSubtitleController.dispose();
    _searchHintController.dispose();
    super.dispose();
  }

  Future<void> _loadMeta() async {
    String? warning;

    try {
      final placeDoc = await _db.collection('places').doc(widget.placeId).get();
      final place = placeDoc.data() ?? const <String, dynamic>{};

      _titleController.text = (place['title'] ?? '').toString();
      _locationController.text = (place['location'] ?? '').toString();
      _descriptionController.text = (place['description'] ?? '').toString();
      final temp = (place['temperature'] ?? place['temperatureC'] ?? '')
          .toString();
      _temperatureController.text = temp;
      _imageUrlController.text = (place['imageUrl'] ?? '').toString();
    } catch (e) {
      warning = 'Failed to load place details: $e';
    }

    try {
      final headerDoc = await _db
          .collection('appConfig')
          .doc('tourSelectionHeader')
          .get();
      final header = headerDoc.data() ?? const <String, dynamic>{};

      _discoverTitleController.text = (header['discoverTitle'] ?? 'Discover')
          .toString();
      _discoverSubtitleController.text =
          (header['discoverSubtitle'] ?? 'Find your perfect destination')
              .toString();
      _searchHintController.text =
          (header['searchHint'] ?? 'Search destinations...').toString();
    } catch (e) {
      warning = warning == null
          ? 'Failed to load header config: $e'
          : '$warning\nFailed to load header config: $e';
      _discoverTitleController.text = 'Discover';
      _discoverSubtitleController.text = 'Find your perfect destination';
      _searchHintController.text = 'Search destinations...';
    } finally {
      if (mounted) {
        setState(() {
          _loadingMeta = false;
        });
      }
    }

    if (warning != null && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(warning)));
    }
  }

  Future<void> _refreshTemperatureFromApi() async {
    if (_fetchingTemperature) return;

    final location = _locationController.text.trim();
    final title = _titleController.text.trim();
    final query = location.isNotEmpty ? location : title;

    if (query.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Enter location or title first to fetch temperature.'),
        ),
      );
      return;
    }

    setState(() {
      _fetchingTemperature = true;
    });

    try {
      final temperature = await _weatherService.fetchCurrentTemperatureC(query);
      if (!mounted) return;
      setState(() {
        _temperatureController.text = temperature.toStringAsFixed(1);
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Temperature updated from API: ${temperature.toStringAsFixed(1)} Ãƒâ€šÃ‚Â°C',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to fetch temperature: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _fetchingTemperature = false;
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

    var tempValue = double.tryParse(_temperatureController.text.trim());
    if (tempValue == null) {
      await _refreshTemperatureFromApi();
      if (!mounted) return;
      tempValue = double.tryParse(_temperatureController.text.trim());
    }
    if (tempValue == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Temperature must be numeric or fetched from API.'),
        ),
      );
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
        'temperature': tempValue,
        'temperatureC': tempValue,
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

  Future<void> _saveHeader() async {
    if (_savingHeader) return;
    if (!(_headerFormKey.currentState?.validate() ?? false)) return;

    setState(() {
      _savingHeader = true;
    });

    try {
      await _db.collection('appConfig').doc('tourSelectionHeader').set({
        'discoverTitle': _discoverTitleController.text.trim(),
        'discoverSubtitle': _discoverSubtitleController.text.trim(),
        'searchHint': _searchHintController.text.trim(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Header content updated.')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to save header: $e')));
    } finally {
      if (mounted) {
        setState(() {
          _savingHeader = false;
        });
      }
    }
  }

  Future<void> _openNodeEditor(String nodeId) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => NodeEditorScreen(
          tourId: widget.tourId,
          nodeId: nodeId,
          xrFirestore: _xrFirestore,
        ),
      ),
    );
  }

  Future<void> _setStartNode(String nodeId) async {
    await _xrFirestore.setStartNode(tourId: widget.tourId, startNodeId: nodeId);
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Start node updated.')));
  }

  Future<void> _createNode() async {
    final newNodeId = _xrFirestore.createNodeId(widget.tourId);
    await _openNodeEditor(newNodeId);
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
                      controller: _temperatureController,
                      decoration: const InputDecoration(
                        labelText: 'Temperature (Ãƒâ€šÃ‚Â°C)',
                        helperText: 'Auto from Open-Meteo API',
                      ),
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      validator: (v) => _required(v, 'Temperature'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  OutlinedButton.icon(
                    onPressed: _fetchingTemperature
                        ? null
                        : _refreshTemperatureFromApi,
                    icon: _fetchingTemperature
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

  Widget _buildHeaderForm() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _headerFormKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Home Header (Used by Tour Selection Header)',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _discoverTitleController,
                decoration: const InputDecoration(labelText: 'Header Title'),
                validator: (v) => _required(v, 'Header Title'),
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _discoverSubtitleController,
                decoration: const InputDecoration(labelText: 'Header Subtitle'),
                validator: (v) => _required(v, 'Header Subtitle'),
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _searchHintController,
                decoration: const InputDecoration(labelText: 'Search Hint'),
                validator: (v) => _required(v, 'Search Hint'),
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.icon(
                  onPressed: _savingHeader ? null : _saveHeader,
                  icon: _savingHeader
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save),
                  label: const Text('Save Header'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNodesSection() {
    final tourDocStream = _db
        .collection('tours')
        .doc(widget.tourId)
        .snapshots();

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: tourDocStream,
      builder: (context, tourSnapshot) {
        final startNodeId = (tourSnapshot.data?.data()?['startNodeId'] ?? '')
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
            if (docs.isEmpty) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text('No nodes yet. Add your first panorama node.'),
              );
            }

            return Column(
              children: docs
                  .map((doc) {
                    final data = doc.data();
                    final name = (data['name'] ?? '').toString();
                    final panoUrl = (data['panoUrl'] ?? '').toString();
                    final hotspots =
                        (data['hotspots'] as List<dynamic>? ?? const []);
                    final isStartNode =
                        startNodeId.isNotEmpty && startNodeId == doc.id;

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Card(
                        child: ListTile(
                          onTap: () => _openNodeEditor(doc.id),
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
                                  padding: EdgeInsets.only(right: 8),
                                  child: Icon(Icons.flag, color: Colors.green),
                                ),
                              PopupMenuButton<String>(
                                onSelected: (value) {
                                  if (value == 'edit') {
                                    _openNodeEditor(doc.id);
                                  }
                                  if (value == 'setStart') {
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
                            ],
                          ),
                        ),
                      ),
                    );
                  })
                  .toList(growable: false),
            );
          },
        );
      },
    );
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
      appBar: AppBar(title: const Text('Unified Place + XR Editor')),
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
                    _buildHeaderForm(),
                    const SizedBox(height: 12),
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
                    const SizedBox(height: 8),
                    _buildNodesSection(),
                  ],
                ),
              ),
            ),
    );
  }
}
