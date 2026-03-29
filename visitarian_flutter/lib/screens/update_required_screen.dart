import 'package:flutter/material.dart';
import 'package:visitarian_flutter/core/services/services.dart';

class UpdateRequiredScreen extends StatefulWidget {
  const UpdateRequiredScreen({super.key, required this.status});

  final AppUpdateStatus status;

  @override
  State<UpdateRequiredScreen> createState() => _UpdateRequiredScreenState();
}

class _UpdateRequiredScreenState extends State<UpdateRequiredScreen> {
  bool _opening = false;

  Future<void> _openUpdate() async {
    if (_opening) return;
    setState(() => _opening = true);
    final opened = await AppDistributionService.instance.openPreferredDownload(
      widget.status.config,
    );
    if (!mounted) return;
    if (!opened) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Update link is not configured yet.')),
      );
    }
    setState(() => _opening = false);
  }

  @override
  Widget build(BuildContext context) {
    final releaseNotes = widget.status.config.releaseNotes;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.system_update_alt, size: 56),
                  const SizedBox(height: 18),
                  const Text(
                    'Update required',
                    style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'This version (${widget.status.currentVersion}) is no longer supported. '
                    'Please update to continue using VisitaRian.',
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Minimum supported version: ${widget.status.config.minSupportedVersion}',
                  ),
                  if (widget.status.config.latestVersion.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      'Latest version: ${widget.status.config.latestVersion}',
                    ),
                  ],
                  if (releaseNotes.isNotEmpty) ...[
                    const SizedBox(height: 18),
                    Text(
                      releaseNotes,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _opening ? null : _openUpdate,
                      child: Text(_opening ? 'Opening...' : 'Update now'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
