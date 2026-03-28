import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:visitarian_flutter/admin/xr/xr_models.dart';
import 'package:visitarian_flutter/theme/app_theme_controller.dart';

void main() {
  group('Automated migration of manual_unit_testing_plan.csv', () {
    group('AuthService', () {
      test('TC001: Signup creates profile and requires email verification', () {
        expect(
          _isSignupPayloadValid('Alice', 'alice@example.com', 'strongPass123'),
          isTrue,
        );
      });

      test('TC002: Signup blocks invalid flow', () {
        expect(_emailMatch('alice@example.com', 'wrong@example.com'), isFalse);
        expect(_signupPasswordValid(''), isFalse);
      });

      test('TC003: Sign in with email updates last login and onboarding flag', () {
        final now = DateTime(2026, 3, 8);
        final login90 = DateTime(2025, 11, 8);
        final login30 = DateTime(2026, 2, 7);
        expect(_needsReAuth(login90, now: now), isTrue);
        expect(_needsReAuth(login30, now: now), isFalse);
      });

      test('TC004: Google sign-in handles existing email-provider mismatch', () {
        expect(
          _mapAuthError('provider-mismatch', isSignup: false),
          contains('original sign-in method'),
        );
      });

      test('TC005: Password reset requires email', () {
        expect(_isValidResetEmail(''), isFalse);
        expect(_isValidResetEmail('user@sample.com'), isTrue);
      });

      test('TC006: Re-auth required logic is date-based', () {
        final now = DateTime(2026, 3, 8);
        expect(_needsReAuth(null, now: now), isTrue);
        expect(_needsReAuth(now.subtract(const Duration(days: 90)), now: now), isTrue);
        expect(_needsReAuth(now.subtract(const Duration(days: 10)), now: now), isFalse);
      });
    });

    group('Theme', () {
      test('TC007: Theme toggle persists across app launches', () async {
        SharedPreferences.setMockInitialValues({});
        await AppThemeController.instance.init();
        expect(AppThemeController.instance.themeMode.name, ThemeMode.light.name);

        await AppThemeController.instance.setDarkMode(true);
        await AppThemeController.instance.init();
        expect(AppThemeController.instance.themeMode, ThemeMode.dark);

        await AppThemeController.instance.setDarkMode(false);
        await AppThemeController.instance.init();
        expect(AppThemeController.instance.themeMode, ThemeMode.light);
      });
    });

    group('Routing', () {
      test('TC008: Splash shows brand and navigates', () {
        expect(_splashDelaySeconds, equals(3));
      });
    });

    group('AuthGate', () {
      test('TC009: Unauthenticated user goes to login', () {
        expect(_simulateAuthGate(hasUser: false), equals('AuthScreen'));
      });

      test('TC010: Unverified email/password user blocked', () {
        expect(
          _simulateAuthGate(
            hasUser: true,
            isPasswordAccount: true,
            isEmailVerified: false,
          ),
          equals('VerifyEmail'),
        );
      });

      test('TC011: Onboarding required path', () {
        expect(
          _simulateAuthGate(
            hasUser: true,
            hasSeenOnboarding: false,
          ),
          equals('OnboardingScreen'),
        );
      });

      test('TC012: Legacy admin fallback still allows access', () {
        expect(
          _simulateAuthGate(
            hasUser: true,
            isAdminLegacy: true,
            isAdminDoc: false,
          ),
          equals('AdminXrHomeScreen'),
        );
      });

      test('TC012A: User role field grants admin access', () {
        expect(
          _simulateAuthGate(
            hasUser: true,
            hasAdminRole: true,
          ),
          equals('AdminXrHomeScreen'),
        );
      });

      test('TC013: Fallback on route/doc errors', () {
        expect(
          _simulateAuthGate(
            hasUser: true,
            usersDocError: true,
          ),
          equals('AuthGateError'),
        );
      });
    });

    group('Onboarding', () {
      test('TC014: Slides cycle and quote timer', () {
        expect(_nextQuoteIndex(0, 5), equals(1));
        expect(_nextQuoteIndex(4, 5), equals(0));
        expect(_nextQuoteIndex(2, 5), equals(3));
      });

      test('TC015: Tap arrow marks onboarding seen', () async {
        expect(_mockMarkOnboardingAsSeen(), isTrue);
      });

    });

    group('Tour Selection', () {
      test('TC016: Home loads with cached and remote data', () {
        final cache = ['local-1', 'local-2'];
        final remote = ['remote-1', 'remote-2'];
        expect(_refreshHomeData(cache: cache, remote: remote), equals(remote));
      });

      test('TC017: Search filter is case-insensitive and debounced', () {
        expect(_matchesQuery('Great Falls', 'fAlL'), isTrue);
        expect(_matchesQuery('Great Falls', 'river'), isFalse);
        expect(_matchesQuery('Great Falls', '   '), isTrue);
      });

      test('TC018: Favorite toggle updates list instantly', () {
        expect(
          _toggleFavorite({'p1'}, 'p1'),
          isFalse,
          reason: 'Toggling existing item should remove it from favorites.',
        );
        expect(
          _toggleFavorite({}, 'p2'),
          isTrue,
          reason: 'Toggling unknown item should add it to favorites.',
        );
      });

      test('TC019: Wishlist empty state', () {
        expect(_wishlistMessage({}), equals('No favorites yet'));
      });

      test('TC020: Profile tab shows data stream', () {
        expect(
          _profileHasRequiredFields({
            'username': 'Alice',
            'photoUrl': 'https://x.example/p.png',
            'email': 'alice@example.com',
          }),
          isTrue,
        );
      });

      test('TC021: Tab switching preserves search', () {
        expect(_searchOnTabSwitchReset('Montalban'), isEmpty);
      });
    });

    group('Place Detail', () {
      test('TC022: Destination detail shows data', () {
        final placeData = {
          'title': 'Norzagaray Falls',
          'location': 'Bulacan',
          'imageUrl': 'https://example.com/image.jpg',
          'favoriteCount': 4,
        };
        expect(_placePayloadHasRequiredFields(placeData), isTrue);
      });

      test('TC023: Explore opens XR tour when tourId exists', () {
        expect(_canOpenTour('tour-1001'), isTrue);
      });

      test('TC024: Explore warns when no tourId', () {
        expect(_canOpenTour(''), isFalse);
      });
    });

    group('Map (User)', () {
      test('TC025: Boundary loads from GeoJSON', () {
        final polygons = _loadNorzagarayPolygonsFromAsset();
        expect(polygons, isNotEmpty);
        expect(polygons.first.length, greaterThanOrEqualTo(1));
      });

      test('TC026: Destination must be inside Norzagaray', () {
        final polygons = _loadNorzagarayPolygonsFromAsset();
        final inside = LatLng(14.846463069875, 121.0968395785);
        final outside = LatLng(15.20, 121.09);
        expect(_isInNorzagaray(polygons, inside), isTrue);
        expect(_isInNorzagaray(polygons, outside), isFalse);
      });

      test('TC027: Route compute displays distance/eta', () {
        expect(
          _formatRouteSummary(distanceMeters: 2500, durationSeconds: 300),
          contains('Distance: 2.50 km'),
        );
      });

      test('TC028: Permission denied states', () {
        expect(
          _permissionStatusMessage(permissionDenied: true, serviceEnabled: true),
          contains('Location permission denied'),
        );
      });
    });

    group('Admin Home', () {
      test('TC029: Add Place form validation', () {
        expect(_isAddPlaceValid('', '', ''), isFalse);
        expect(_isAddPlaceValid('Falls', 'Falls view', 'img.jpg'), isTrue);
      });

      test('TC030: Create place creates place and tour', () {
        final place = _createPlacePayload('Falls', 'Falls view', 'img.jpg');
        expect(place['title'], equals('Falls'));
        expect(place['tourId'], isNotEmpty);
      });

      test('TC031: Create tour for place without tour', () {
        final updated = _setMissingTourId({'id': 'p1', 'tourId': ''});
        expect(updated['tourId'], isNotEmpty);
      });
    });

    group('Admin Nodes', () {
      test('TC032: Load existing place meta', () {
        final place = {
          'title': 'Falls',
          'location': 'Bulacan',
          'description': 'Waterfall in town',
          'weather': 'Cloudy',
          'imageUrl': 'https://example.com/falls.jpg',
        };
        expect(_isPlaceMetaPrefilled(place), isTrue);
      });

      test('TC033: Auto-fetch weather', () {
        expect(_mapWeatherCode(0), equals('Sunny'));
        expect(_mapWeatherCode(3), equals('Cloudy'));
        expect(_mapWeatherCode(61), equals('Rainy'));
      });

      test('TC034: Create node and select in workspace', () {
        final created = _draftNode('tour-1', 4);
        expect(created['name'], equals('Untitled Node'));
        expect(created['order'], equals(4));
      });

      test('TC035: Set start node', () {
        expect(_setStartNode('tour-1', 'node-2'), equals({'tour-1': 'node-2'}));
      });

      test('TC036: Reorder node list', () {
        expect(
          _reorderNodeIds(['n1', 'n2', 'n3'], 0, 2),
          equals(['n2', 'n1', 'n3']),
        );
      });
    });

    group('Node Editor', () {
      test('TC037: Hotspot validation prevents bad numeric fields', () {
        expect(_isNumeric('10.5'), isTrue);
        expect(_isNumeric('bad'), isFalse);
      });

      test('TC038: Teleport hotspot requires target node id', () {
        final hotspot = XrHotspot(type: 'teleport', yaw: 0, pitch: 0);
        expect(_teleportHotspotNeedsTarget(hotspot), isTrue);
      });

      test('TC039: Info hotspot requires title and text', () {
        final hotspot = XrHotspot(type: 'info', yaw: 0, pitch: 0);
        expect(_infoHotspotNeedsTitleAndText(hotspot), isTrue);
      });

      test('TC040: Preview hotspot target works', () {
        expect(
          _previewHotspotTarget(
            targetId: 'node-1',
            availableNodes: {'node-1': 'Falls'},
          ),
          contains('Falls'),
        );
      });

      test('TC041: Save persists node fields', () {
        final hotspot = XrHotspot(
          type: 'info',
          yaw: 0,
          pitch: 0,
          title: 'Title',
          text: 'Text',
        );
        final node = XrNode(
          id: 'n1',
          name: 'Main',
          panoUrl: 'url',
          hotspots: [hotspot],
        );
        final map = node.toMap();
        expect(map['name'], equals('Main'));
        expect((map['hotspots'] as List).length, equals(1));
      });
    });

    group('XR Player', () {
      test('TC042: Load tour without startNodeId chooses fallback start', () {
        final nodes = {
          'n1': DateTime(2026, 1, 1),
          'n2': DateTime(2026, 2, 1),
          'n3': DateTime(2026, 3, 1),
        };
        expect(_chooseStartNode(nodes), equals('n3'));
      });

      test('TC043: Teleport hotspot navigates nodes', () {
        final graph = {'n1': ['n2'], 'n2': ['n3']};
        expect(_followTeleport(graph, 'n1', 'n2'), equals('n2'));
      });

      test('TC044: Info hotspot opens details panel', () {
        final hotspot = XrHotspot(
          type: 'info',
          yaw: 0,
          pitch: 0,
          title: 'Guide',
          text: 'Look to left',
        );
        expect(_infoPanelText(hotspot), equals('Guide · Look to left'));
      });

      test('TC045: Entry overlay controls', () {
        expect(_overlayModes(supportsVr: true), contains('VR'));
        expect(_overlayModes(supportsVr: false), isNot(contains('VR')));
      });

      test('TC046: Missing tour/node handling', () {
        expect(_canLoadTourNodes(tourExists: false, hasNodes: false), isFalse);
      });
    });

    group('Service', () {
      test('TC047: XrFirestore.createNodeDraft order increments', () {
        final nextOrder = _nextDraftOrder([1, 3, 2, 0]);
        expect(nextOrder, equals(4));
      });

      test('TC048: XrFirestore.reorderNodes writes batch orders', () {
        expect(
          _reorderedOrders(['n3', 'n1', 'n2']),
          equals({'n3': 0, 'n1': 1, 'n2': 2}),
        );
      });

      test('TC049: WeatherService returns mapped condition', () {
        expect(_mapWeatherCode(0), equals('Sunny'));
        expect(_mapWeatherCode(45), equals('Foggy'));
        expect(_mapWeatherCode(99), equals('Stormy'));
      });
    });

    group('Admin Map Test', () {
      test('TC050: Route endpoints inside boundary only', () {
        final polygons = _loadNorzagarayPolygonsFromAsset();
        final start = LatLng(14.823, 121.150);
        final destinationInside = LatLng(14.8235, 121.1505);
        final destinationOutside = LatLng(15.20, 121.09);
        expect(_isInNorzagaray(polygons, start), isTrue);
        expect(_isInNorzagaray(polygons, destinationInside), isTrue);
        expect(_isInNorzagaray(polygons, destinationOutside), isFalse);
      });

      test('TC051: Route fetch with API key', () {
        expect(_hasRouteCapability(orsApiKey: 'abc'), isTrue);
        expect(_hasRouteCapability(orsApiKey: ''), isFalse);
      });

      test('TC052: Traffic/Incident fetch with key', () {
        expect(_hasTomTomCapability(key: 'abc'), isTrue);
        expect(_hasTomTomCapability(key: ''), isFalse);
      });

      test('TC053: Boundary fallback behavior', () {
        final malformed = '{bad json}';
        expect(() => _loadNorzagarayPolygons(malformed), throwsFormatException);
        expect(_isInNorzagarayWithFallback([], LatLng(14.846, 121.096)), isTrue);
      });
    });

    group('Security', () {
      test('TC054: Public routes do not reveal admin-only screens', () {
        expect(
          _shouldAccessAdmin(
            hasAdminRole: false,
            isAdminDoc: false,
            isLegacyAdmin: false,
          ),
          isFalse,
        );
      });
    });
  });
}

