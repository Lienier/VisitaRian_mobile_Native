import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../admin/xr/admin_access.dart';
import '../admin/xr/admin_xr_home_screen.dart';
import '../services/auth_service.dart';
import 'auth_screen.dart';
import 'onboarding_screen.dart';
import 'tour_selection_screen.dart';

class AuthGate extends StatelessWidget {
  AuthGate({super.key});

  final _auth = AuthService();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: _auth.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final user = snapshot.data;

        if (user == null) return const AuthScreen();

        final isPasswordAccount = user.providerData.any(
          (provider) => provider.providerId == 'password',
        );
        if (isPasswordAccount && !user.emailVerified) {
          return const _VerifyEmailScreen();
        }

        return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .snapshots(),
          builder: (context, userSnapshot) {
            if (userSnapshot.connectionState == ConnectionState.waiting) {
              return const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              );
            }

            final userData = userSnapshot.data?.data();
            bool hasSeenOnboarding;
            if (userData == null) {
              hasSeenOnboarding = true;
            } else if (userData.containsKey('hasSeenOnboarding')) {
              hasSeenOnboarding =
                  (userData['hasSeenOnboarding'] ?? false) as bool;
            } else {
              final createdAt = userData['createdAt'] as Timestamp?;
              if (createdAt != null) {
                final daysSinceCreated = DateTime.now()
                    .difference(createdAt.toDate())
                    .inDays;
                hasSeenOnboarding = daysSinceCreated > 30;
              } else {
                hasSeenOnboarding = true;
              }
            }

            final lastLoginAt = userData?['lastLoginAt'] as Timestamp?;

            bool isReAuthRequired = false;
            if (lastLoginAt != null) {
              final daysSinceLogin = DateTime.now()
                  .difference(lastLoginAt.toDate())
                  .inDays;
              isReAuthRequired = daysSinceLogin >= 90;
            }

            if (isReAuthRequired) {
              return const AuthScreen();
            }

            if (!hasSeenOnboarding) {
              return const OnboardingScreen();
            }

            final isAdmin = isAdminEmail(user.email);

            if (isAdmin) {
              return const AdminXrHomeScreen();
            }

            return const TourSelectionScreen();
          },
        );
      },
    );
  }
}

class _VerifyEmailScreen extends StatefulWidget {
  const _VerifyEmailScreen();

  @override
  State<_VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends State<_VerifyEmailScreen> {
  bool _loading = false;

  Future<void> _resendVerification() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    setState(() => _loading = true);
    try {
      await user.sendEmailVerification();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Verification email sent to ${user.email ?? 'your email'}.',
          ),
        ),
      );
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.message ?? 'Failed to send verification email.'),
        ),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _refreshVerification() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    setState(() => _loading = true);
    try {
      await user.reload();
      final refreshed = FirebaseAuth.instance.currentUser;
      if (!mounted) return;
      if (!(refreshed?.emailVerified ?? false)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Email is not verified yet.')),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.mark_email_unread_outlined, size: 72),
              const SizedBox(height: 16),
              const Text(
                'Verify your email',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                'We sent a verification link to ${user?.email ?? 'your email'}. Check inbox/spam and verify to continue.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _loading ? null : _resendVerification,
                  child: const Text('Resend verification email'),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: _loading ? null : _refreshVerification,
                  child: const Text("I've verified"),
                ),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: _loading
                    ? null
                    : () => FirebaseAuth.instance.signOut(),
                child: const Text('Use another account'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
