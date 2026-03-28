import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:visitarian_flutter/config/app_env.dart';

class TourUserMapContent extends StatefulWidget {
  const TourUserMapContent({super.key});

  @override
  State<TourUserMapContent> createState() => _TourUserMapContentState();
}

class _TourUserMapContentState extends State<TourUserMapContent> {
  static const String _boundaryAssetPath = 'assets/geo/norzagaray.geojson';
  static const String _orsHost = 'api.openrouteservice.org';
  static const String _orsPath = '/v2/directions/driving-car/geojson';
  static const String _tomTomHost = 'api.tomtom.com';
  static const String _tomTomIncidentPath =
      '/traffic/services/5/incidentDetails';
  static const LatLng _defaultCenter = LatLng(14.9083, 121.0509);
  static String get _orsApiKey => AppEnv.orsApiKey;
  static String get _tomTomApiKey => AppEnv.tomTomApiKey;

  final MapController _mapController = MapController();
  final Distance _distance = const Distance();

  StreamSubscription<Position>? _positionSub;
  Timer? _etaRefreshTimer;

  bool _loadingBoundary = true;
  bool _locationReady = false;
  bool _routing = false;
  bool _navigating = false;

  String? _statusMessage;
  String? _boundaryError;
  String? _routeError;
  String? _routeSummary;

  LatLng? _currentLocation;
  LatLng? _destination;
  List<LatLng> _routePoints = const [];
  List<Polyline> _boundaryPolylines = const [];
  List<List<List<LatLng>>> _boundaryPolygons = const [];

  DateTime? _lastRerouteAt;
  DateTime? _lastRouteComputeAt;
  Position? _lastPositionSample;
  DateTime? _lastPositionSampleAt;
  final List<double> _recentSpeedSamplesMps = <double>[];
  double _routeDistanceMeters = 0;
  double _routeDurationSeconds = 0;
  double _incidentDelaySeconds = 0;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    _etaRefreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _init() async {
    await _loadBoundary();
    if (!mounted) return;
    await _startLocationTracking();
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

  Future<void> _startLocationTracking() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (!mounted) return;
      setState(() {
        _statusMessage = 'Enable GPS/Location services to start navigation.';
      });
      return;
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      if (!mounted) return;
      setState(() {
        _statusMessage =
            'Location permission denied. Allow location to use navigation.';
      });
      return;
    }