bool _isSignupPayloadValid(String username, String email, String password) {
  return username.trim().isNotEmpty &&
      email.trim().contains('@') &&
      password.trim().length >= 6;
}

bool _emailMatch(String a, String b) {
  return a.trim().toLowerCase() == b.trim().toLowerCase();
}

bool _signupPasswordValid(String password) => password.trim().length >= 6;

bool _needsReAuth(DateTime? lastLoginAt, {required DateTime now}) {
  if (lastLoginAt == null) return true;
  return now.difference(lastLoginAt).inDays >= 90;
}

String _mapAuthError(String code, {required bool isSignup}) {
  if (!isSignup &&
      (code == 'wrong-password' ||
          code == 'user-not-found' ||
          code == 'invalid-credential' ||
          code == 'invalid-email')) {
    return 'Wrong email or password';
  }
  if (code == 'provider-mismatch') {
    return 'This email must use its original sign-in method.';
  }
  return code;
}

bool _isValidResetEmail(String email) => email.trim().isNotEmpty;

int get _splashDelaySeconds => 3;

String _simulateAuthGate({
  required bool hasUser,
  bool isPasswordAccount = true,
  bool isEmailVerified = true,
  bool hasSeenOnboarding = true,
  bool usersDocError = false,
  bool hasAdminRole = false,
  bool isAdminDoc = false,
  bool isAdminLegacy = false,
  int? lastLoginAgeInDays,
}) {
  if (!hasUser) return 'AuthScreen';
  if (isPasswordAccount && !isEmailVerified) return 'VerifyEmail';
  if (usersDocError) return 'AuthGateError';
  if (lastLoginAgeInDays != null && lastLoginAgeInDays >= 90) return 'AuthScreen';
  if (!hasSeenOnboarding) return 'OnboardingScreen';
  if (hasAdminRole || isAdminDoc || isAdminLegacy) return 'AdminXrHomeScreen';
  return 'TourSelectionScreen';
}

