import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:panorama_viewer/panorama_viewer.dart';
import 'package:visitarian_flutter/core/services/services.dart';

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
  final AppDistributionService _distribution = AppDistributionService.instance;

  bool _loading = true;
  bool _openingDistributionLink = false;
  bool _gyroEnabled = true;
  bool _resolvingPanoUrl = false;
  String? _error;
  String? _startNodeId;
  String? _currentNodeId;
  String? _resolvedPreviewPanoUrl;
  String? _resolvedPanoUrl;
  bool _highResReady = false;
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
  final Set<String> _prefetchedNodeIds = <String>{};

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
      await SystemChrome.setPreferredOrientations(const [
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
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
        _resolvedPreviewPanoUrl = null;
        _resolvedPanoUrl = null;
        _highResReady = false;
        _resolvingPanoUrl = true;
        _activeInfoTitle = null;
        _activeInfoText = null;
        _resetGazeTracking();
      });

      final hotspots = _parseHotspots();
      unawaited(_prefetchTeleportTargetImages(hotspots));

      final rawPreviewUrl = (_currentNodeData?['previewUrl'] ?? '')
          .toString()
          .trim();
      final rawPanoUrl = (_currentNodeData?['panoUrl'] ?? '').toString().trim();
      final token = ++_panoResolveToken;

      final resolvedPreview = await _resolveRemoteUrl(rawPreviewUrl);
      if (mounted &&
          token == _panoResolveToken &&
          _currentNodeId == nodeDoc.id &&
          resolvedPreview != null) {
        setState(() {
          _resolvedPreviewPanoUrl = resolvedPreview;
        });
        unawaited(
          precacheImage(CachedNetworkImageProvider(resolvedPreview), context),
        );
      }

      final resolvedPano = await _resolveRemoteUrl(rawPanoUrl);
      if (!mounted ||
          token != _panoResolveToken ||
          _currentNodeId != nodeDoc.id) {
        return;
      }
      if (resolvedPano == null) {
        setState(() {
          _resolvingPanoUrl = false;
          _highResReady = false;
        });
        return;
      }

      setState(() {
        _resolvedPanoUrl = resolvedPano;
        _highResReady = true;
        _resolvingPanoUrl = false;
      });

      unawaited(() async {
        try {
          await precacheImage(
            CachedNetworkImageProvider(resolvedPano),
            context,
          );
        } catch (_) {
          // Ignore pre-cache failure; on-screen image load still proceeds.
        }
      }());
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Failed to open node: $e';
      });
    }
  }

  Future<String?> _resolveRemoteUrl(String rawUrl) async {
    final trimmed = rawUrl.trim();
    if (trimmed.isEmpty) {
      return null;
    }

    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      return trimmed;
    }

    if (trimmed.startsWith('gs://')) {
      try {
        return await FirebaseStorage.instance
            .refFromURL(trimmed)
            .getDownloadURL();
      } catch (_) {
        // Fall through to path-based resolution.
      }
    }

    try {
      return await FirebaseStorage.instance
          .ref()
          .child(trimmed)
          .getDownloadURL();
    } catch (_) {
      return null;
    }
  }

  Future<void> _prefetchTeleportTargetImages(
    List<_RuntimeHotspot> hotspots,
  ) async {
    final currentNodeId = _currentNodeId;
    if (currentNodeId == null) return;

    final targetIds = hotspots
        .where((hotspot) => hotspot.type == 'teleport')
        .map((hotspot) => (hotspot.toNodeId ?? '').trim())
        .where((id) => id.isNotEmpty && id != currentNodeId)
        .toSet();

    for (final targetId in targetIds) {
      if (_prefetchedNodeIds.contains(targetId)) continue;
      _prefetchedNodeIds.add(targetId);
      unawaited(_prefetchNodeImages(targetId));
    }
  }

  Future<void> _prefetchNodeImages(String nodeId) async {
    try {
      final snapshot = await _db
          .collection('tours')
          .doc(widget.tourId)
          .collection('nodes')
          .doc(nodeId)
          .get();
      if (!snapshot.exists || !mounted) return;

      final data = snapshot.data() ?? const <String, dynamic>{};
      final rawPreview = (data['previewUrl'] ?? '').toString().trim();
      final rawPano = (data['panoUrl'] ?? '').toString().trim();

      final urls = <String?>[
        await _resolveRemoteUrl(rawPreview),
        await _resolveRemoteUrl(rawPano),
      ];

      for (final url in urls) {
        if (url == null || !mounted) continue;
        try {
          await precacheImage(CachedNetworkImageProvider(url), context);
        } catch (_) {
          // Ignore prefetch failures; normal load still runs later.
        }
      }
    } catch (_) {
      // Ignore prefetch failures.
    }
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

  Future<void> _openAndroidAppDownload() async {
    if (_openingDistributionLink) return;
    setState(() => _openingDistributionLink = true);
    try {
      final config = await _distribution.fetchConfig();
      final opened = await _distribution.openAndroidApk(config);
      if (!opened && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Android app download link is not configured yet.'),
          ),
        );
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Android app download link is not configured yet.'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _openingDistributionLink = false);
      }
    }
  }

  Widget _buildWebVrDownloadCard({
    bool compact = false,
    EdgeInsetsGeometry margin = EdgeInsets.zero,
  }) {
    return FutureBuilder<AppDistributionConfig>(
      future: _distribution.fetchConfig(),
      builder: (context, snapshot) {
        final config = snapshot.data;
        if (config == null || config.androidApkUrl.isEmpty) {
          return const SizedBox.shrink();
        }

        final textTheme = Theme.of(context).textTheme;
        final bodyColor = compact ? Colors.white70 : textTheme.bodyMedium?.color;

        return Container(
          width: double.infinity,
          margin: margin,
          padding: EdgeInsets.all(compact ? 12 : 14),
          decoration: BoxDecoration(
            color: compact
                ? Colors.white.withValues(alpha: 0.10)
                : Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: compact
                  ? Colors.white24
                  : Theme.of(context).colorScheme.outline.withValues(alpha: 0.2),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'VR works best in the Android app',
                style: (compact
                        ? textTheme.titleSmall
                        : textTheme.titleMedium)
                    ?.copyWith(
                      color: compact ? Colors.white : null,
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 6),
              Text(
                'Web users can keep exploring here, but full phone VR mode is available in the Android APK.',
                style: (compact
                        ? textTheme.bodySmall
                        : textTheme.bodyMedium)
                    ?.copyWith(color: bodyColor),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: compact
                    ? ElevatedButton.icon(
                        onPressed: _openingDistributionLink
                            ? null
                            : _openAndroidAppDownload,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: Colors.black87,
                        ),
                        icon: const Icon(Icons.download),
                        label: const Text('Download Android APK'),
                      )
                    : OutlinedButton.icon(
                        onPressed: _openingDistributionLink
                            ? null
                            : _openAndroidAppDownload,
                        icon: const Icon(Icons.download),
                        label: const Text('Download Android APK'),
                      ),
              ),
            ],
          ),
        );
      },
    );
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
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isShort = constraints.maxHeight < 430;
            final topTitleSize = isShort ? 13.0 : 16.0;
            final destinationTitleSize = isShort ? 34.0 : 44.0;
            final chooseModeSize = isShort ? 30.0 : 38.0;
            final verticalButtonPadding = isShort ? 10.0 : 14.0;

            return Container(
              padding: EdgeInsets.fromLTRB(
                16,
                isShort ? 12 : 24,
                16,
                isShort ? 12 : 24,
              ),
              color: Colors.black.withValues(alpha: 0.35),
              child: SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Explore the beauty of',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: topTitleSize,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        title,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: destinationTitleSize,
                          fontWeight: FontWeight.w800,
                          height: 1.05,
                        ),
                      ),
                      SizedBox(height: isShort ? 12 : 18),
                      Text(
                        'Choose View Mode',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: chooseModeSize,
                          fontWeight: FontWeight.w800,
                          height: 1.0,
                        ),
                      ),
                      SizedBox(height: isShort ? 12 : 55),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: _supportsVrCardboard ? _enterVrMode : null,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF2C8D5B),
                            foregroundColor: Colors.white,
                            padding: EdgeInsets.symmetric(
                              vertical: verticalButtonPadding,
                            ),
                          ),
                          icon: const Icon(Icons.vrpano),
                          label: const Text(
                            'VR Mode',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                      ),
                      if (!_supportsVrCardboard)
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Padding(
                              padding: EdgeInsets.only(top: 8),
                              child: Text(
                                'VR mode is only available on Android/iOS devices.',
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                            if (kIsWeb)
                              _buildWebVrDownloadCard(
                                compact: true,
                                margin: const EdgeInsets.only(top: 12),
                              ),
                          ],
                        ),
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: _enterScreenMode,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            side: const BorderSide(color: Colors.white70),
                            padding: EdgeInsets.symmetric(
                              vertical: verticalButtonPadding,
                            ),
                          ),
                          icon: const Icon(Icons.smartphone),
                          label: const Text(
                            'Screen / Normal Mode',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildSafetyWarningOverlay() {
    if (!_showSafetyWarning) {
      return const SizedBox.shrink();
    }

    return Positioned.fill(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isShort = constraints.maxHeight < 430;
          final horizontalPadding = isShort ? 12.0 : 20.0;
          final titleSize = isShort ? 26.0 : 34.0;
          final bodyFontSize = isShort ? 12.0 : 13.0;

          return Container(
            color: Colors.black.withValues(alpha: 0.45),
            alignment: Alignment.center,
            padding: EdgeInsets.all(horizontalPadding),
            child: Container(
              constraints: BoxConstraints(
                maxWidth: 420,
                maxHeight: constraints.maxHeight - (horizontalPadding * 2),
              ),
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.65),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFF0FC1FF), width: 1.2),
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'WARNING!',
                      style: TextStyle(
                        color: const Color(0xFF1CC848),
                        fontSize: titleSize,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'This mobile virtual reality nature experience limits your awareness of your real-world surroundings. '
                      'Use only in a safe, open area free of obstacles, edges, water, or traffic. Remain seated or stationary '
                      'while wearing the headset, and remove it before walking or moving. Take regular breaks to prevent '
                      'dizziness or discomfort. Children should be supervised at all times. Remember, while the environment may '
                      'be virtual, real-world hazards still exist.',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: bodyFontSize,
                        height: 1.4,
                        fontWeight: FontWeight.w600,
                      ),
                      textAlign: TextAlign.justify,
                    ),
                    const SizedBox(height: 10),
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
        },
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
          final isTeleport = hotspot.type == 'teleport';
          final markerColor = _parseColorHexOrDefault(
            hotspot.colorHex,
            hotspot.type,
          );
          final markerSize = hotspot.size.clamp(16.0, 44.0);
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
            width: markerSize,
            height: markerSize,
            widget: GestureDetector(
              onTap: () => _onHotspotTap(hotspot),
              child: SizedBox(
                width: markerSize,
                height: markerSize,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Container(
                      width: markerSize,
                      height: markerSize,
                      decoration: BoxDecoration(
                        color: markerColor.withValues(alpha: 0.25),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 1.5),
                        boxShadow: [
                          BoxShadow(
                            color: markerColor.withValues(alpha: 0.45),
                            blurRadius: 8,
                            spreadRadius: 1,
                          ),
                        ],
                      ),
                    ),
                    Container(
                      width: markerSize * 0.62,
                      height: markerSize * 0.62,
                      decoration: BoxDecoration(
                        color: markerColor,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 1.3),
                      ),
                      child: Icon(
                        _iconForStyle(hotspot.iconStyle, isTeleport),
                        size: markerSize * 0.35,
                        color: Colors.black,
                      ),
                    ),
                    Positioned(
                      top: 0,
                      right: 0,
                      child: Container(
                        width: markerSize * 0.42,
                        height: markerSize * 0.42,
                        alignment: Alignment.center,
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                        ),
                        child: Text(
                          '${index + 1}',
                          style: const TextStyle(
                            fontSize: 8,
                            fontWeight: FontWeight.w800,
                            color: Colors.black,
                            height: 1,
                          ),
                        ),
                      ),
                    ),
                  ],
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
    final hasUrl =
        panoUrl.startsWith('http://') || panoUrl.startsWith('https://');

    if (!hasUrl) {
      if (_resolvingPanoUrl) {
        return const ColoredBox(
          color: Colors.black54,
          child: Center(child: CircularProgressIndicator()),
        );
      }
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

    final cacheWidth = (MediaQuery.sizeOf(context).width * 2).round().clamp(
      1024,
      4096,
    );

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
        cacheWidth: cacheWidth,
        errorBuilder: (context, networkError, stackTrace) {
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
    final transitionKey = ValueKey<String>('${_currentNodeId ?? ''}|$panoUrl');

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
    final activePanoUrl =
        (_highResReady ? _resolvedPanoUrl : _resolvedPreviewPanoUrl) ??
        _resolvedPanoUrl ??
        rawPanoUrl;
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
                if (kIsWeb)
                  _buildWebVrDownloadCard(
                    margin: const EdgeInsets.only(top: 12),
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
                        child: _buildVrCardboardPanorama(
                          activePanoUrl,
                          hotspots,
                        ),
                      ),
                      if (_resolvingPanoUrl)
                        const Positioned(
                          top: 10,
                          left: 10,
                          child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
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
                          activePanoUrl,
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
                      if (_resolvingPanoUrl)
                        const Positioned(
                          top: 10,
                          left: 10,
                          child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
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
                              activePanoUrl,
                              hotspots,
                              showHotspots: true,
                              interactive: true,
                            ),
                          ),
                          if (_resolvingPanoUrl)
                            const Positioned(
                              top: 10,
                              left: 10,
                              child: SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
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
  final String iconStyle;
  final String? colorHex;
  final double size;

  const _RuntimeHotspot({
    required this.type,
    required this.yaw,
    required this.pitch,
    this.title,
    this.text,
    this.toNodeId,
    this.label,
    this.iconStyle = 'auto',
    this.colorHex,
    this.size = 28,
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
      iconStyle: (map['icon'] ?? 'auto').toString(),
      colorHex: map['colorHex']?.toString(),
      size: readFiniteDouble(map['size']).clamp(16.0, 44.0),
    );
  }
}

Color _defaultHotspotColor(String type) {
  return type == 'teleport' ? Colors.orangeAccent : Colors.lightBlueAccent;
}

Color _parseColorHexOrDefault(String? hex, String type) {
  final fallback = _defaultHotspotColor(type);
  if (hex == null) return fallback;
  var input = hex.trim();
  if (input.isEmpty) return fallback;
  if (input.startsWith('#')) input = input.substring(1);
  if (input.length == 6) input = 'FF$input';
  if (input.length != 8) return fallback;
  final value = int.tryParse(input, radix: 16);
  if (value == null) return fallback;
  return Color(value);
}

IconData _iconForStyle(String style, bool isTeleport) {
  switch (style) {
    case 'pin':
      return Icons.place;
    case 'star':
      return Icons.star;
    case 'flag':
      return Icons.flag;
    case 'camera':
      return Icons.photo_camera;
    case 'arrow':
      return Icons.arrow_forward;
    case 'info':
      return Icons.info_outline;
    default:
      return isTeleport ? Icons.arrow_forward : Icons.info_outline;
  }
}