    final current = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
    );

    if (!mounted) return;
    final currentLatLng = LatLng(current.latitude, current.longitude);
    setState(() {
      _locationReady = true;
      _currentLocation = currentLatLng;
      _statusMessage = 'Tap the map to set destination.';
    });
    _moveTo(currentLatLng, zoom: 15);

    _positionSub?.cancel();
    _positionSub =
        Geolocator.getPositionStream(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.bestForNavigation,
            distanceFilter: 5,
          ),
        ).listen((position) {
          final updated = LatLng(position.latitude, position.longitude);
          _captureSpeedSample(position);
          if (!mounted) return;
          setState(() {
            _currentLocation = updated;
          });

          if (_navigating) {
            _moveTo(updated);
            _onLocationUpdateWhileNavigating(updated);
          }
        });
    _startEtaRefreshLoop();
  }

  void _startEtaRefreshLoop() {
    _etaRefreshTimer?.cancel();
    _etaRefreshTimer = Timer.periodic(const Duration(seconds: 8), (_) async {
      if (!mounted || !_navigating || _destination == null || _routing) return;

      _refreshEtaSummary();

      final canPeriodicRecompute =
          _lastRouteComputeAt == null ||
          DateTime.now().difference(_lastRouteComputeAt!) >
              const Duration(seconds: 25);
      if (canPeriodicRecompute) {
        await _computeRoute(updateStatus: false);
      }
    });
  }

  void _captureSpeedSample(Position current) {
    final now = DateTime.now();

    final sensorSpeed = current.speed;
    if (sensorSpeed.isFinite && sensorSpeed > 0.5) {
      _recentSpeedSamplesMps.add(sensorSpeed);
    }

    final prev = _lastPositionSample;
    final prevAt = _lastPositionSampleAt;
    if (prev != null && prevAt != null) {
      final seconds = now.difference(prevAt).inMilliseconds / 1000.0;
      if (seconds > 0.5) {
        final movedMeters = _distance(
          LatLng(prev.latitude, prev.longitude),
          LatLng(current.latitude, current.longitude),
        );
        final computedSpeed = movedMeters / seconds;
        if (computedSpeed.isFinite && computedSpeed > 0.2) {
          _recentSpeedSamplesMps.add(computedSpeed);
        }
      }
    }

    if (_recentSpeedSamplesMps.length > 8) {
      _recentSpeedSamplesMps.removeRange(0, _recentSpeedSamplesMps.length - 8);
    }

    _lastPositionSample = current;
    _lastPositionSampleAt = now;
  }

  void _moveTo(LatLng point, {double? zoom}) {
    try {
      _mapController.move(point, zoom ?? _mapController.camera.zoom);
    } catch (_) {
      // Ignore if map controller is not yet attached.
    }
  }

  Future<void> _onMapTap(TapPosition _, LatLng point) async {
    if (!_locationReady) return;
    if (!_isInNorzagaray(point)) {
      setState(() {
        _routeError = 'Destination must be inside Norzagaray boundary.';
      });
      return;
    }

    setState(() {
      _destination = point;
      _routeError = null;
      _statusMessage = 'Computing route...';
    });
    await _computeRoute();
  }

  Future<void> _computeRoute({bool updateStatus = true}) async {
    if (_routing) return;
    if (_orsApiKey.isEmpty) {
      setState(() {
        _routeError =
            'Missing ORS API key. Add ORS_API_KEY to .env or pass --dart-define.';
      });
      return;
    }

    final start = _currentLocation;
    final end = _destination;
    if (start == null || end == null) return;

    setState(() {
      _routing = true;
      _routeError = null;
      if (updateStatus) {
        _statusMessage = 'Computing route...';
      }
    });

    try {
      final uri = Uri.https(_orsHost, _orsPath);
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
      if (features.isEmpty) throw Exception('No route available.');

      final feature = features.first as Map<String, dynamic>;
      final geometry =
          feature['geometry'] as Map<String, dynamic>? ??
          const <String, dynamic>{};
      final rawCoords = geometry['coordinates'] as List<dynamic>? ?? const [];
      if (rawCoords.isEmpty) throw Exception('Route geometry is empty.');

      final points = rawCoords
          .map((entry) {
            final pair = entry as List<dynamic>;
            return LatLng(
              (pair[1] as num).toDouble(),
              (pair[0] as num).toDouble(),
            );
          })
          .toList(growable: false);

      final summary =
          (feature['properties'] as Map<String, dynamic>? ??
                  const <String, dynamic>{})['summary']
              as Map<String, dynamic>? ??
          const <String, dynamic>{};
      final distanceMeters = ((summary['distance'] as num?) ?? 0).toDouble();
      final durationSeconds = ((summary['duration'] as num?) ?? 0).toDouble();
      final incidentDelaySeconds = await _estimateIncidentDelaySeconds(
        routePoints: points,
        start: start,
        end: end,
      );

      if (!mounted) return;
      setState(() {
        _routePoints = points;
        _routeDistanceMeters = distanceMeters;
        _routeDurationSeconds = durationSeconds;
        _incidentDelaySeconds = incidentDelaySeconds;
        _navigating = true;
        _lastRouteComputeAt = DateTime.now();
        if (updateStatus) {
          _statusMessage = 'Navigation active. Follow the blue route.';
        }
      });
      _refreshEtaSummary();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _routeError = e.toString().replaceFirst('Exception: ', '');
        _navigating = false;
      });
    } finally {
      if (mounted) {
        setState(() {
          _routing = false;
        });
      }
    }
  }

  Future<double> _estimateIncidentDelaySeconds({
    required List<LatLng> routePoints,
    required LatLng start,
    required LatLng end,
  }) async {
    if (_tomTomApiKey.isEmpty || routePoints.isEmpty) return 0;

    try {
      final west = math.min(start.longitude, end.longitude) - 0.04;
      final south = math.min(start.latitude, end.latitude) - 0.04;
      final east = math.max(start.longitude, end.longitude) + 0.04;
      final north = math.max(start.latitude, end.latitude) + 0.04;
      final bbox =
          '${west.toStringAsFixed(6)},${south.toStringAsFixed(6)},${east.toStringAsFixed(6)},${north.toStringAsFixed(6)}';

      final uri = Uri.https(_tomTomHost, _tomTomIncidentPath, {
        'key': _tomTomApiKey,
        'bbox': bbox,
        'timeValidityFilter': 'present',
        'language': 'en-GB',
      });
      final response = await http.get(uri);
      final body = jsonDecode(response.body);
      if (response.statusCode != 200 || body is! Map<String, dynamic>) return 0;

      final incidents = body['incidents'] as List<dynamic>? ?? const [];
      double delaySeconds = 0;

      for (final raw in incidents) {
        final incident = raw as Map<String, dynamic>;
        final geometry =
            incident['geometry'] as Map<String, dynamic>? ??
            const <String, dynamic>{};
        final properties =
            incident['properties'] as Map<String, dynamic>? ??
            const <String, dynamic>{};
        final points = _extractIncidentPoints(geometry);
        if (points.isEmpty) continue;

        var nearRoute = false;
        for (final point in points) {
          if (_distanceToRoutePolyline(point, routePoints) <= 120) {
            nearRoute = true;
            break;
          }
        }
        if (!nearRoute) continue;

        final rawDelay = (properties['delay'] as num?)?.toDouble() ?? 0;
        if (rawDelay > 0) {
          delaySeconds += rawDelay * 0.35;
        } else {
          delaySeconds += 45;
        }
      }

      return delaySeconds.clamp(0, 12 * 60);
    } catch (_) {
      return 0;
    }
  }

  List<LatLng> _extractIncidentPoints(Map<String, dynamic> geometry) {
    final type = (geometry['type'] ?? '').toString().toLowerCase();
    final coordinates = geometry['coordinates'];

    if (type == 'point' &&
        coordinates is List<dynamic> &&
        coordinates.length >= 2) {
      return [
        LatLng(
          (coordinates[1] as num).toDouble(),
          (coordinates[0] as num).toDouble(),
        ),
      ];
    }

    if (type == 'linestring' && coordinates is List<dynamic>) {
      final points = <LatLng>[];
      for (final rawPoint in coordinates) {
        if (rawPoint is! List<dynamic> || rawPoint.length < 2) continue;
        points.add(
          LatLng(
            (rawPoint[1] as num).toDouble(),
            (rawPoint[0] as num).toDouble(),
          ),
        );
      }
      return points;
    }

    return const [];
  }

  void _refreshEtaSummary() {
    final current = _currentLocation;
    if (!_navigating ||
        current == null ||
        _destination == null ||
        _routePoints.isEmpty ||
        _routeDistanceMeters <= 0 ||
        _routeDurationSeconds <= 0) {
      return;
    }

    final remainingRouteMeters = _estimateRemainingRouteMeters(current);
    final progressRatio = (remainingRouteMeters / _routeDistanceMeters).clamp(
      0.0,
      1.0,
    );
    final baseRemainingSeconds = _routeDurationSeconds * progressRatio;

    final expectedSpeed = _routeDistanceMeters / _routeDurationSeconds;
    final measuredSpeed = _smoothedSpeedMps();

    var speedAdjustedSeconds = baseRemainingSeconds;
    if (measuredSpeed > 0.5 && expectedSpeed > 0.5) {
      final factor = (expectedSpeed / measuredSpeed).clamp(0.65, 1.9);
      speedAdjustedSeconds = baseRemainingSeconds * factor;
    }

    final totalEtaSeconds = speedAdjustedSeconds + _incidentDelaySeconds;
    final distanceKm = remainingRouteMeters / 1000;
    final etaMinutes = (totalEtaSeconds / 60).ceil();
    final incidentMinutes = (_incidentDelaySeconds / 60).round();
    final speedKph = measuredSpeed * 3.6;

    if (!mounted) return;
    setState(() {
      _routeSummary =
          'Distance: ${distanceKm.toStringAsFixed(2)} km | ETA: $etaMinutes min'
          '${incidentMinutes > 0 ? ' | Delay +${incidentMinutes}m' : ''}'
          '${speedKph > 1 ? ' | Speed ${speedKph.toStringAsFixed(0)} kph' : ''}';
    });
  }

  double _estimateRemainingRouteMeters(LatLng current) {
    if (_routePoints.isEmpty) return 0;

    var nearestIndex = 0;
    var nearestMeters = double.infinity;
    for (var i = 0; i < _routePoints.length; i++) {
      final meters = _distance(current, _routePoints[i]);
      if (meters < nearestMeters) {
        nearestMeters = meters;
        nearestIndex = i;
      }
    }

    var remaining = nearestMeters;
    for (var i = nearestIndex; i < _routePoints.length - 1; i++) {
      remaining += _distance(_routePoints[i], _routePoints[i + 1]);
    }
    return remaining;
  }

  double _smoothedSpeedMps() {
    if (_recentSpeedSamplesMps.isEmpty) return 0;
    final sum = _recentSpeedSamplesMps.fold<double>(0, (a, b) => a + b);
    return sum / _recentSpeedSamplesMps.length;
  }

  Future<void> _onLocationUpdateWhileNavigating(LatLng current) async {
    if (_routePoints.isEmpty || _destination == null) return;

    final remainingMeters = _distance(current, _destination!);
    if (remainingMeters <= 25) {
      setState(() {
        _navigating = false;
        _routePoints = const [];
        _destination = null;
        _routeSummary = null;
        _routeDistanceMeters = 0;
        _routeDurationSeconds = 0;
        _incidentDelaySeconds = 0;
        _statusMessage = 'Arrived at destination.';
      });
      return;
    }

    final offRouteMeters = _distanceToRoutePolyline(current, _routePoints);
    final canReroute =
        _lastRerouteAt == null ||
        DateTime.now().difference(_lastRerouteAt!) >
            const Duration(seconds: 10);
    _refreshEtaSummary();

    if (offRouteMeters > 45 && canReroute) {
      _lastRerouteAt = DateTime.now();
      setState(() {
        _statusMessage = 'Off-route detected. Recalculating...';
      });
      await _computeRoute();
    }
  }

  double _distanceToRoutePolyline(LatLng point, List<LatLng> polyline) {
    if (polyline.isEmpty) return double.infinity;
    var minMeters = double.infinity;
    for (final routePoint in polyline) {
      final meters = _distance(point, routePoint);
      minMeters = math.min(minMeters, meters);
    }
    return minMeters;
  }

  void _clearNavigation() {
    setState(() {
      _destination = null;
      _routePoints = const [];
      _routeSummary = null;
      _routeError = null;
      _navigating = false;
      _routeDistanceMeters = 0;
      _routeDurationSeconds = 0;
      _incidentDelaySeconds = 0;
      _statusMessage = _locationReady
          ? 'Tap the map to set destination.'
          : 'Waiting for location access...';
    });
  }

  @override
  Widget build(BuildContext context) {
    final errorColor = Theme.of(context).colorScheme.error;
    final user = _currentLocation;
    final destination = _destination;

    final markers = <Marker>[
      if (user != null)
        Marker(
          point: user,
          width: 44,
          height: 44,
          child: const Icon(Icons.my_location, size: 28, color: Colors.blue),
        ),
      if (destination != null)
        Marker(
          point: destination,
          width: 44,
          height: 44,
          child: const Icon(Icons.location_on, size: 30, color: Colors.red),
        ),
    ];

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.navigation_outlined),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(_statusMessage ?? 'Initializing map...'),
                  ),
                  IconButton(
                    tooltip: 'My location',
                    onPressed: user == null
                        ? null
                        : () => _moveTo(user, zoom: 16),
                    icon: const Icon(Icons.gps_fixed),
                  ),
                  IconButton(
                    tooltip: 'Clear navigation',
                    onPressed: _clearNavigation,
                    icon: const Icon(Icons.clear),
                  ),
                ],
              ),
              if (_routeSummary != null) Text(_routeSummary!),
              if (_loadingBoundary)
                const Text('Loading Norzagaray boundary...'),
              if (_boundaryError != null)
                Text(
                  'Boundary warning: $_boundaryError',
                  style: TextStyle(color: errorColor),
                ),
              if (_routeError != null)
                Text(_routeError!, style: TextStyle(color: errorColor)),
            ],
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: FlutterMap(
                mapController: _mapController,
                options: MapOptions(
                  initialCenter: _defaultCenter,
                  initialZoom: 12,
                  minZoom: 9,
                  maxZoom: 18,
                  onTap: _onMapTap,
                ),
                children: [
                  TileLayer(
                    urlTemplate:
                        'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'com.example.visitarian_flutter',
                  ),
                  if (_boundaryPolylines.isNotEmpty)
                    PolylineLayer(polylines: _boundaryPolylines),
                  if (_routePoints.isNotEmpty)
                    PolylineLayer(
                      polylines: [
                        Polyline(
                          points: _routePoints,
                          color: Colors.blue,
                          strokeWidth: 5,
                        ),
                      ],
                    ),
                  MarkerLayer(markers: markers),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