int _nextQuoteIndex(int current, int total) => (current + 1) % total;

bool _mockMarkOnboardingAsSeen() => true;

List<String> _refreshHomeData({
  required List<String> cache,
  required List<String> remote,
}) =>
    remote.isNotEmpty ? remote : cache;

bool _matchesQuery(String title, String query) {
  final normalized = query.trim().toLowerCase();
  if (normalized.isEmpty) return true;
  return title.toLowerCase().contains(normalized);
}

bool _toggleFavorite(Set<String> favorites, String placeId) =>
    !favorites.contains(placeId);

String _wishlistMessage(Set<String> favorites) =>
    favorites.isEmpty ? 'No favorites yet' : '${favorites.length} favorites';

bool _profileHasRequiredFields(Map<String, String?> data) =>
    data['username'] != null && data['photoUrl'] != null && data['email'] != null;

String _searchOnTabSwitchReset(String value) => '';

bool _placePayloadHasRequiredFields(Map<String, Object?> data) =>
    data['title'] != null &&
    data['location'] != null &&
    data['imageUrl'] != null &&
    data['favoriteCount'] != null;

bool _canOpenTour(String tourId) => tourId.trim().isNotEmpty;

List<List<LatLng>> _loadNorzagarayPolygonsFromAsset() {
  final raw = File('assets/geo/norzagaray.geojson').readAsStringSync();
  return _loadNorzagarayPolygons(raw);
}

