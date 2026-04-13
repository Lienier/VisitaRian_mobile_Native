import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

class AdminSpotCreatorScreen extends StatefulWidget {
  final String? initialPlaceId;

  const AdminSpotCreatorScreen({super.key, this.initialPlaceId});

  @override
  State<AdminSpotCreatorScreen> createState() => _AdminSpotCreatorScreenState();
}

class _AdminSpotCreatorScreenState extends State<AdminSpotCreatorScreen> {
  static const String _boundaryAssetPath = 'assets/geo/norzagaray.geojson';
  static const LatLng _defaultCenter = LatLng(14.9083, 121.0509);

  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final MapController _mapController = MapController();
  final TextEditingController _searchController = TextEditingController();

  bool _loadingBoundary = true;
  bool _saving = false;
  bool _clearing = false;
  String? _boundaryError;
  String? _statusMessage;
  String? _selectedPlaceId;
  String _searchQuery = '';
  LatLng? _draftPoint;
  List<Polyline> _boundaryPolylines = const [];
  List<List<List<LatLng>>> _boundaryPolygons = const [];

  @override
  void initState() {
    super.initState();
    _selectedPlaceId = widget.initialPlaceId?.trim().isNotEmpty == true
        ? widget.initialPlaceId!.trim()
        : null;
    _searchController.addListener(() {
      if (!mounted) return;
      setState(() {
        _searchQuery = _searchController.text.trim().toLowerCase();
      });
    });
    _loadBoundary();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadBoundary() async {
    try {
      final raw = await rootBundle.loadString(_boundaryAssetPath);
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final features = decoded['features'] as List<dynamic>? ?? const [];

      final polygons = <List<List<LatLng>>>[];
      for (final rawFeature in features) {
        final feature = rawFeature as Map<String, dynamic>;
        final geometry =
            feature['geometry'] as Map<String, dynamic>? ??
            const <String, dynamic>{};
        final type = (geometry['type'] ?? '').toString();
        final coordinates = geometry['coordinates'];

        if (type == 'Polygon' && coordinates is List<dynamic>) {
          final polygon = _parseRings(coordinates);
          if (polygon.isNotEmpty) polygons.add(polygon);
          continue;
        }

        if (type == 'MultiPolygon' && coordinates is List<dynamic>) {
          for (final rawPolygon in coordinates) {
            if (rawPolygon is List<dynamic>) {
              final polygon = _parseRings(rawPolygon);
              if (polygon.isNotEmpty) polygons.add(polygon);
            }
          }
        }
      }

      final lines = <Polyline>[];
      for (final polygon in polygons) {
        for (final ring in polygon) {
          lines.add(
            Polyline(
              points: ring,
              color: Colors.green.shade700,
              strokeWidth: 3,
            ),
          );
        }
      }

      if (!mounted) return;
      setState(() {
        _boundaryPolygons = polygons;
        _boundaryPolylines = lines;
        _loadingBoundary = false;
        _boundaryError = polygons.isEmpty
            ? 'Boundary geometry is empty.'
            : null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingBoundary = false;
        _boundaryError = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  List<List<LatLng>> _parseRings(List<dynamic> rawRings) {
    final rings = <List<LatLng>>[];
    for (final rawRing in rawRings) {
      if (rawRing is! List<dynamic>) continue;
      final ring = <LatLng>[];
      for (final rawPoint in rawRing) {
        if (rawPoint is! List<dynamic> || rawPoint.length < 2) continue;
        ring.add(
          LatLng(
            (rawPoint[1] as num).toDouble(),
            (rawPoint[0] as num).toDouble(),
          ),
        );
      }
      if (ring.length >= 3) rings.add(ring);
    }
    return rings;
  }

  bool _isPointInRing(LatLng point, List<LatLng> ring) {
    var inside = false;
    for (var i = 0, j = ring.length - 1; i < ring.length; j = i++) {
      final xi = ring[i].longitude;
      final yi = ring[i].latitude;
      final xj = ring[j].longitude;
      final yj = ring[j].latitude;

      final intersects =
          ((yi > point.latitude) != (yj > point.latitude)) &&
          (point.longitude <
              (xj - xi) * (point.latitude - yi) / ((yj - yi) + 1e-12) + xi);
      if (intersects) inside = !inside;
    }
    return inside;
  }

  bool _isInNorzagaray(LatLng point) {
    if (_boundaryPolygons.isEmpty) return true;
    for (final polygon in _boundaryPolygons) {
      if (!_isPointInRing(point, polygon.first)) continue;
      var insideHole = false;
      for (var i = 1; i < polygon.length; i++) {
        if (_isPointInRing(point, polygon[i])) {
          insideHole = true;
          break;
        }
      }
      if (!insideHole) return true;
    }
    return false;
  }

  void _moveTo(LatLng point, {double zoom = 15}) {
    try {
      _mapController.move(point, zoom);
    } catch (_) {
      // Ignore if the controller is not attached yet.
    }
  }

  void _selectPlace(_PlaceSpotRecord place) {
    final existingSpot = place.spot;
    setState(() {
      _selectedPlaceId = place.id;
      _draftPoint = existingSpot;
      _statusMessage = existingSpot == null
          ? 'Tap the map to create a spot for ${place.title}.'
          : 'Adjust the pin for ${place.title} or save it as-is.';
    });
    _moveTo(existingSpot ?? _defaultCenter, zoom: existingSpot == null ? 13 : 16);
  }

  void _handleMapTap(TapPosition _, LatLng point) {
    if (_selectedPlaceId == null) {
      setState(() {
        _statusMessage = 'Select a place first, then tap the map to position its spot.';
      });
      return;
    }
    if (!_isInNorzagaray(point)) {
      setState(() {
        _statusMessage = 'Spot must stay inside the Norzagaray boundary.';
      });
      return;
    }

    setState(() {
      _draftPoint = point;
      _statusMessage =
          'Spot positioned at ${point.latitude.toStringAsFixed(5)}, ${point.longitude.toStringAsFixed(5)}. Save to publish it.';
    });
  }

  Future<void> _saveSpot(_PlaceSpotRecord place) async {
    final point = _draftPoint;
    if (point == null || _saving) return;

    setState(() {
      _saving = true;
    });

    try {
      await _db.collection('places').doc(place.id).set({
        'mapSpot': {
          'latitude': point.latitude,
          'longitude': point.longitude,
          'label': place.title,
          'updatedAt': FieldValue.serverTimestamp(),
        },
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (!mounted) return;
      setState(() {
        _statusMessage = 'Saved navigation spot for ${place.title}.';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Spot saved for ${place.title}.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to save spot: $e')));
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }

  Future<void> _clearSpot(_PlaceSpotRecord place) async {
    if (_clearing) return;
    setState(() {
      _clearing = true;
    });

    try {
      await _db.collection('places').doc(place.id).set({
        'mapSpot': FieldValue.delete(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (!mounted) return;
      setState(() {
        _draftPoint = null;
        _statusMessage = 'Cleared the saved map spot for ${place.title}.';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Spot cleared for ${place.title}.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to clear spot: $e')));
    } finally {
      if (mounted) {
        setState(() {
          _clearing = false;
        });
      }
    }
  }

  bool _matchesQuery(_PlaceSpotRecord place) {
    if (_searchQuery.isEmpty) return true;
    return place.title.toLowerCase().contains(_searchQuery) ||
        place.location.toLowerCase().contains(_searchQuery);
  }

  Widget _buildPlaceList(
    List<_PlaceSpotRecord> allPlaces,
    List<_PlaceSpotRecord> filteredPlaces,
  ) {
    final selected = _findPlaceById(allPlaces, _selectedPlaceId);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Places',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _searchController,
              decoration: InputDecoration(
                isDense: true,
                hintText: 'Search place or location',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
            const SizedBox(height: 12),
            if (selected != null)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  _draftPoint == null
                      ? 'Selected: ${selected.title}\nTap the map to place a navigation spot.'
                      : 'Selected: ${selected.title}\nDraft: ${_draftPoint!.latitude.toStringAsFixed(5)}, ${_draftPoint!.longitude.toStringAsFixed(5)}',
                ),
              ),
            if (selected != null) const SizedBox(height: 12),
            Expanded(
              child: filteredPlaces.isEmpty
                  ? const Center(child: Text('No matching places found.'))
                  : ListView.separated(
                      itemCount: filteredPlaces.length,
                      separatorBuilder: (context, index) =>
                          const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final place = filteredPlaces[index];
                        final isSelected = place.id == _selectedPlaceId;
                        final spot = place.spot;
                        return ListTile(
                          tileColor: isSelected
                              ? Theme.of(context).colorScheme.primaryContainer
                              : null,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                            side: BorderSide(
                              color: isSelected
                                  ? Theme.of(context).colorScheme.primary
                                  : Colors.grey.shade300,
                            ),
                          ),
                          onTap: () => _selectPlace(place),
                          title: Text(place.title),
                          subtitle: Text(
                            spot == null
                                ? '${place.location}\nNo map spot saved yet'
                                : '${place.location}\n${spot.latitude.toStringAsFixed(5)}, ${spot.longitude.toStringAsFixed(5)}',
                            maxLines: 2,
                          ),
                          isThreeLine: true,
                          trailing: Icon(
                            spot == null
                                ? Icons.location_off_outlined
                                : Icons.location_on,
                            color: spot == null ? Colors.grey : Colors.green,
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMapPanel(List<_PlaceSpotRecord> places) {
    final selected = _findPlaceById(places, _selectedPlaceId);
    final selectedSavedSpot = selected?.spot;
    final showDraftMarker =
        _draftPoint != null &&
        (selectedSavedSpot == null ||
            selectedSavedSpot.latitude != _draftPoint!.latitude ||
            selectedSavedSpot.longitude != _draftPoint!.longitude);

    final markers = <Marker>[
      ...places.where((place) => place.spot != null).map((place) {
        final spot = place.spot!;
        final isSelected = place.id == _selectedPlaceId;
        return Marker(
          point: spot,
          width: 52,
          height: 52,
          child: GestureDetector(
            onTap: () => _selectPlace(place),
            child: Icon(
              isSelected ? Icons.place : Icons.location_on,
              color: isSelected ? Colors.orange : Colors.red,
              size: isSelected ? 38 : 32,
            ),
          ),
        );
      }),
      if (showDraftMarker)
        Marker(
          point: _draftPoint!,
          width: 54,
          height: 54,
          child: const Icon(
            Icons.add_location_alt,
            color: Colors.blue,
            size: 36,
          ),
        ),
    ];

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Spot Creator',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 6),
                Text(
                  _statusMessage ??
                      'Select a place and tap on the map to place its navigation spot.',
                ),
                if (_loadingBoundary)
                  const Padding(
                    padding: EdgeInsets.only(top: 6),
                    child: Text('Loading Norzagaray boundary...'),
                  ),
                if (_boundaryError != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      'Boundary warning: $_boundaryError',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                if (selected != null) ...[
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilledButton.icon(
                        onPressed: _draftPoint == null || _saving
                            ? null
                            : () => _saveSpot(selected),
                        icon: _saving
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.save),
                        label: const Text('Save Spot'),
                      ),
                      OutlinedButton.icon(
                        onPressed:
                            (selected.spot == null && _draftPoint == null) ||
                                _clearing
                            ? null
                            : () => _clearSpot(selected),
                        icon: _clearing
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.delete_outline),
                        label: const Text('Clear Spot'),
                      ),
                      if (selected.spot != null)
                        OutlinedButton.icon(
                          onPressed: () => _moveTo(selected.spot!, zoom: 16),
                          icon: const Icon(Icons.center_focus_strong),
                          label: const Text('Center Saved Spot'),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          Expanded(
            child: FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: _defaultCenter,
                initialZoom: 12,
                minZoom: 9,
                maxZoom: 18,
                onTap: _handleMapTap,
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.example.visitarian_flutter',
                ),
                if (_boundaryPolylines.isNotEmpty)
                  PolylineLayer(polylines: _boundaryPolylines),
                MarkerLayer(markers: markers),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<_PlaceSpotRecord> _readPlaces(QuerySnapshot<Map<String, dynamic>> snapshot) {
    final records = snapshot.docs
        .map((doc) => _PlaceSpotRecord.fromDoc(doc))
        .toList(growable: false);
    return records;
  }

  _PlaceSpotRecord? _findPlaceById(
    List<_PlaceSpotRecord> places,
    String? placeId,
  ) {
    if (placeId == null || placeId.isEmpty) return null;
    for (final place in places) {
      if (place.id == placeId) return place;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Admin Spot Creator')),
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

          final places = _readPlaces(snapshot.data!);
          if (places.isEmpty) {
            return const Center(child: Text('No places available yet.'));
          }

          final selectedExists = places.any((place) => place.id == _selectedPlaceId);
          if (!selectedExists) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted || places.isEmpty) return;
              _selectPlace(places.first);
            });
          }

          final filteredPlaces = places
              .where(_matchesQuery)
              .toList(growable: false);

          return LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 1080;
              if (wide) {
                return Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 360,
                        child: _buildPlaceList(places, filteredPlaces),
                      ),
                      const SizedBox(width: 12),
                      Expanded(child: _buildMapPanel(places)),
                    ],
                  ),
                );
              }

              return Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    SizedBox(height: 320, child: _buildPlaceList(places, filteredPlaces)),
                    const SizedBox(height: 12),
                    Expanded(child: _buildMapPanel(places)),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _PlaceSpotRecord {
  final String id;
  final String title;
  final String location;
  final LatLng? spot;

  const _PlaceSpotRecord({
    required this.id,
    required this.title,
    required this.location,
    required this.spot,
  });

  factory _PlaceSpotRecord.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const <String, dynamic>{};
    final rawSpot = data['mapSpot'];
    LatLng? parsedSpot;

    if (rawSpot is Map) {
      final spot = Map<String, dynamic>.from(rawSpot);
      final latitude = (spot['latitude'] as num?)?.toDouble();
      final longitude = (spot['longitude'] as num?)?.toDouble();
      if (latitude != null && longitude != null) {
        parsedSpot = LatLng(latitude, longitude);
      }
    }

    return _PlaceSpotRecord(
      id: doc.id,
      title: (data['title'] ?? 'Untitled Place').toString().trim().isEmpty
          ? 'Untitled Place'
          : (data['title'] ?? 'Untitled Place').toString().trim(),
      location: (data['location'] ?? '').toString(),
      spot: parsedSpot,
    );
  }
}
