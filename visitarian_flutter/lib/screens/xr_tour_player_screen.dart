import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:panorama_viewer/panorama_viewer.dart';

enum _ViewMode { embedded, normalFullscreen, vrCardboard }

class XrTourPlayerScreen extends StatefulWidget {
  final String tourId;
  final String? placeTitle;
  final bool showEntryFlow;

  const XrTourPlayerScreen({
    super.key,
    required this.tourId,
    this.placeTitle,
    this.showEntryFlow = true,
  });

  @override
  State<XrTourPlayerScreen> createState() => _XrTourPlayerScreenState();
}

class _XrTourPlayerScreenState extends State<XrTourPlayerScreen> {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  bool _loading = true;
  bool _gyroEnabled = true;
  bool _resolvingPanoUrl = false;
  String? _error;
  String? _startNodeId;
  String? _currentNodeId;
  String? _resolvedPanoUrl;
  Map<String, dynamic>? _currentNodeData;
  bool _showIntroOverlay = true;
  bool _showSafetyWarning = false;
  int _panoResolveToken = 0;
  String? _activeInfoTitle;
  String? _activeInfoText;
  _ViewMode _viewMode = _ViewMode.embedded;
  double _currentViewLongitude = 0;
  double _currentViewLatitude = 0;
  Timer? _gazeTicker;
  String? _gazeTargetKey;
  double _gazeProgress = 0;
  DateTime _gazeCooldownUntil = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void initState() {
    super.initState();
    _showIntroOverlay = widget.showEntryFlow;
    _applySystemUiForCurrentState();
    _loadTourStart();
  }

  @override
  void dispose() {
    _gazeTicker?.cancel();
    _restoreSystemUiDefaults();
    super.dispose();
  }

  bool get _isVrCardboardActive =>
      _viewMode == _ViewMode.vrCardboard && !_showIntroOverlay;
  bool get _isNormalFullscreenActive =>
      _viewMode == _ViewMode.normalFullscreen && !_showIntroOverlay;
  bool get _isImmersiveActive =>
      _isVrCardboardActive || _isNormalFullscreenActive;
  bool get _supportsVrCardboard {
    if (kIsWeb) return false;
    return defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
  }