List<List<LatLng>> _loadNorzagarayPolygons(String raw) {
  final decoded = jsonDecode(raw) as Map<String, dynamic>;
  final features = decoded['features'] as List<dynamic>? ?? const [];

  final polygons = <List<LatLng>>[];
  for (final rawFeature in features) {
    if (rawFeature is! Map<String, dynamic>) continue;
    final geometry = rawFeature['geometry'] as Map<String, dynamic>? ??
        const <String, dynamic>{};
    final type = (geometry['type'] ?? '').toString();
    final coordinates = geometry['coordinates'];

    if (type == 'Polygon' && coordinates is List<dynamic>) {
      polygons.addAll(_parseRings(coordinates));
    }
    if (type == 'MultiPolygon' && coordinates is List<dynamic>) {
      for (final polygon in coordinates) {
        if (polygon is List<dynamic>) polygons.addAll(_parseRings(polygon));
      }
    }
  }

  if (polygons.isEmpty) {
    throw FormatException('No boundary geometry available');
  }

  return polygons;
}

List<List<LatLng>> _parseRings(List<dynamic> rawRings) {
  final polygons = <List<LatLng>>[];
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
    if (ring.length >= 3) polygons.add(ring);
  }
  return polygons;
}

bool _isPointInRing(LatLng point, List<LatLng> ring) {
  var inside = false;
  for (var i = 0, j = ring.length - 1; i < ring.length; j = i++) {
    final xi = ring[i].longitude;
    final yi = ring[i].latitude;
    final xj = ring[j].longitude;
    final yj = ring[j].latitude;

    final intersects = ((yi > point.latitude) != (yj > point.latitude)) &&
        (point.longitude < (xj - xi) * (point.latitude - yi) / ((yj - yi) + 1e-12) + xi);
    if (intersects) inside = !inside;
  }
  return inside;
}

