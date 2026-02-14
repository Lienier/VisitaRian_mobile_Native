import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:panorama_viewer/panorama_viewer.dart';

class XrTourPlayerScreen extends StatefulWidget {
  final String tourId;
  final String? placeTitle;

  const XrTourPlayerScreen({super.key, required this.tourId, this.placeTitle});

  @override
  State<XrTourPlayerScreen> createState() => _XrTourPlayerScreenState();
}

class _XrTourPlayerScreenState extends State<XrTourPlayerScreen> {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  bool _loading = true;
  bool _gyroEnabled = true;
  String? _error;
  String? _startNodeId;
  String? _currentNodeId;
  Map<String, dynamic>? _currentNodeData;

  @override
  void initState() {
    super.initState();
    _loadTourStart();
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

      if (startNodeId.isEmpty) {
        final firstNodeSnapshot = await _db
            .collection('tours')
            .doc(widget.tourId)
            .collection('nodes')
            .orderBy('updatedAt', descending: true)
            .limit(1)
            .get();

        if (firstNodeSnapshot.docs.isNotEmpty) {
          startNodeId = firstNodeSnapshot.docs.first.id;
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
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to open node: $e')));
    }
  }

  List<_RuntimeHotspot> _parseHotspots() {
    final rawList =
        (_currentNodeData?['hotspots'] as List<dynamic>? ?? const []);

    return rawList
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
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(text),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  List<Hotspot> _buildPanoramaHotspots(List<_RuntimeHotspot> hotspots) {
    return hotspots.asMap().entries.map((entry) {
      final index = entry.key;
      final hotspot = entry.value;
      final markerColor = hotspot.type == 'teleport'
          ? Colors.orange
          : Colors.lightBlueAccent;

      return Hotspot(
        latitude: hotspot.pitch.clamp(-90.0, 90.0),
        longitude: hotspot.yaw.clamp(-180.0, 180.0),
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
    }).toList();
  }

  Widget _buildPanorama(String panoUrl, List<_RuntimeHotspot> hotspots) {
    final hasUrl =
        panoUrl.startsWith('http://') || panoUrl.startsWith('https://');

    if (!hasUrl) {
      return const ColoredBox(
        color: Colors.black54,
        child: Center(
          child: Text(
            'Panorama URL missing or invalid.',
            style: TextStyle(color: Colors.white),
          ),
        ),
      );
    }

    final sensorControl = (!kIsWeb && _gyroEnabled)
        ? SensorControl.orientation
        : SensorControl.none;

    return PanoramaViewer(
      sensorControl: sensorControl,
      minZoom: 1,
      maxZoom: 5,
      hotspots: _buildPanoramaHotspots(hotspots),
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

  Widget _buildTourView() {
    final nodeName = (_currentNodeData?['name'] ?? '').toString();
    final panoUrl = (_currentNodeData?['panoUrl'] ?? '').toString();
    final hotspots = _parseHotspots();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Stack(
                children: [
                  Positioned.fill(child: _buildPanorama(panoUrl, hotspots)),
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
                ],
              ),
            ),
          ),
        ),
        if (hotspots.isNotEmpty)
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
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Row(
            children: [
              if (_startNodeId != null && _currentNodeId != _startNodeId)
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
    return Scaffold(
      appBar: AppBar(title: const Text('XR Tour')),
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
    return _RuntimeHotspot(
      type: (map['type'] ?? '').toString(),
      yaw: (map['yaw'] as num?)?.toDouble() ?? 0.0,
      pitch: (map['pitch'] as num?)?.toDouble() ?? 0.0,
      title: map['title']?.toString(),
      text: map['text']?.toString(),
      toNodeId: map['toNodeId']?.toString(),
      label: map['label']?.toString(),
    );
  }
}
