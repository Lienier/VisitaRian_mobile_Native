import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:visitarian_flutter/config/app_env.dart';

class AdminMapTestScreen extends StatefulWidget {
  const AdminMapTestScreen({super.key});

  @override
  State<AdminMapTestScreen> createState() => _AdminMapTestScreenState();
}

class _AdminMapTestScreenState extends State<AdminMapTestScreen> {
  static const String _apiHost = 'api.openrouteservice.org';
  static const String _routePath = '/v2/directions/driving-car/geojson';
  static const String _tomTomHost = 'api.tomtom.com';
  static const String _tomTomIncidentPath =
      '/traffic/services/5/incidentDetails';
  static const String _norzagarayGeoJsonPath = 'assets/geo/norzagaray.geojson';
  static const LatLng _defaultCenter = LatLng(14.9083, 121.0509);
  static const String _norzagarayBbox = '120.93,14.83,121.16,14.99';
  static const double _norzagarayWest = 120.93;
  static const double _norzagaraySouth = 14.83;
  static const double _norzagarayEast = 121.16;
  static const double _norzagarayNorth = 14.99;

  static String get _orsApiKey => AppEnv.orsApiKey;
  static String get _tomTomApiKey => AppEnv.tomTomApiKey;

  LatLng? _startPoint;
  LatLng? _endPoint;
  List<LatLng> _routePoints = const [];
  List<Marker> _incidentMarkers = const [];
  List<Polyline> _incidentPolylines = const [];
  List<Polyline> _boundaryPolylines = const [];
  List<List<List<LatLng>>> _boundaryPolygons = const [];
  bool _loadingRoute = false;
  bool _loadingTraffic = false;
  bool _loadingBoundary = true;
  String? _routeSummary;
  String? _trafficSummary;
  String? _routeError;
  String? _trafficError;
  String? _boundaryError;

  @override
  void initState() {
    super.initState();
    _loadBoundaryPolygon();
  }