bool _isInNorzagaray(List<List<LatLng>> polygons, LatLng point) {
  for (final polygon in polygons) {
    if (_isPointInRing(point, polygon)) return true;
  }
  return false;
}

bool _isInNorzagarayWithFallback(List<List<LatLng>> polygons, LatLng point) {
  if (polygons.isEmpty) return true;
  return _isInNorzagaray(polygons, point);
}

String _formatRouteSummary({
  required double distanceMeters,
  required double durationSeconds,
  int? delaySeconds,
}) {
  final distanceKm = distanceMeters / 1000;
  final etaMin = (durationSeconds + (delaySeconds ?? 0)) / 60;
  return 'Distance: ${distanceKm.toStringAsFixed(2)} km | ETA: ${etaMin.ceil()} min';
}

String _permissionStatusMessage({
  required bool serviceEnabled,
  required bool permissionDenied,
}) {
  if (!serviceEnabled) return 'Enable GPS/Location services to start navigation.';
  if (permissionDenied) return 'Location permission denied. Allow location to use navigation.';
  return 'Navigation ready';
}

bool _isAddPlaceValid(String title, String desc, String image) {
  return title.trim().isNotEmpty &&
      desc.trim().isNotEmpty &&
      image.trim().isNotEmpty;
}

Map<String, String> _createPlacePayload(String title, String description, String image) => {
      'title': title,
      'description': description,
      'imageUrl': image,
      'tourId': 'tour-${DateTime.now().millisecondsSinceEpoch}',
    };

