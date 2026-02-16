import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'admin_access.dart';
import 'node_editor_screen.dart';
import 'xr_firestore.dart';

class NodeWorkspaceScreen extends StatefulWidget {
  final String tourId;
  final String? initialNodeId;
  final XrFirestore? xrFirestore;

  const NodeWorkspaceScreen({
    super.key,
    required this.tourId,
    this.initialNodeId,
    this.xrFirestore,
  });

  @override
  State<NodeWorkspaceScreen> createState() => _NodeWorkspaceScreenState();
}

class _NodeWorkspaceScreenState extends State<NodeWorkspaceScreen> {
  late final XrFirestore _xrFirestore;
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  String? _selectedNodeId;

  @override
  void initState() {
    super.initState();
    _xrFirestore = widget.xrFirestore ?? XrFirestore();
    _selectedNodeId = widget.initialNodeId;
    _searchController.addListener(() {
      if (!mounted) return;
      setState(() {
        _searchQuery = _searchController.text.trim().toLowerCase();
      });
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _createNode() async {
    final newNodeId = _xrFirestore.createNodeId(widget.tourId);
    setState(() {
      _selectedNodeId = newNodeId;
    });
  }

  Future<void> _setStartNode(String nodeId) async {
    await _xrFirestore.setStartNode(tourId: widget.tourId, startNodeId: nodeId);
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Start node updated.')));
  }

  bool _matchesQuery(String nodeId, String name) {
    if (_searchQuery.isEmpty) return true;
    return nodeId.toLowerCase().contains(_searchQuery) ||
        name.toLowerCase().contains(_searchQuery);
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
            TextField(
              controller: _searchController,
              decoration: InputDecoration(
                isDense: true,
                hintText: 'Search node name or ID',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
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
                        ..sort((a, b) {
                          final aTs = a.data()['updatedAt'] as Timestamp?;
                          final bTs = b.data()['updatedAt'] as Timestamp?;
                          if (aTs == null && bTs == null) return 0;
                          if (aTs == null) return 1;
                          if (bTs == null) return -1;
                          return bTs.compareTo(aTs);
                        });

                      final filteredDocs = sortedDocs
                          .where((doc) {
                            final name = (doc.data()['name'] ?? '').toString();
                            return _matchesQuery(doc.id, name);
                          })
                          .toList(growable: false);

                      if (filteredDocs.isEmpty) {
                        return const Center(child: Text('No matching nodes.'));
                      }

                      final selectedExists = filteredDocs.any(
                        (doc) => doc.id == _selectedNodeId,
                      );
                      if ((_selectedNodeId == null || !selectedExists) &&
                          filteredDocs.isNotEmpty) {
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (!mounted) return;
                          setState(() {
                            _selectedNodeId = filteredDocs.first.id;
                          });
                        });
                      }

                      return ListView.separated(
                        itemCount: filteredDocs.length,
                        separatorBuilder: (context, index) =>
                            const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final doc = filteredDocs[index];
                          final data = doc.data();
                          final name = (data['name'] ?? '').toString();
                          final panoUrl = (data['panoUrl'] ?? '').toString();
                          final hotspots =
                              (data['hotspots'] as List<dynamic>? ?? const []);
                          final isStartNode =
                              startNodeId.isNotEmpty && startNodeId == doc.id;
                          final isSelected = _selectedNodeId == doc.id;

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
                            onTap: () {
                              setState(() {
                                _selectedNodeId = doc.id;
                              });
                            },
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
                                      setState(() {
                                        _selectedNodeId = doc.id;
                                      });
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

  Widget _buildNodeEditorPanel() {
    if (_selectedNodeId == null) {
      return const Card(
        child: Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text('Select a node from the list to edit.'),
          ),
        ),
      );
    }

    return Card(
      clipBehavior: Clip.antiAlias,
      child: NodeEditorScreen(
        key: ValueKey(_selectedNodeId),
        tourId: widget.tourId,
        nodeId: _selectedNodeId!,
        xrFirestore: _xrFirestore,
        embedded: true,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!isAdminEmail(FirebaseAuth.instance.currentUser?.email)) {
      return Scaffold(
        appBar: AppBar(title: const Text('XR Node Workspace')),
        body: const Center(
          child: Text('Access denied. Admin account required.'),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('XR Node Workspace')),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 1000;
          if (wide) {
            return Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  SizedBox(width: 360, child: _buildNodeListPanel()),
                  const SizedBox(width: 12),
                  Expanded(child: _buildNodeEditorPanel()),
                ],
              ),
            );
          }

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              SizedBox(height: 360, child: _buildNodeListPanel()),
              const SizedBox(height: 12),
              SizedBox(height: 900, child: _buildNodeEditorPanel()),
            ],
          );
        },
      ),
    );
  }
}
