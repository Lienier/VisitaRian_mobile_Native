import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:visitarian_flutter/core/services/services.dart';

class SuperAdminConsoleScreen extends StatefulWidget {
  const SuperAdminConsoleScreen({super.key});

  @override
  State<SuperAdminConsoleScreen> createState() =>
      _SuperAdminConsoleScreenState();
}

class _SuperAdminConsoleScreenState extends State<SuperAdminConsoleScreen> {
  final AccessInviteService _inviteService = AccessInviteService.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _organizationController = TextEditingController();
  final TextEditingController _subscriptionLabelController =
      TextEditingController();

  String _role = 'admin';
  DateTime? _inviteExpiresAt;
  DateTime? _subscriptionEndsAt;
  bool _creatingInvite = false;
  String? _latestInviteToken;
  String? _latestInviteUrl;

  @override
  void dispose() {
    _emailController.dispose();
    _organizationController.dispose();
    _subscriptionLabelController.dispose();
    super.dispose();
  }

  Future<void> _pickInviteExpiry() async {
    final today = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: _inviteExpiresAt ?? today.add(const Duration(days: 3)),
      firstDate: today,
      lastDate: today.add(const Duration(days: 365)),
    );
    if (date == null || !mounted) return;
    setState(() {
      _inviteExpiresAt = DateTime(date.year, date.month, date.day, 23, 59);
    });
  }

  Future<void> _pickSubscriptionEnd() async {
    final today = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: _subscriptionEndsAt ?? today.add(const Duration(days: 30)),
      firstDate: today,
      lastDate: today.add(const Duration(days: 3650)),
    );
    if (date == null || !mounted) return;
    setState(() {
      _subscriptionEndsAt = DateTime(date.year, date.month, date.day, 23, 59);
    });
  }

  Future<void> _createInvite() async {
    final email = _emailController.text.trim();
    if (email.isEmpty) {
      _showMessage('Email is required.');
      return;
    }

    setState(() => _creatingInvite = true);
    try {
      final result = await _inviteService.createInvite(
        email: email,
        role: _role,
        organizationName: _organizationController.text,
        subscriptionLabel: _subscriptionLabelController.text,
        expiresAt: _inviteExpiresAt,
        subscriptionEndsAt: _subscriptionEndsAt,
      );
      if (!mounted) return;
      setState(() {
        _latestInviteToken = result.inviteToken;
        _latestInviteUrl = result.inviteUrl.isEmpty ? null : result.inviteUrl;
      });
      _showMessage('Invite created for $email.');
    } catch (error) {
      if (!mounted) return;
      _showMessage(AccessInviteService.describeError(error));
    } finally {
      if (mounted) {
        setState(() => _creatingInvite = false);
      }
    }
  }

  Future<void> _copy(String value, String label) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (!mounted) return;
    _showMessage('$label copied.');
  }

  Future<void> _revokeInvite(String inviteId) async {
    try {
      await _inviteService.revokeInvite(inviteId);
      if (!mounted) return;
      _showMessage('Invite revoked.');
    } catch (error) {
      if (!mounted) return;
      _showMessage(AccessInviteService.describeError(error));
    }
  }

  Future<void> _setManagedStatus({
    required String targetUid,
    required bool disabled,
  }) async {
    try {
      await _inviteService.setManagedAccountStatus(
        targetUid: targetUid,
        disabled: disabled,
      );
      if (!mounted) return;
      _showMessage(disabled ? 'Account suspended.' : 'Account re-enabled.');
    } catch (error) {
      if (!mounted) return;
      _showMessage(AccessInviteService.describeError(error));
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Super Admin Console')),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 1100;
          final leftPane = _buildCreateInviteCard();
          final invitePane = _buildInviteListSection();
          final managedPane = _buildManagedAccountsSection();

          if (wide) {
            return Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 4, child: leftPane),
                  const SizedBox(width: 16),
                  Expanded(
                    flex: 5,
                    child: Column(
                      children: [
                        Expanded(child: invitePane),
                        const SizedBox(height: 16),
                        Expanded(child: managedPane),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              leftPane,
              const SizedBox(height: 16),
              invitePane,
              const SizedBox(height: 16),
              managedPane,
            ],
          );
        },
      ),
    );
  }

  Widget _buildCreateInviteCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Create Invite',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _emailController,
              decoration: const InputDecoration(
                labelText: 'Invited email',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _role,
              decoration: const InputDecoration(
                labelText: 'Role',
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(value: 'admin', child: Text('Admin')),
                DropdownMenuItem(
                  value: 'beneficiary',
                  child: Text('Beneficiary'),
                ),
              ],
              onChanged: (value) {
                if (value == null) return;
                setState(() => _role = value);
              },
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _organizationController,
              decoration: const InputDecoration(
                labelText: 'Organization',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _subscriptionLabelController,
              decoration: const InputDecoration(
                labelText: 'Subscription label',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                OutlinedButton.icon(
                  onPressed: _pickInviteExpiry,
                  icon: const Icon(Icons.schedule),
                  label: Text(
                    _inviteExpiresAt == null
                        ? 'Invite expiry'
                        : _formatDate(_inviteExpiresAt!),
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: _pickSubscriptionEnd,
                  icon: const Icon(Icons.event_available),
                  label: Text(
                    _subscriptionEndsAt == null
                        ? 'Subscription end'
                        : _formatDate(_subscriptionEndsAt!),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _creatingInvite ? null : _createInvite,
                icon: _creatingInvite
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.mail_lock),
                label: Text(
                  _creatingInvite ? 'Creating...' : 'Create One-Time Invite',
                ),
              ),
            ),
            if (_latestInviteToken != null || _latestInviteUrl != null) ...[
              const SizedBox(height: 18),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFF7FAF8),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Latest Invite',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    if (_latestInviteUrl != null) ...[
                      const SizedBox(height: 10),
                      SelectableText(_latestInviteUrl!),
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        onPressed: () => _copy(_latestInviteUrl!, 'Invite URL'),
                        icon: const Icon(Icons.copy),
                        label: const Text('Copy Invite URL'),
                      ),
                    ],
                    if (_latestInviteToken != null) ...[
                      const SizedBox(height: 10),
                      SelectableText(_latestInviteToken!),
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        onPressed: () =>
                            _copy(_latestInviteToken!, 'Invite token'),
                        icon: const Icon(Icons.copy),
                        label: const Text('Copy Invite Token'),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildInviteListSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Invites',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 320,
              child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: _db
                    .collection('adminInvites')
                    .orderBy('createdAt', descending: true)
                    .snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError) {
                    return Center(
                      child: Text('Failed to load invites: ${snapshot.error}'),
                    );
                  }

                  final docs =
                      snapshot.data?.docs ??
                      <QueryDocumentSnapshot<Map<String, dynamic>>>[];
                  if (docs.isEmpty) {
                    return const Center(child: Text('No invites yet.'));
                  }

                  return ListView.separated(
                    itemCount: docs.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final doc = docs[index];
                      final data = doc.data();
                      final status = (data['status'] ?? 'pending').toString();
                      final redeemedBy = (data['redeemedByEmail'] ?? '')
                          .toString();
                      return ListTile(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                          side: BorderSide(color: Colors.grey.shade300),
                        ),
                        title: Text((data['email'] ?? '').toString()),
                        subtitle: Text(
                          '${(data['role'] ?? '').toString()} • '
                          '${(data['organizationName'] ?? 'No organization').toString()}'
                          '${redeemedBy.isEmpty ? '' : '\nRedeemed by $redeemedBy'}',
                        ),
                        trailing: Wrap(
                          spacing: 8,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Chip(label: Text(status)),
                            if (status == 'pending')
                              TextButton(
                                onPressed: () => _revokeInvite(doc.id),
                                child: const Text('Revoke'),
                              ),
                          ],
                        ),
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

  Widget _buildManagedAccountsSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Managed Accounts',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 320,
              child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: _db
                    .collection('accessGrants')
                    .orderBy('updatedAt', descending: true)
                    .snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError) {
                    return Center(
                      child: Text(
                        'Failed to load managed accounts: ${snapshot.error}',
                      ),
                    );
                  }

                  final docs =
                      snapshot.data?.docs ??
                      <QueryDocumentSnapshot<Map<String, dynamic>>>[];
                  if (docs.isEmpty) {
                    return const Center(
                      child: Text('No managed accounts yet.'),
                    );
                  }

                  return ListView.separated(
                    itemCount: docs.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final doc = docs[index];
                      final data = doc.data();
                      final status = (data['status'] ?? 'active').toString();
                      final isSuspended = status == 'suspended';
                      return ListTile(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                          side: BorderSide(color: Colors.grey.shade300),
                        ),
                        title: Text((data['email'] ?? '').toString()),
                        subtitle: Text(
                          '${(data['role'] ?? '').toString()} • '
                          '${(data['organizationName'] ?? 'No organization').toString()}'
                          '\nSubscription: ${(data['subscriptionStatus'] ?? 'unknown').toString()}',
                        ),
                        trailing: TextButton(
                          onPressed: () => _setManagedStatus(
                            targetUid: doc.id,
                            disabled: !isSuspended,
                          ),
                          child: Text(isSuspended ? 'Enable' : 'Suspend'),
                        ),
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

  static String _formatDate(DateTime value) {
    final local = value.toLocal();
    final month = local.month.toString().padLeft(2, '0');
    final day = local.day.toString().padLeft(2, '0');
    return '${local.year}-$month-$day';
  }
}