  Future<void> _loadBoundaryPolygon() async {
    try {
      final raw = await rootBundle.loadString(_norzagarayGeoJsonPath);
      final json = jsonDecode(raw) as Map<String, dynamic>;
      final features = json['features'] as List<dynamic>? ?? const [];
      if (features.isEmpty) {
        throw Exception('No features found in boundary GeoJSON.');
      }

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

      if (polygons.isEmpty) {
        throw Exception('Unsupported geometry in boundary GeoJSON.');
      }

      final boundaryLines = <Polyline>[];
      for (final polygon in polygons) {
        for (final ring in polygon) {
          if (ring.length >= 2) {
            boundaryLines.add(
              Polyline(points: ring, color: Colors.purple, strokeWidth: 2),
            );
          }
        }
      }

      if (!mounted) return;
      setState(() {
        _boundaryPolygons = polygons;
        _boundaryPolylines = boundaryLines;
        _boundaryError = null;
        _loadingBoundary = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _boundaryError = e.toString().replaceFirst('Exception: ', '');
        _loadingBoundary = false;
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

  bool _isInNorzagarayBounds(LatLng point) {
    return point.longitude >= _norzagarayWest &&
        point.longitude <= _norzagarayEast &&
        point.latitude >= _norzagaraySouth &&
        point.latitude <= _norzagarayNorth;
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

  bool _isInNorzagarayPolygon(LatLng point) {
    if (_boundaryPolygons.isEmpty) return _isInNorzagarayBounds(point);

    for (final polygon in _boundaryPolygons) {
      final outerRing = polygon.first;
      if (!_isPointInRing(point, outerRing)) continue;

      var isInsideHole = false;
      for (var i = 1; i < polygon.length; i++) {
        if (_isPointInRing(point, polygon[i])) {
          isInsideHole = true;
          break;
        }
      }
      if (!isInsideHole) return true;
    }

    return false;
  }

  void _handleMapTap(TapPosition _, LatLng point) {
    setState(() {
      _routeError = null;
      _routeSummary = null;
      _routePoints = const [];

      if (_startPoint == null || _endPoint != null) {
        _startPoint = point;
        _endPoint = null;
        return;
      }

      if (!_isInNorzagarayPolygon(point)) {
        _routeError = 'Destination must be inside Norzagaray, Bulacan.';
        return;
      }

      _endPoint = point;
    });
  }

  Future<void> _fetchRoute() async {
    if (_loadingRoute) return;

    if (_orsApiKey.isEmpty) {
      setState(() {
        _routeError =
            'Missing ORS API key. Add ORS_API_KEY to .env or pass --dart-define.';
      });
      return;
    }

    final start = _startPoint;
    final end = _endPoint;
    if (start == null || end == null) {
      setState(() {
        _routeError = 'Set both start and destination points.';
      });
      return;
    }
    if (!_isInNorzagarayPolygon(end)) {
      setState(() {
        _routeError = 'Destination must be inside Norzagaray, Bulacan.';
      });
      return;
    }

    setState(() {
      _loadingRoute = true;
      _routeError = null;
    });

    try {
      final uri = Uri.https(_apiHost, _routePath);
      final response = await http.post(
        uri,
        headers: <String, String>{
          'Authorization': _orsApiKey,
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'coordinates': [
            [start.longitude, start.latitude],
            [end.longitude, end.latitude],
          ],
          'instructions': true,
        }),
      );

      final body = jsonDecode(response.body);
      if (response.statusCode != 200) {
        final message = body is Map<String, dynamic>
            ? (body['error'] ?? body['message'] ?? 'Route request failed')
                  .toString()
            : 'Route request failed (${response.statusCode})';
        throw Exception(message);
      }

      final data = body as Map<String, dynamic>;
      final features = data['features'] as List<dynamic>? ?? const [];
      if (features.isEmpty) {
        throw Exception('No route found for these points.');
      }

      final firstFeature = features.first as Map<String, dynamic>;
      final geometry =
          firstFeature['geometry'] as Map<String, dynamic>? ??
          const <String, dynamic>{};
      final coordinates = geometry['coordinates'] as List<dynamic>? ?? const [];
      if (coordinates.isEmpty) {
        throw Exception('Route geometry is empty.');
      }

      final points = coordinates
          .map((entry) {
            final pair = entry as List<dynamic>;
            return LatLng(
              (pair[1] as num).toDouble(),
              (pair[0] as num).toDouble(),
            );
          })
          .toList(growable: false);

      final properties =
          firstFeature['properties'] as Map<String, dynamic>? ??
          const <String, dynamic>{};
      final summary =
          properties['summary'] as Map<String, dynamic>? ??
          const <String, dynamic>{};
      final distanceKm = ((summary['distance'] as num?) ?? 0) / 1000;
      final durationMin = ((summary['duration'] as num?) ?? 0) / 60;

      setState(() {
        _routePoints = points;
        _routeSummary =
            'Distance: ${distanceKm.toStringAsFixed(2)} km | ETA: ${durationMin.toStringAsFixed(0)} min';
      });
    } catch (e) {
      setState(() {
        _routeError = e.toString().replaceFirst('Exception: ', '');
      });
    } finally {
      if (mounted) {
        setState(() {
          _loadingRoute = false;
        });
      }
    }
  }

  void _clearSelection() {
    setState(() {
      _startPoint = null;
      _endPoint = null;
      _routePoints = const [];
      _routeSummary = null;
      _routeError = null;
      _trafficError = null;
    });
  }

  Future<void> _fetchTrafficIncidents() async {
    if (_loadingTraffic) return;

    if (_tomTomApiKey.isEmpty) {
      setState(() {
        _trafficError =
            'Missing TomTom API key. Add TOMTOM_API_KEY to .env or pass --dart-define.';
      });
      return;
    }

    setState(() {
      _loadingTraffic = true;
      _trafficError = null;
    });

    try {
      final uri = Uri.https(_tomTomHost, _tomTomIncidentPath, {
        'key': _tomTomApiKey,
        'bbox': _norzagarayBbox,
        'timeValidityFilter': 'present',
        'language': 'en-GB',
      });

      final response = await http.get(uri);
      final body = jsonDecode(response.body);
      if (response.statusCode != 200) {
        final message = body is Map<String, dynamic>
            ? (body['detailedError'] ??
                      body['error'] ??
                      body['message'] ??
                      'Traffic request failed')
                  .toString()
            : 'Traffic request failed (${response.statusCode})';
        throw Exception(message);
      }

      final data = body as Map<String, dynamic>;
      final incidents = (data['incidents'] as List<dynamic>? ?? const []);

      final markerList = <Marker>[];
      final polylineList = <Polyline>[];

      for (final raw in incidents) {
        final incident = raw as Map<String, dynamic>;
        final geometry =
            incident['geometry'] as Map<String, dynamic>? ??
            const <String, dynamic>{};
        final properties =
            incident['properties'] as Map<String, dynamic>? ??
            const <String, dynamic>{};
        final geometryType = (geometry['type'] ?? '').toString().toLowerCase();
        final delaySeconds = (properties['delay'] as num?)?.toInt() ?? 0;
        final from = (properties['from'] ?? '').toString();
        final to = (properties['to'] ?? '').toString();

        if (geometryType == 'point') {
          final coordinates = geometry['coordinates'] as List<dynamic>? ?? [];
          if (coordinates.length >= 2) {
            markerList.add(
              Marker(
                point: LatLng(
                  (coordinates[1] as num).toDouble(),
                  (coordinates[0] as num).toDouble(),
                ),
                width: 42,
                height: 42,
                child: Tooltip(
                  message: [
                    if (from.isNotEmpty) 'From: $from',
                    if (to.isNotEmpty) 'To: $to',
                    if (delaySeconds > 0)
                      'Delay: ${(delaySeconds / 60).round()} min',
                  ].join('\n'),
                  child: const Icon(
                    Icons.warning_amber_rounded,
                    color: Colors.deepOrange,
                    size: 26,
                  ),
                ),
              ),
            );
          }
          continue;
        }

        if (geometryType == 'linestring') {
          final coordinates = geometry['coordinates'] as List<dynamic>? ?? [];
          if (coordinates.isEmpty) continue;
          final points = <LatLng>[];
          for (final rawPoint in coordinates) {
            final point = rawPoint as List<dynamic>;
            if (point.length < 2) continue;
            points.add(
              LatLng(
                (point[1] as num).toDouble(),
                (point[0] as num).toDouble(),
              ),
            );
          }
          if (points.isEmpty) continue;
          polylineList.add(
            Polyline(points: points, color: Colors.deepOrange, strokeWidth: 4),
          );
        }
      }

      setState(() {
        _incidentMarkers = markerList;
        _incidentPolylines = polylineList;
        _trafficSummary =
            'Incidents: ${incidents.length} | Point markers: ${markerList.length} | Line segments: ${polylineList.length}';
      });
    } catch (e) {
      setState(() {
        _trafficError = e.toString().replaceFirst('Exception: ', '');
      });
    } finally {
      if (mounted) {
        setState(() {
          _loadingTraffic = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final routeMarkers = <Marker>[
      if (_startPoint != null)
        Marker(
          point: _startPoint!,
          width: 44,
          height: 44,
          child: const Icon(Icons.trip_origin, color: Colors.green, size: 28),
        ),
      if (_endPoint != null)
        Marker(
          point: _endPoint!,
          width: 44,
          height: 44,
          child: const Icon(Icons.location_on, color: Colors.red, size: 30),
        ),
    ];
    final allMarkers = [...routeMarkers, ..._incidentMarkers];

    return Scaffold(
      appBar: AppBar(title: const Text('Admin ORS Route Test')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _loadingRoute ? null : _fetchRoute,
                        icon: _loadingRoute
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.route),
                        label: const Text('Fetch Route'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      onPressed: _clearSelection,
                      icon: const Icon(Icons.clear),
                      label: const Text('Clear'),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      onPressed: _loadingTraffic
                          ? null
                          : _fetchTrafficIncidents,
                      icon: _loadingTraffic
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.traffic),
                      label: const Text('Fetch Traffic'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    _routeSummary ??
                        'Tap map: 1st tap = Start, 2nd tap = Destination (Norzagaray only).',
                  ),
                ),
                if (_loadingBoundary)
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text('Loading Norzagaray boundary...'),
                  ),
                if (_boundaryError != null)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Boundary fallback to bbox: $_boundaryError',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                if (_routeError != null)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      _routeError!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                if (_trafficSummary != null)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(_trafficSummary!),
                  ),
                if (_trafficError != null)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      _trafficError!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: FlutterMap(
              options: MapOptions(
                initialCenter: _defaultCenter,
                initialZoom: 13,
                minZoom: 8,
                maxZoom: 18,
                onTap: _handleMapTap,
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.example.visitarian_flutter',
                ),
                if (_routePoints.isNotEmpty)
                  PolylineLayer(
                    polylines: [
                      Polyline(
                        points: _routePoints,
                        strokeWidth: 5,
                        color: Colors.blue,
                      ),
                    ],
                  ),
                if (_incidentPolylines.isNotEmpty)
                  PolylineLayer(polylines: _incidentPolylines),
                if (_boundaryPolylines.isNotEmpty)
                  PolylineLayer(polylines: _boundaryPolylines),
                MarkerLayer(markers: allMarkers),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Start: ${_startPoint == null ? '-' : '${_startPoint!.latitude.toStringAsFixed(5)}, ${_startPoint!.longitude.toStringAsFixed(5)}'}',
                  ),
                ),
                Expanded(
                  child: Text(
                    'End: ${_endPoint == null ? '-' : '${_endPoint!.latitude.toStringAsFixed(5)}, ${_endPoint!.longitude.toStringAsFixed(5)}'}',
                    textAlign: TextAlign.end,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
