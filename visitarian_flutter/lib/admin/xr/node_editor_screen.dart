import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'admin_access.dart';
import 'xr_firestore.dart';
import 'xr_models.dart';

class NodeEditorScreen extends StatefulWidget {
  final String tourId;
  final String nodeId;
  final XrFirestore? xrFirestore;
  final bool embedded;
  final VoidCallback? onSaved;

  const NodeEditorScreen({
    super.key,
    required this.tourId,
    required this.nodeId,
    this.xrFirestore,
    this.embedded = false,
    this.onSaved,
  });

  @override
  State<NodeEditorScreen> createState() => _NodeEditorScreenState();
}

class _NodeEditorScreenState extends State<NodeEditorScreen> {
  late final XrFirestore _xrFirestore;
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _panoUrlController = TextEditingController();

  final List<_EditableHotspot> _hotspots = [];
  bool _isLoading = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _xrFirestore = widget.xrFirestore ?? XrFirestore();
    _loadNode();
    _panoUrlController.addListener(_requestRebuild);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _panoUrlController.removeListener(_requestRebuild);
    _panoUrlController.dispose();
    for (final hotspot in _hotspots) {
      hotspot.dispose();
    }
    super.dispose();
  }

  void _requestRebuild() {
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _loadNode() async {
    if (!isAdminEmail(FirebaseAuth.instance.currentUser?.email)) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
      return;
    }

    try {
      final DocumentSnapshot<Map<String, dynamic>> snapshot = await _xrFirestore
          .getNode(tourId: widget.tourId, nodeId: widget.nodeId);

      if (!mounted) return;

      if (snapshot.exists) {
        final data = snapshot.data() ?? {};
        _nameController.text = (data['name'] ?? '').toString();
        _panoUrlController.text = (data['panoUrl'] ?? '').toString();

        final hotspotMaps = (data['hotspots'] as List<dynamic>? ?? const []);
        for (final raw in hotspotMaps) {
          if (raw is Map<String, dynamic>) {
            _hotspots.add(
              _EditableHotspot.fromModel(
                XrHotspot.fromMap(raw),
                _requestRebuild,
              ),
            );
          }
        }
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to load node: $e')));
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _addHotspot(String type) {
    setState(() {
      _hotspots.add(
        _EditableHotspot(type: type, onAnyChanged: _requestRebuild),
      );
    });
  }

  void _removeHotspot(int index) {
    setState(() {
      final removed = _hotspots.removeAt(index);
      removed.dispose();
    });
  }

  String? _validateRequired(String? value, String field) {
    if (value == null || value.trim().isEmpty) {
      return '$field is required';
    }
    return null;
  }

  bool _validateHotspots() {
    for (var i = 0; i < _hotspots.length; i++) {
      final hotspot = _hotspots[i];
      final yaw = double.tryParse(hotspot.yawController.text.trim());
      final pitch = double.tryParse(hotspot.pitchController.text.trim());

      if (yaw == null || pitch == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Hotspot ${i + 1}: yaw/pitch must be numeric.'),
          ),
        );
        return false;
      }

      if (hotspot.type == 'info') {
        if (hotspot.titleController.text.trim().isEmpty ||
            hotspot.textController.text.trim().isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Hotspot ${i + 1}: info title and text are required.',
              ),
            ),
          );
          return false;
        }
      }

      if (hotspot.type == 'teleport' &&
          hotspot.toNodeIdController.text.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Hotspot ${i + 1}: target nodeId is required.'),
          ),
        );
        return false;
      }
    }

    return true;
  }

  Future<void> _save() async {
    if (_isSaving) return;

    if (!isAdminEmail(FirebaseAuth.instance.currentUser?.email)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Access denied. Admin account required.')),
      );
      return;
    }

    final isValid = _formKey.currentState?.validate() ?? false;
    if (!isValid || !_validateHotspots()) return;

    final hotspotModels = _hotspots.map((e) => e.toModel()).toList();

    setState(() {
      _isSaving = true;
    });

    try {
      await _xrFirestore.upsertNode(
        tourId: widget.tourId,
        nodeId: widget.nodeId,
        name: _nameController.text.trim(),
        panoUrl: _panoUrlController.text.trim(),
        hotspots: hotspotModels,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Node saved.')));
      if (widget.embedded) {
        widget.onSaved?.call();
      } else {
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to save node: $e')));
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  List<_PreviewHotspot> _buildPreviewHotspots() {
    final preview = <_PreviewHotspot>[];
    for (var i = 0; i < _hotspots.length; i++) {
      final hotspot = _hotspots[i];
      final yaw = double.tryParse(hotspot.yawController.text.trim());
      final pitch = double.tryParse(hotspot.pitchController.text.trim());
      if (yaw == null || pitch == null) continue;

      preview.add(
        _PreviewHotspot(index: i, type: hotspot.type, yaw: yaw, pitch: pitch),
      );
    }
    return preview;
  }

  double _normalizeYaw(double yaw) {
    final normalized = ((yaw + 180) % 360 + 360) % 360;
    return normalized - 180;
  }

  Offset _mapYawPitchToPoint(double yaw, double pitch, Size size) {
    final normalizedYaw = _normalizeYaw(yaw);
    final clampedPitch = pitch.clamp(-90.0, 90.0);

    final x = ((normalizedYaw + 180.0) / 360.0) * size.width;
    final y = ((90.0 - clampedPitch) / 180.0) * size.height;

    return Offset(x, y);
  }

  bool _isNetworkUrl(String value) {
    return value.startsWith('http://') || value.startsWith('https://');
  }

  Future<String?> _resolvePreviewUrl(String rawUrl) async {
    final trimmed = rawUrl.trim();
    if (trimmed.isEmpty) return null;

    if (_isNetworkUrl(trimmed)) {
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

  Future<_TeleportPreviewData?> _loadTeleportPreview(
    String targetNodeId,
  ) async {
    final nodeId = targetNodeId.trim();
    if (nodeId.isEmpty) return null;

    final snapshot = await _xrFirestore.getNode(
      tourId: widget.tourId,
      nodeId: nodeId,
    );

    if (!snapshot.exists) {
      return _TeleportPreviewData(
        nodeId: nodeId,
        title: '',
        panoUrl: '',
        resolvedPreviewUrl: null,
        error: 'Target node not found.',
      );
    }

    final data = snapshot.data() ?? const <String, dynamic>{};
    final title = (data['name'] ?? '').toString().trim();
    final panoUrl = (data['panoUrl'] ?? '').toString().trim();
    final resolved = await _resolvePreviewUrl(panoUrl);

    return _TeleportPreviewData(
      nodeId: snapshot.id,
      title: title,
      panoUrl: panoUrl,
      resolvedPreviewUrl: resolved,
      error: null,
    );
  }

  Widget _buildTeleportPreview(_EditableHotspot hotspot) {
    final targetNodeId = hotspot.toNodeIdController.text.trim();
    if (targetNodeId.isEmpty) {
      return const SizedBox.shrink();
    }

    return FutureBuilder<_TeleportPreviewData?>(
      future: _loadTeleportPreview(targetNodeId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.only(top: 8),
            child: SizedBox(
              height: 44,
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            ),
          );
        }

        if (snapshot.hasError) {
          return Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'Preview unavailable: ${snapshot.error}',
              style: const TextStyle(color: Colors.redAccent),
            ),
          );
        }

        final preview = snapshot.data;
        if (preview == null) return const SizedBox.shrink();

        return Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.shade300),
              borderRadius: BorderRadius.circular(10),
              color: Colors.black.withValues(alpha: 0.02),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  preview.title.isEmpty ? preview.nodeId : preview.title,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(
                  'Node ID: ${preview.nodeId}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () async {
                      final messenger = ScaffoldMessenger.of(context);
                      await Clipboard.setData(
                        ClipboardData(text: preview.nodeId),
                      );
                      if (!mounted) return;
                      messenger.showSnackBar(
                        const SnackBar(content: Text('Node ID copied.')),
                      );
                    },
                    icon: const Icon(Icons.copy, size: 16),
                    label: const Text('Copy Node ID'),
                  ),
                ),
                if (preview.error != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    preview.error!,
                    style: const TextStyle(color: Colors.redAccent),
                  ),
                ] else if (preview.resolvedPreviewUrl != null) ...[
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: AspectRatio(
                      aspectRatio: 16 / 9,
                      child: Image.network(
                        preview.resolvedPreviewUrl!,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) {
                          return const ColoredBox(
                            color: Color(0xFF263238),
                            child: Center(
                              child: Text(
                                'Failed to load preview image',
                                style: TextStyle(color: Colors.white),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ] else ...[
                  const SizedBox(height: 8),
                  const Text(
                    'No preview image available for this target node.',
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _pickTargetNodeFromList(_EditableHotspot hotspot) async {
    final selectedNodeId = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Pick Target Node'),
          content: SizedBox(
            width: 560,
            height: 420,
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _xrFirestore.nodesStream(widget.tourId),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(
                    child: Text('Failed to load nodes: ${snapshot.error}'),
                  );
                }

                final docs = snapshot.data?.docs ?? const [];
                final candidates = docs
                    .where((doc) => doc.id != widget.nodeId)
                    .toList(growable: false);

                if (candidates.isEmpty) {
                  return const Center(
                    child: Text('No other nodes available in this tour.'),
                  );
                }

                return ListView.separated(
                  itemCount: candidates.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final doc = candidates[index];
                    final data = doc.data();
                    final name = (data['name'] ?? '').toString().trim();
                    final panoUrl = (data['panoUrl'] ?? '').toString().trim();

                    return ListTile(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                        side: BorderSide(color: Colors.grey.shade300),
                      ),
                      title: Text(name.isEmpty ? doc.id : name),
                      subtitle: Text(
                        'Node ID: ${doc.id}\n$panoUrl',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      isThreeLine: true,
                      trailing: IconButton(
                        tooltip: 'Copy node ID',
                        icon: const Icon(Icons.copy, size: 18),
                        onPressed: () async {
                          final messenger = ScaffoldMessenger.of(context);
                          await Clipboard.setData(ClipboardData(text: doc.id));
                          if (!mounted) return;
                          messenger.showSnackBar(
                            const SnackBar(content: Text('Node ID copied.')),
                          );
                        },
                      ),
                      onTap: () => Navigator.of(dialogContext).pop(doc.id),
                    );
                  },
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
          ],
        );
      },
    );

    if (selectedNodeId == null) return;
    setState(() {
      hotspot.toNodeIdController.text = selectedNodeId;
    });
  }

  Widget _buildHotspotPreview() {
    final panoUrl = _panoUrlController.text.trim();
    final previewHotspots = _buildPreviewHotspots();

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Live Yaw/Pitch Preview',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'Yaw: -180 to 180, Pitch: -90 to 90. Markers move as you edit.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: AspectRatio(
                aspectRatio: 2,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final size = Size(
                      constraints.maxWidth,
                      constraints.maxHeight,
                    );

                    return Stack(
                      fit: StackFit.expand,
                      children: [
                        if (panoUrl.startsWith('http://') ||
                            panoUrl.startsWith('https://'))
                          Image.network(
                            panoUrl,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) {
                              return const ColoredBox(
                                color: Color(0xFF263238),
                                child: Center(
                                  child: Text(
                                    'Panorama failed to load',
                                    style: TextStyle(color: Colors.white),
                                  ),
                                ),
                              );
                            },
                          )
                        else
                          const ColoredBox(
                            color: Color(0xFF263238),
                            child: Center(
                              child: Text(
                                'Add panorama URL to visualize hotspots',
                                style: TextStyle(color: Colors.white),
                              ),
                            ),
                          ),
                        Container(color: Colors.black.withValues(alpha: 0.18)),
                        Positioned.fill(
                          child: CustomPaint(painter: _GridPainter()),
                        ),
                        ...previewHotspots.map((h) {
                          final point = _mapYawPitchToPoint(
                            h.yaw,
                            h.pitch,
                            size,
                          );
                          final color = h.type == 'teleport'
                              ? Colors.orange
                              : Colors.lightBlueAccent;

                          return Positioned(
                            left: point.dx - 10,
                            top: point.dy - 10,
                            child: Tooltip(
                              message:
                                  '#${h.index + 1} ${h.type}\nYaw: ${h.yaw.toStringAsFixed(1)} | Pitch: ${h.pitch.toStringAsFixed(1)}',
                              child: Container(
                                width: 20,
                                height: 20,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: color,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: Colors.white,
                                    width: 2,
                                  ),
                                ),
                                child: Text(
                                  '${h.index + 1}',
                                  style: const TextStyle(
                                    color: Colors.black,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 10,
                                  ),
                                ),
                              ),
                            ),
                          );
                        }),
                      ],
                    );
                  },
                ),
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: const [
                _LegendDot(
                  color: Colors.lightBlueAccent,
                  label: 'info hotspot',
                ),
                _LegendDot(color: Colors.orange, label: 'teleport hotspot'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHotspotCard(int index) {
    final hotspot = _hotspots[index];
    final yaw = double.tryParse(hotspot.yawController.text.trim()) ?? 0.0;
    final pitch = double.tryParse(hotspot.pitchController.text.trim()) ?? 0.0;
    final clampedYaw = yaw.clamp(-180.0, 180.0);
    final clampedPitch = pitch.clamp(-90.0, 90.0);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: hotspot.type,
                    decoration: const InputDecoration(
                      labelText: 'Hotspot Type',
                    ),
                    items: const [
                      DropdownMenuItem<String>(
                        value: 'info',
                        child: Text('info'),
                      ),
                      DropdownMenuItem<String>(
                        value: 'teleport',
                        child: Text('teleport'),
                      ),
                    ],
                    onChanged: (value) {
                      if (value == null) return;
                      setState(() {
                        hotspot.type = value;
                      });
                    },
                  ),
                ),
                IconButton(
                  onPressed: () => _removeHotspot(index),
                  icon: const Icon(Icons.delete_outline),
                  tooltip: 'Remove hotspot',
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: hotspot.yawController,
                    onChanged: (_) => setState(() {}),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                      signed: true,
                    ),
                    decoration: const InputDecoration(labelText: 'Yaw'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: hotspot.pitchController,
                    onChanged: (_) => setState(() {}),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                      signed: true,
                    ),
                    decoration: const InputDecoration(labelText: 'Pitch'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Preview value: Yaw ${yaw.toStringAsFixed(1)} | Pitch ${pitch.toStringAsFixed(1)}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            Slider(
              value: clampedYaw,
              min: -180,
              max: 180,
              divisions: 360,
              label: 'Yaw ${clampedYaw.toStringAsFixed(0)}',
              onChanged: (value) {
                hotspot.yawController.text = value.toStringAsFixed(1);
                setState(() {});
              },
            ),
            Slider(
              value: clampedPitch,
              min: -90,
              max: 90,
              divisions: 180,
              label: 'Pitch ${clampedPitch.toStringAsFixed(0)}',
              onChanged: (value) {
                hotspot.pitchController.text = value.toStringAsFixed(1);
                setState(() {});
              },
            ),
            const SizedBox(height: 8),
            if (hotspot.type == 'info') ...[
              TextFormField(
                controller: hotspot.titleController,
                decoration: const InputDecoration(labelText: 'Info title'),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: hotspot.textController,
                decoration: const InputDecoration(
                  labelText: 'Info description',
                ),
                maxLines: 3,
              ),
            ],
            if (hotspot.type == 'teleport') ...[
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: hotspot.toNodeIdController,
                      onChanged: (_) => setState(() {}),
                      decoration: const InputDecoration(
                        labelText: 'Target nodeId',
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: () => _pickTargetNodeFromList(hotspot),
                    icon: const Icon(Icons.list_alt, size: 18),
                    label: const Text('Pick'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: hotspot.labelController,
                decoration: const InputDecoration(labelText: 'Teleport label'),
              ),
              _buildTeleportPreview(hotspot),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildEditorBody(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1100),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(labelText: 'Node name'),
                  validator: (value) => _validateRequired(value, 'Node name'),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _panoUrlController,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    labelText: 'Panorama URL (Firebase Storage URL)',
                  ),
                  validator: (value) =>
                      _validateRequired(value, 'Panorama URL'),
                ),
                const SizedBox(height: 16),
                _buildHotspotPreview(),
                Row(
                  children: [
                    Text(
                      'Hotspots',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const Spacer(),
                    OutlinedButton.icon(
                      onPressed: () => _addHotspot('info'),
                      icon: const Icon(Icons.info_outline),
                      label: const Text('Add Info'),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      onPressed: () => _addHotspot('teleport'),
                      icon: const Icon(Icons.open_in_new),
                      label: const Text('Add Teleport'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (_hotspots.isEmpty)
                  const Text('No hotspots yet. Add info or teleport hotspots.'),
                for (var i = 0; i < _hotspots.length; i++) _buildHotspotCard(i),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _isSaving ? null : _save,
                    icon: const Icon(Icons.save),
                    label: const Text('Save Node'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isAdmin = isAdminEmail(FirebaseAuth.instance.currentUser?.email);
    if (!isAdmin) {
      if (widget.embedded) {
        return const Center(
          child: Text('Access denied. Admin account required.'),
        );
      }
      return Scaffold(
        appBar: AppBar(title: const Text('XR Node Editor')),
        body: const Center(
          child: Text('Access denied. Admin account required.'),
        ),
      );
    }

    if (widget.embedded) {
      return _buildEditorBody(context);
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('Edit Node ${widget.nodeId}'),
        actions: [
          TextButton.icon(
            onPressed: _isLoading || _isSaving ? null : _save,
            icon: _isSaving
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save),
            label: const Text('Save'),
          ),
        ],
      ),
      body: _buildEditorBody(context),
    );
  }
}

class _EditableHotspot {
  String type;
  final VoidCallback onAnyChanged;
  final TextEditingController yawController;
  final TextEditingController pitchController;
  final TextEditingController titleController;
  final TextEditingController textController;
  final TextEditingController toNodeIdController;
  final TextEditingController labelController;

  _EditableHotspot({
    required this.type,
    required this.onAnyChanged,
    String yaw = '0',
    String pitch = '0',
    String title = '',
    String text = '',
    String toNodeId = '',
    String label = '',
  }) : yawController = TextEditingController(text: yaw),
       pitchController = TextEditingController(text: pitch),
       titleController = TextEditingController(text: title),
       textController = TextEditingController(text: text),
       toNodeIdController = TextEditingController(text: toNodeId),
       labelController = TextEditingController(text: label) {
    yawController.addListener(onAnyChanged);
    pitchController.addListener(onAnyChanged);
  }

  factory _EditableHotspot.fromModel(
    XrHotspot hotspot,
    VoidCallback onAnyChanged,
  ) {
    return _EditableHotspot(
      type: hotspot.type,
      onAnyChanged: onAnyChanged,
      yaw: hotspot.yaw.toString(),
      pitch: hotspot.pitch.toString(),
      title: hotspot.title ?? '',
      text: hotspot.text ?? '',
      toNodeId: hotspot.toNodeId ?? '',
      label: hotspot.label ?? '',
    );
  }

  XrHotspot toModel() {
    return XrHotspot(
      type: type,
      yaw: double.tryParse(yawController.text.trim()) ?? 0.0,
      pitch: double.tryParse(pitchController.text.trim()) ?? 0.0,
      title: titleController.text.trim().isEmpty
          ? null
          : titleController.text.trim(),
      text: textController.text.trim().isEmpty
          ? null
          : textController.text.trim(),
      toNodeId: toNodeIdController.text.trim().isEmpty
          ? null
          : toNodeIdController.text.trim(),
      label: labelController.text.trim().isEmpty
          ? null
          : labelController.text.trim(),
    );
  }

  void dispose() {
    yawController.removeListener(onAnyChanged);
    pitchController.removeListener(onAnyChanged);
    yawController.dispose();
    pitchController.dispose();
    titleController.dispose();
    textController.dispose();
    toNodeIdController.dispose();
    labelController.dispose();
  }
}

class _PreviewHotspot {
  final int index;
  final String type;
  final double yaw;
  final double pitch;

  const _PreviewHotspot({
    required this.index,
    required this.type,
    required this.yaw,
    required this.pitch,
  });
}

class _TeleportPreviewData {
  final String nodeId;
  final String title;
  final String panoUrl;
  final String? resolvedPreviewUrl;
  final String? error;

  const _TeleportPreviewData({
    required this.nodeId,
    required this.title,
    required this.panoUrl,
    required this.resolvedPreviewUrl,
    required this.error,
  });
}

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;

  const _LegendDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 1),
          ),
        ),
        const SizedBox(width: 6),
        Text(label),
      ],
    );
  }
}

class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.25)
      ..strokeWidth = 1;

    for (var i = 1; i < 4; i++) {
      final dy = (size.height / 4) * i;
      canvas.drawLine(Offset(0, dy), Offset(size.width, dy), paint);
    }

    for (var i = 1; i < 8; i++) {
      final dx = (size.width / 8) * i;
      canvas.drawLine(Offset(dx, 0), Offset(dx, size.height), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