  Future<void> _applySystemUiForCurrentState() async {
    if (kIsWeb) return;
    if (_isVrCardboardActive) {
      await SystemChrome.setPreferredOrientations(const [
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      return;
    }
    if (_isNormalFullscreenActive) {
      await SystemChrome.setPreferredOrientations(DeviceOrientation.values);
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      return;
    }
    await SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }

  Future<void> _restoreSystemUiDefaults() async {
    if (kIsWeb) return;
    await SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }

  void _setViewMode(_ViewMode mode) {
    if (!mounted) return;
    setState(() {
      _viewMode = mode;
      if (mode == _ViewMode.vrCardboard) {
        _gyroEnabled = true;
      }
      _resetGazeTracking();
    });
    _applySystemUiForCurrentState();
  }

  void _resetGazeTracking() {
    _gazeTicker?.cancel();
    _gazeTicker = null;
    _gazeTargetKey = null;
    _gazeProgress = 0;
  }

  Future<void> _loadTourStart() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final tourDoc = await _db.collection('tours').doc(widget.tourId).get();
      if (!tourDoc.exists) {
        throw Exception('Tour does not exist.');
      }

      var startNodeId = (tourDoc.data()?['startNodeId'] ?? '')
          .toString()
          .trim();

      final nodesRef = _db
          .collection('tours')
          .doc(widget.tourId)
          .collection('nodes');

      if (startNodeId.isNotEmpty) {
        final startNodeDoc = await nodesRef.doc(startNodeId).get();
        if (!startNodeDoc.exists) {
          startNodeId = '';
        }
      }

      if (startNodeId.isEmpty) {
        // Prefer the most recently updated node when metadata is available.
        try {
          final latestNodeSnapshot = await nodesRef
              .orderBy('updatedAt', descending: true)
              .limit(1)
              .get();
          if (latestNodeSnapshot.docs.isNotEmpty) {
            startNodeId = latestNodeSnapshot.docs.first.id;
          }
        } catch (_) {
          // Fallback below handles nodes without sortable metadata.
        }
      }

      if (startNodeId.isEmpty) {
        // Final fallback: pick any available node, even if updatedAt is missing.
        final anyNodeSnapshot = await nodesRef.limit(1).get();
        if (anyNodeSnapshot.docs.isNotEmpty) {
          startNodeId = anyNodeSnapshot.docs.first.id;
        }
      }

      if (startNodeId.isEmpty) {
        throw Exception('No nodes found in this tour.');
      }

      _startNodeId = startNodeId;
      await _loadNode(startNodeId);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _loadNode(String nodeId) async {
    try {
      final nodeDoc = await _db
          .collection('tours')
          .doc(widget.tourId)
          .collection('nodes')
          .doc(nodeId)
          .get();

      if (!nodeDoc.exists) {
        throw Exception('Node not found: $nodeId');
      }

      if (!mounted) return;
      setState(() {
        _currentNodeId = nodeDoc.id;
        _currentNodeData = nodeDoc.data();
        _loading = false;
        _error = null;
        _resolvedPanoUrl = null;
        _resolvingPanoUrl = false;
        _activeInfoTitle = null;
        _activeInfoText = null;
        _resetGazeTracking();
      });

      final rawPanoUrl = (_currentNodeData?['panoUrl'] ?? '').toString().trim();
      final token = ++_panoResolveToken;
      await _resolvePanoramaUrl(
        rawPanoUrl,
        expectedNodeId: nodeDoc.id,
        token: token,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Failed to open node: $e';
      });
    }
  }

  Future<void> _resolvePanoramaUrl(
    String rawUrl, {
    required String expectedNodeId,
    required int token,
  }) async {
    if (!mounted || token != _panoResolveToken) return;
    setState(() {
      _resolvingPanoUrl = true;
      _resolvedPanoUrl = null;
    });

    final trimmed = rawUrl.trim();
    if (trimmed.isEmpty) {
      if (!mounted ||
          token != _panoResolveToken ||
          _currentNodeId != expectedNodeId) {
        return;
      }
      setState(() {
        _resolvingPanoUrl = false;
      });
      return;
    }

    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      if (!mounted ||
          token != _panoResolveToken ||
          _currentNodeId != expectedNodeId) {
        return;
      }
      setState(() {
        _resolvedPanoUrl = trimmed;
        _resolvingPanoUrl = false;
      });
      return;
    }

    if (trimmed.startsWith('gs://')) {
      try {
        final downloadUrl = await FirebaseStorage.instance
            .refFromURL(trimmed)
            .getDownloadURL();
        if (!mounted ||
            token != _panoResolveToken ||
            _currentNodeId != expectedNodeId) {
          return;
        }
        setState(() {
          _resolvedPanoUrl = downloadUrl;
          _resolvingPanoUrl = false;
        });
        return;
      } catch (_) {
        // Fall through to path-based resolution.
      }
    }

    try {
      final downloadUrl = await FirebaseStorage.instance
          .ref()
          .child(trimmed)
          .getDownloadURL();
      if (!mounted ||
          token != _panoResolveToken ||
          _currentNodeId != expectedNodeId) {
        return;
      }
      setState(() {
        _resolvedPanoUrl = downloadUrl;
        _resolvingPanoUrl = false;
      });
      return;
    } catch (_) {
      // Keep invalid URL state below.
    }

    if (!mounted ||
        token != _panoResolveToken ||
        _currentNodeId != expectedNodeId) {
      return;
    }
    setState(() {
      _resolvingPanoUrl = false;
    });
  }

  List<_RuntimeHotspot> _parseHotspots() {
    final rawList =
        (_currentNodeData?['hotspots'] as List<dynamic>? ?? const []);

    return rawList
        .map((item) {
          if (item is Map<String, dynamic>) return item;
          if (item is Map) return Map<String, dynamic>.from(item);
          return null;
        })
        .whereType<Map<String, dynamic>>()
        .map(_RuntimeHotspot.fromMap)
        .toList();
  }