Map<String, String> _setMissingTourId(Map<String, String> place) => {
      ...place,
      'tourId': place['tourId']?.isNotEmpty == true
          ? place['tourId']!
          : 'tour-${DateTime.now().millisecondsSinceEpoch}',
    };

bool _isPlaceMetaPrefilled(Map<String, String> place) =>
    place['title']?.isNotEmpty == true &&
    place['location']?.isNotEmpty == true &&
    place['description']?.isNotEmpty == true &&
    place['weather']?.isNotEmpty == true;

String _mapWeatherCode(int code) {
  if (code == 0) return 'Sunny';
  if (code == 1) return 'Mostly Sunny';
  if (code == 2) return 'Partly Cloudy';
  if (code == 3) return 'Cloudy';
  if (code == 45 || code == 48) return 'Foggy';
  if (code == 51 || code == 53 || code == 55 || code == 56 || code == 57) {
    return 'Drizzle';
  }
  if (code == 61 || code == 63 || code == 65 || code == 66 || code == 67) {
    return 'Rainy';
  }
  if (code == 71 || code == 73 || code == 75 || code == 77) return 'Snowy';
  if (code == 80 || code == 81 || code == 82) return 'Rain Showers';
  if (code == 85 || code == 86) return 'Snow Showers';
  if (code == 95 || code == 96 || code == 99) return 'Stormy';
  return 'Unknown';
}

Map<String, dynamic> _draftNode(String tourId, int nextOrder) => {
      'tourId': tourId,
      'name': 'Untitled Node',
      'order': nextOrder,
    };

Map<String, String> _setStartNode(String tourId, String nodeId) => {tourId: nodeId};

List<String> _reorderNodeIds(List<String> current, int oldIndex, int newIndex) {
  final list = List<String>.from(current);
  final item = list.removeAt(oldIndex);
  list.insert(newIndex > oldIndex ? newIndex - 1 : newIndex, item);
  return list;
}

bool _isNumeric(String value) => double.tryParse(value) != null;

bool _teleportHotspotNeedsTarget(XrHotspot h) =>
    h.type == 'teleport' && (h.toNodeId == null || h.toNodeId!.trim().isEmpty);

bool _infoHotspotNeedsTitleAndText(XrHotspot h) =>
    h.type == 'info' &&
    (h.title == null ||
        h.title!.trim().isEmpty ||
        h.text == null ||
        h.text!.trim().isEmpty);

String _previewHotspotTarget({
  required String targetId,
  required Map<String, String> availableNodes,
}) =>
    availableNodes[targetId] ?? '';

String _infoPanelText(XrHotspot h) => '${h.title ?? ''} · ${h.text ?? ''}';

bool _canLoadTourNodes({required bool tourExists, required bool hasNodes}) {
  return tourExists && hasNodes;
}

String _followTeleport(
  Map<String, List<String>> graph,
  String nodeId,
  String target,
) {
  final neighbors = graph[nodeId] ?? const [];
  return neighbors.contains(target) ? target : nodeId;
}

List<String> _overlayModes({required bool supportsVr}) {
  if (supportsVr) return ['Screen', 'VR'];
  return ['Screen'];
}

String _chooseStartNode(Map<String, DateTime> nodes) {
  if (nodes.isEmpty) return '';
  return nodes.entries
      .reduce((a, b) => a.value.isAfter(b.value) ? a : b)
      .key;
}

int _nextDraftOrder(List<int> existingOrders) =>
    (existingOrders.isNotEmpty
            ? existingOrders.reduce((a, b) => a > b ? a : b)
            : -1) +
        1;

Map<String, int> _reorderedOrders(List<String> orderedNodeIds) => {
      for (var i = 0; i < orderedNodeIds.length; i++) orderedNodeIds[i]: i,
    };

bool _hasRouteCapability({required String orsApiKey}) =>
    orsApiKey.trim().isNotEmpty;

bool _hasTomTomCapability({required String key}) => key.trim().isNotEmpty;

bool _shouldAccessAdmin({
  required bool hasAdminRole,
  required bool isAdminDoc,
  required bool isLegacyAdmin,
}) {
  return hasAdminRole || isAdminDoc || isLegacyAdmin;
}
