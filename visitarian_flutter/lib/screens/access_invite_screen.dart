import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:visitarian_flutter/admin/xr/admin_xr_home_screen.dart';
import 'package:visitarian_flutter/core/services/services.dart';
import 'package:visitarian_flutter/screens/tour_selection_screen.dart';

class AccessInviteScreen extends StatefulWidget {
  final String inviteToken;

  const AccessInviteScreen({super.key, required this.inviteToken});

  @override
  State<AccessInviteScreen> createState() => _AccessInviteScreenState();
}

class _AccessInviteScreenState extends State<AccessInviteScreen> {
  final AccessInviteService _inviteService = AccessInviteService.instance;

  bool _loading = true;
  bool _redeeming = false;
  String? _error;
  AccessInviteDetails? _invite;

  @override
  void initState() {
    super.initState();
    _loadInvite();
  }

  Future<void> _loadInvite() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final invite = await _inviteService.validateInvite(widget.inviteToken);
      if (!mounted) return;
      setState(() {
        _invite = invite;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = AccessInviteService.describeError(error);
        _loading = false;
      });
    }
  }

  Future<void> _redeemInvite() async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;

    setState(() => _redeeming = true);
    try {
      final role = await _inviteService.redeemInvite(widget.inviteToken);
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Access activated. Your role is now live.'),
        ),
      );

      if (role == 'admin') {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(
            builder: (_) => const AdminXrHomeScreen(isSuperAdmin: false),
          ),
          (_) => false,
        );
      } else {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const TourSelectionScreen()),
          (_) => false,
        );
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = AccessInviteService.describeError(error);
        _redeeming = false;
      });
    }
  }

  Future<void> _reloadVerification() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    await user.reload();
    if (!mounted) return;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final userEmail = (user?.email ?? '').trim().toLowerCase();
    final inviteEmail = (_invite?.email ?? '').trim().toLowerCase();
    final emailMatches = inviteEmail.isEmpty || inviteEmail == userEmail;
    final needsVerification =
        user != null &&
        user.providerData.any(
          (provider) => provider.providerId == 'password',
        ) &&
        !(user.emailVerified);

    return Scaffold(
      backgroundColor: const Color(0xFFF6FBF8),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Card(
                elevation: 4,
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: _loading
                      ? const Center(child: CircularProgressIndicator())
                      : Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Activate Managed Access',
                              style: TextStyle(
                                fontSize: 28,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              _invite == null
                                  ? 'This invite could not be loaded.'
                                  : 'Review the invite, confirm you are signed in with the invited email, then activate your account.',
                              style: const TextStyle(fontSize: 15),
                            ),
                            if (_error != null) ...[
                              const SizedBox(height: 16),
                              _StatusBox(
                                color: Colors.red.shade50,
                                borderColor: Colors.red.shade200,
                                textColor: Colors.red.shade700,
                                message: _error!,
                              ),
                            ],
                            if (_invite != null) ...[
                              const SizedBox(height: 20),
                              _InviteSummary(invite: _invite!),
                              const SizedBox(height: 18),
                              _StatusBox(
                                color: emailMatches
                                    ? const Color(0xFFEAF7F0)
                                    : const Color(0xFFFFF5E8),
                                borderColor: emailMatches
                                    ? const Color(0xFF9CCFB0)
                                    : const Color(0xFFF0C67A),
                                textColor: emailMatches
                                    ? const Color(0xFF19573F)
                                    : const Color(0xFF8A5A00),
                                message: user == null
                                    ? 'Sign in or create an account with ${_invite!.email}.'
                                    : emailMatches
                                    ? 'Signed in as ${user.email}.'
                                    : 'This invite is for ${_invite!.email}, but you are signed in as ${user.email}.',
                              ),
                            ],
                            if (needsVerification) ...[
                              const SizedBox(height: 16),
                              _StatusBox(
                                color: const Color(0xFFFFF5E8),
                                borderColor: const Color(0xFFF0C67A),
                                textColor: const Color(0xFF8A5A00),
                                message:
                                    'Verify your email first, then come back here and activate the invite.',
                              ),
                            ],
                            const SizedBox(height: 22),
                            Wrap(
                              spacing: 12,
                              runSpacing: 12,
                              children: [
                                FilledButton.icon(
                                  onPressed:
                                      _invite == null ||
                                          user == null ||
                                          !emailMatches ||
                                          needsVerification ||
                                          _redeeming
                                      ? null
                                      : _redeemInvite,
                                  icon: _redeeming
                                      ? const SizedBox(
                                          width: 16,
                                          height: 16,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: Colors.white,
                                          ),
                                        )
                                      : const Icon(Icons.verified_user),
                                  label: Text(
                                    _redeeming
                                        ? 'Activating...'
                                        : 'Activate Account',
                                  ),
                                ),
                                OutlinedButton.icon(
                                  onPressed: _loadInvite,
                                  icon: const Icon(Icons.refresh),
                                  label: const Text('Refresh Invite'),
                                ),
                                if (needsVerification)
                                  OutlinedButton.icon(
                                    onPressed: _reloadVerification,
                                    icon: const Icon(Icons.mark_email_read),
                                    label: const Text("I've Verified"),
                                  ),
                                if (user != null)
                                  TextButton(
                                    onPressed: () => AuthService().signOut(),
                                    child: const Text('Use Another Account'),
                                  ),
                              ],
                            ),
                          ],
                        ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _InviteSummary extends StatelessWidget {
  final AccessInviteDetails invite;

  const _InviteSummary({required this.invite});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SummaryRow(label: 'Invited Email', value: invite.email),
          _SummaryRow(label: 'Role', value: invite.role),
          _SummaryRow(
            label: 'Organization',
            value: invite.organizationName.isEmpty
                ? 'Not specified'
                : invite.organizationName,
          ),
          _SummaryRow(
            label: 'Subscription',
            value: invite.subscriptionLabel.isEmpty
                ? 'Not specified'
                : invite.subscriptionLabel,
          ),
          _SummaryRow(
            label: 'Invite Expires',
            value: invite.expiresAt == null
                ? 'Not specified'
                : _formatDate(invite.expiresAt!),
          ),
          _SummaryRow(
            label: 'Subscription Ends',
            value: invite.subscriptionEndsAt == null
                ? 'Not specified'
                : _formatDate(invite.subscriptionEndsAt!),
          ),
        ],
      ),
    );
  }

  static String _formatDate(DateTime value) {
    final local = value.toLocal();
    final month = local.month.toString().padLeft(2, '0');
    final day = local.day.toString().padLeft(2, '0');
    return '${local.year}-$month-$day ${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }
}

class _SummaryRow extends StatelessWidget {
  final String label;
  final String value;

  const _SummaryRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 148,
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}

class _StatusBox extends StatelessWidget {
  final Color color;
  final Color borderColor;
  final Color textColor;
  final String message;

  const _StatusBox({
    required this.color,
    required this.borderColor,
    required this.textColor,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderColor),
      ),
      child: Text(
        message,
        style: TextStyle(color: textColor, fontWeight: FontWeight.w600),
      ),
    );
  }
}