  Future<void> _onHotspotTap(_RuntimeHotspot hotspot) async {
    if (hotspot.type == 'teleport') {
      final toNodeId = (hotspot.toNodeId ?? '').trim();
      if (toNodeId.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Teleport hotspot has no target node.')),
        );
        return;
      }
      await _loadNode(toNodeId);
      return;
    }

    final title = hotspot.title?.trim().isNotEmpty == true
        ? hotspot.title!.trim()
        : 'Information';
    final text = hotspot.text?.trim().isNotEmpty == true
        ? hotspot.text!.trim()
        : 'No description provided.';

    if (!mounted) return;
    setState(() {
      _activeInfoTitle = title;
      _activeInfoText = text;
    });
  }

  String _hotspotKey(_RuntimeHotspot hotspot, int index) {
    return '$index|${hotspot.type}|${hotspot.toNodeId ?? ''}|${hotspot.title ?? ''}';
  }

  double _yawDelta(double a, double b) {
    return ((a - b + 540) % 360) - 180;
  }

  _RuntimeHotspot? _findNearestGazeTarget(List<_RuntimeHotspot> hotspots) {
    if (hotspots.isEmpty) return null;
    _RuntimeHotspot? best;
    var bestScore = double.infinity;

    for (final hotspot in hotspots) {
      if (!hotspot.yaw.isFinite || !hotspot.pitch.isFinite) continue;
      final yawDiff = _yawDelta(hotspot.yaw, _currentViewLongitude).abs();
      final pitchDiff = (hotspot.pitch - _currentViewLatitude).abs();
      final score = yawDiff + pitchDiff;
      if (score < bestScore) {
        bestScore = score;
        best = hotspot;
      }
    }

    if (best == null) return null;
    return bestScore <= 15.0 ? best : null;
  }

  void _updateGazeTarget(List<_RuntimeHotspot> hotspots) {
    if (!_isVrCardboardActive || _showSafetyWarning || _showIntroOverlay) {
      _resetGazeTracking();
      return;
    }
    if (DateTime.now().isBefore(_gazeCooldownUntil)) {
      return;
    }

    final target = _findNearestGazeTarget(hotspots);
    if (target == null) {
      if (_gazeTargetKey != null || _gazeProgress != 0) {
        setState(() {
          _gazeTargetKey = null;
          _gazeProgress = 0;
        });
      }
      _gazeTicker?.cancel();
      _gazeTicker = null;
      return;
    }

    final targetIndex = hotspots.indexOf(target);
    final targetKey = _hotspotKey(target, targetIndex);
    if (_gazeTargetKey != targetKey) {
      _gazeTicker?.cancel();
      setState(() {
        _gazeTargetKey = targetKey;
        _gazeProgress = 0;
      });
      _gazeTicker = Timer.periodic(const Duration(milliseconds: 60), (
        timer,
      ) async {
        if (!mounted || _gazeTargetKey != targetKey || !_isVrCardboardActive) {
          timer.cancel();
          return;
        }
        final next = (_gazeProgress + 0.05).clamp(0.0, 1.0);
        setState(() {
          _gazeProgress = next;
        });
        if (next >= 1.0) {
          timer.cancel();
          _gazeCooldownUntil = DateTime.now().add(
            const Duration(milliseconds: 900),
          );
          await _onHotspotTap(target);
          if (!mounted) return;
          setState(() {
            _gazeProgress = 0;
          });
        }
      });
    }
  }

  void _onSwipeUpToEnter() {
    if (!_supportsVrCardboard) return;
    if (_showSafetyWarning) return;
    _setViewMode(_ViewMode.vrCardboard);
    setState(() {
      _gyroEnabled = true;
      _showSafetyWarning = true;
    });
  }

  void _enterScreenMode() {
    _setViewMode(_ViewMode.normalFullscreen);
    setState(() {
      _gyroEnabled = false;
      _showSafetyWarning = false;
      _showIntroOverlay = false;
    });
    _applySystemUiForCurrentState();
  }

  void _enterVrMode() {
    if (!_supportsVrCardboard) return;
    if (_showSafetyWarning) return;
    _setViewMode(_ViewMode.vrCardboard);
    setState(() {
      _gyroEnabled = true;
      _showSafetyWarning = true;
    });
  }

  Widget _buildEntryOverlay(String title) {
    return Positioned.fill(
      child: GestureDetector(
        onVerticalDragEnd: (details) {
          final velocity = details.primaryVelocity ?? 0;
          if (velocity < -300) {
            _onSwipeUpToEnter();
          }
        },
        child: Container(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
          color: Colors.black.withValues(alpha: 0.35),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Explore the beauty of',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 44,
                  fontWeight: FontWeight.w800,
                  height: 1.05,
                ),
              ),
              const Spacer(),
              const Text(
                'Choose View Mode',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 38,
                  fontWeight: FontWeight.w800,
                  height: 1.0,
                ),
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _supportsVrCardboard ? _enterVrMode : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2C8D5B),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  icon: const Icon(Icons.vrpano),
                  label: const Text(
                    'VR Mode',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
              if (!_supportsVrCardboard)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text(
                    'VR mode is only available on Android/iOS devices.',
                    style: TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _enterScreenMode,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Colors.white70),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  icon: const Icon(Icons.smartphone),
                  label: const Text(
                    'Screen / Normal Mode',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              const Center(
                child: Text(
                  'VR mode shows safety warning first',
                  style: TextStyle(color: Colors.white70),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSafetyWarningOverlay() {
    if (!_showSafetyWarning) {
      return const SizedBox.shrink();
    }

    return Positioned.fill(
      child: Container(
        color: Colors.black.withValues(alpha: 0.45),
        alignment: Alignment.center,
        padding: const EdgeInsets.all(20),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 420),
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.65),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFF0FC1FF), width: 1.2),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'WARNING!',
                style: TextStyle(
                  color: Color(0xFF1CC848),
                  fontSize: 34,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'This mobile virtual reality nature experience limits your awareness of your real-world surroundings. '
                'Use only in a safe, open area free of obstacles, edges, water, or traffic. Remain seated or stationary '
                'while wearing the headset, and remove it before walking or moving. Take regular breaks to prevent '
                'dizziness or discomfort. Children should be supervised at all times. Remember, while the environment may '
                'be virtual, real-world hazards still exist.',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  height: 1.4,
                  fontWeight: FontWeight.w600,
                ),
                textAlign: TextAlign.justify,
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  TextButton(
                    onPressed: () {
                      setState(() {
                        _showSafetyWarning = false;
                        _showIntroOverlay = false;
                        _viewMode = _ViewMode.vrCardboard;
                      });
                      _applySystemUiForCurrentState();
                    },
                    child: const Text(
                      'OK',
                      style: TextStyle(
                        color: Color(0xFF1CC848),
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  TextButton(
                    onPressed: () {
                      setState(() {
                        _showSafetyWarning = false;
                        _viewMode = _ViewMode.embedded;
                      });
                      _applySystemUiForCurrentState();
                    },
                    child: const Text(
                      'BACK',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoOverlay() {
    final title = _activeInfoTitle;
    final text = _activeInfoText;
    if (title == null ||
        text == null ||
        _showIntroOverlay ||
        _showSafetyWarning) {
      return const SizedBox.shrink();
    }

    return Positioned(
      left: 14,
      right: 14,
      bottom: 14,
      child: Material(
        color: Colors.transparent,
        child: Container(
          constraints: const BoxConstraints(maxHeight: 220),
          padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.72),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        text,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                tooltip: 'Close',
                onPressed: () {
                  setState(() {
                    _activeInfoTitle = null;
                    _activeInfoText = null;
                  });
                },
                icon: const Icon(Icons.close, color: Colors.white),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Hotspot> _buildPanoramaHotspots(List<_RuntimeHotspot> hotspots) {
    return hotspots
        .asMap()
        .entries
        .map((entry) {
          final index = entry.key;
          final hotspot = entry.value;
          final markerColor = hotspot.type == 'teleport'
              ? Colors.orange
              : Colors.lightBlueAccent;
          final rawLatitude = hotspot.pitch;
          final rawLongitude = hotspot.yaw;

          if (!rawLatitude.isFinite || !rawLongitude.isFinite) {
            return null;
          }

          final latitude = rawLatitude.clamp(-90.0, 90.0).toDouble();
          final longitude = rawLongitude.clamp(-180.0, 180.0).toDouble();
          if (!latitude.isFinite || !longitude.isFinite) {
            return null;
          }

          return Hotspot(
            latitude: latitude,
            longitude: longitude,
            width: 32,
            height: 32,
            widget: GestureDetector(
              onTap: () => _onHotspotTap(hotspot),
              child: Container(
                width: 28,
                height: 28,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: markerColor,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black38,
                      blurRadius: 6,
                      offset: Offset(0, 2),
                    ),
                  ],
                ),
                child: Text(
                  '${index + 1}',
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: Colors.black,
                  ),
                ),
              ),
            ),
          );
        })
        .whereType<Hotspot>()
        .toList();
  }

  Widget _buildPanorama(
    String panoUrl,
    List<_RuntimeHotspot> hotspots, {
    required bool showHotspots,
    required bool interactive,
    SensorControl? sensorControlOverride,
    Function(double longitude, double latitude, double tilt)? onViewChanged,
  }) {
    if (_resolvingPanoUrl) {
      return const ColoredBox(
        color: Colors.black54,
        child: Center(child: CircularProgressIndicator()),
      );
    }

    final hasUrl =
        panoUrl.startsWith('http://') || panoUrl.startsWith('https://');

    if (!hasUrl) {
      return ColoredBox(
        color: Colors.black54,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'Panorama URL missing or invalid.\n$panoUrl',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white),
            ),
          ),
        ),
      );
    }

    final sensorControl =
        sensorControlOverride ??
        ((!kIsWeb && _gyroEnabled)
            ? SensorControl.orientation
            : SensorControl.none);

    return PanoramaViewer(
      interactive: interactive,
      sensorControl: sensorControl,
      minZoom: 1,
      maxZoom: 5,
      hotspots: showHotspots ? _buildPanoramaHotspots(hotspots) : null,
      onViewChanged: onViewChanged,
      child: Image.network(
        panoUrl,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) {
          return const ColoredBox(
            color: Colors.black54,
            child: Center(
              child: Text(
                'Failed to load panorama image.',
                style: TextStyle(color: Colors.white),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildPanoramaWithTransition(
    String panoUrl,
    List<_RuntimeHotspot> hotspots, {
    required bool showHotspots,
    required bool interactive,
    SensorControl? sensorControlOverride,
    Function(double longitude, double latitude, double tilt)? onViewChanged,
  }) {
    final transitionKey = ValueKey<String>(
      '${_currentNodeId ?? ''}|${_resolvedPanoUrl ?? panoUrl}',
    );

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 350),
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      transitionBuilder: (child, animation) =>
          FadeTransition(opacity: animation, child: child),
      child: KeyedSubtree(
        key: transitionKey,
        child: _buildPanorama(
          panoUrl,
          hotspots,
          showHotspots: showHotspots,
          interactive: interactive,
          sensorControlOverride: sensorControlOverride,
          onViewChanged: onViewChanged,
        ),
      ),
    );
  }

  Widget _buildVrReticle() {
    return IgnorePointer(
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 42,
              height: 42,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  CircularProgressIndicator(
                    value: _gazeProgress,
                    strokeWidth: 3,
                    backgroundColor: Colors.white24,
                    valueColor: const AlwaysStoppedAnimation<Color>(
                      Colors.lightGreenAccent,
                    ),
                  ),
                  Container(
                    width: 10,
                    height: 10,
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.45),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Text(
                'Focus to activate hotspot',
                style: TextStyle(color: Colors.white, fontSize: 11),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVrCardboardPanorama(
    String panoUrl,
    List<_RuntimeHotspot> hotspots,
  ) {
    void onViewChanged(double longitude, double latitude, double tilt) {
      if (!mounted) return;
      _currentViewLongitude = longitude;
      _currentViewLatitude = latitude;
      _updateGazeTarget(hotspots);
    }

    return Row(
      children: [
        Expanded(
          child: ClipRect(
            child: _buildPanoramaWithTransition(
              panoUrl,
              hotspots,
              showHotspots: true,
              interactive: false,
              sensorControlOverride: kIsWeb
                  ? SensorControl.none
                  : SensorControl.orientation,
              onViewChanged: onViewChanged,
            ),
          ),
        ),
        Container(width: 2, color: Colors.black.withValues(alpha: 0.65)),
        Expanded(
          child: ClipRect(
            child: _buildPanoramaWithTransition(
              panoUrl,
              hotspots,
              showHotspots: true,
              interactive: false,
              sensorControlOverride: kIsWeb
                  ? SensorControl.none
                  : SensorControl.orientation,
              onViewChanged: onViewChanged,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTourView() {
    final isVrCardboard = _isVrCardboardActive;
    final isNormalFullscreen = _isNormalFullscreenActive;
    final isFullscreen = isVrCardboard || isNormalFullscreen;
    final nodeName = (_currentNodeData?['name'] ?? '').toString();
    final rawPanoUrl = (_currentNodeData?['panoUrl'] ?? '').toString().trim();
    final panoUrl = _resolvedPanoUrl ?? rawPanoUrl;
    final hotspots = _parseHotspots();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!isFullscreen)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.placeTitle?.trim().isNotEmpty == true
                      ? widget.placeTitle!
                      : 'XR Tour',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 4),
                Text(
                  'Node: ${nodeName.isEmpty ? _currentNodeId ?? '' : nodeName}',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                if (rawPanoUrl.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 4),
                    child: Text(
                      'This node has no panorama URL yet.',
                      style: TextStyle(color: Colors.redAccent),
                    ),
                  ),
                const SizedBox(height: 4),
                Text(
                  !kIsWeb
                      ? 'Drag to look. Move your phone for gyro.'
                      : 'Drag to look. Gyro is disabled on web.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        Expanded(
          child: isVrCardboard
              ? SizedBox.expand(
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: _buildVrCardboardPanorama(panoUrl, hotspots),
                      ),
                      _buildVrReticle(),
                      Positioned(
                        top: 10,
                        right: 10,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.45),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: IconButton(
                            icon: const Icon(Icons.close, color: Colors.white),
                            onPressed: () {
                              setState(() {
                                _showIntroOverlay = true;
                                _showSafetyWarning = false;
                                _viewMode = _ViewMode.embedded;
                                _gyroEnabled = false;
                                _resetGazeTracking();
                              });
                              _applySystemUiForCurrentState();
                            },
                          ),
                        ),
                      ),
                      if (_showIntroOverlay)
                        _buildEntryOverlay(widget.placeTitle ?? 'Destination'),
                      _buildSafetyWarningOverlay(),
                      _buildInfoOverlay(),
                    ],
                  ),
                )
              : isNormalFullscreen
              ? SizedBox.expand(
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: _buildPanoramaWithTransition(
                          panoUrl,
                          hotspots,
                          showHotspots: true,
                          interactive: true,
                        ),
                      ),
                      Positioned(
                        top: 10,
                        right: 10,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            DecoratedBox(
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.45),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const SizedBox(width: 8),
                                  const Icon(
                                    Icons.screen_rotation,
                                    color: Colors.white,
                                    size: 18,
                                  ),
                                  Switch(
                                    value: !kIsWeb && _gyroEnabled,
                                    onChanged: kIsWeb
                                        ? null
                                        : (value) {
                                            setState(() {
                                              _gyroEnabled = value;
                                            });
                                          },
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            DecoratedBox(
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.45),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: IconButton(
                                icon: const Icon(
                                  Icons.close,
                                  color: Colors.white,
                                ),
                                onPressed: () {
                                  setState(() {
                                    _showIntroOverlay = true;
                                    _showSafetyWarning = false;
                                    _viewMode = _ViewMode.embedded;
                                  });
                                  _applySystemUiForCurrentState();
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (_showIntroOverlay)
                        _buildEntryOverlay(widget.placeTitle ?? 'Destination'),
                      _buildSafetyWarningOverlay(),
                      _buildInfoOverlay(),
                    ],
                  ),
                )
              : Padding(
                  padding: const EdgeInsets.all(16),
                  child: Container(
                    width: double.infinity,
                    height: double.infinity,
                    decoration: BoxDecoration(
                      color: Colors.black,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: Stack(
                        children: [
                          Positioned.fill(
                            child: _buildPanoramaWithTransition(
                              panoUrl,
                              hotspots,
                              showHotspots: true,
                              interactive: true,
                            ),
                          ),
                          Positioned(
                            top: 10,
                            right: 10,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.45),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const SizedBox(width: 8),
                                  const Icon(
                                    Icons.screen_rotation,
                                    color: Colors.white,
                                    size: 18,
                                  ),
                                  Switch(
                                    value: !kIsWeb && _gyroEnabled,
                                    onChanged: kIsWeb
                                        ? null
                                        : (value) {
                                            setState(() {
                                              _gyroEnabled = value;
                                            });
                                          },
                                  ),
                                ],
                              ),
                            ),
                          ),
                          if (_showIntroOverlay)
                            _buildEntryOverlay(
                              widget.placeTitle ?? 'Destination',
                            ),
                          _buildSafetyWarningOverlay(),
                          _buildInfoOverlay(),
                        ],
                      ),
                    ),
                  ),
                ),
        ),
        if (!isFullscreen && !_showIntroOverlay && hotspots.isNotEmpty)
          SizedBox(
            height: 64,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              scrollDirection: Axis.horizontal,
              itemCount: hotspots.length,
              separatorBuilder: (context, index) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final hotspot = hotspots[index];
                return ActionChip(
                  avatar: Icon(
                    hotspot.type == 'teleport'
                        ? Icons.open_in_new
                        : Icons.info_outline,
                    size: 16,
                  ),
                  label: Text(
                    hotspot.type == 'teleport'
                        ? (hotspot.label?.isNotEmpty == true
                              ? hotspot.label!
                              : 'Teleport ${index + 1}')
                        : (hotspot.title?.isNotEmpty == true
                              ? hotspot.title!
                              : 'Info ${index + 1}'),
                  ),
                  onPressed: () => _onHotspotTap(hotspot),
                );
              },
            ),
          ),
        if (!isFullscreen)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Row(
              children: [
                if (!_showIntroOverlay &&
                    _startNodeId != null &&
                    _currentNodeId != _startNodeId)
                  OutlinedButton.icon(
                    onPressed: () => _loadNode(_startNodeId!),
                    icon: const Icon(Icons.first_page),
                    label: const Text('Back to Start'),
                  ),
                const Spacer(),
                Text(
                  'Tap markers to interact',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final isFullScreen = _isImmersiveActive;

    return Scaffold(
      appBar: isFullScreen
          ? null
          : AppBar(
              title: Text(
                widget.placeTitle?.trim().isNotEmpty == true
                    ? widget.placeTitle!
                    : 'XR Tour',
              ),
            ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Unable to open tour\n$_error',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    ElevatedButton(
                      onPressed: _loadTourStart,
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            )
          : _buildTourView(),
    );
  }
}

class _RuntimeHotspot {
  final String type;
  final double yaw;
  final double pitch;
  final String? title;
  final String? text;
  final String? toNodeId;
  final String? label;

  const _RuntimeHotspot({
    required this.type,
    required this.yaw,
    required this.pitch,
    this.title,
    this.text,
    this.toNodeId,
    this.label,
  });

  factory _RuntimeHotspot.fromMap(Map<String, dynamic> map) {
    double readFiniteDouble(dynamic value) {
      final number = value is num
          ? value.toDouble()
          : double.tryParse('$value');
      if (number == null || !number.isFinite) return 0.0;
      return number;
    }

    return _RuntimeHotspot(
      type: (map['type'] ?? '').toString(),
      yaw: readFiniteDouble(map['yaw']),
      pitch: readFiniteDouble(map['pitch']),
      title: map['title']?.toString(),
      text: map['text']?.toString(),
      toNodeId: map['toNodeId']?.toString(),
      label: map['label']?.toString(),
    );
  }
}
