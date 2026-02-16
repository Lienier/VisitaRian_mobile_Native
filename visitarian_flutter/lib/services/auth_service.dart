import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

class AuthService {
  final _auth = FirebaseAuth.instance;
  final _db = FirebaseFirestore.instance;

  Stream<User?> authStateChanges() => _auth.userChanges();

  Future<User?> signUpWithEmail({
    required String username,
    required String email,
    required String password,
  }) async {
    final normalizedEmail = email.trim();
    UserCredential cred;
    try {
      cred = await _auth.createUserWithEmailAndPassword(
        email: normalizedEmail,
        password: password,
      );
    } on FirebaseAuthException catch (e) {
      if (e.code == 'email-already-in-use') {
        throw FirebaseAuthException(
          code: 'email-already-in-use',
          message: 'This email is already in use.',
        );
      }
      rethrow;
    }
    final user = cred.user;

    if (user != null) {
      await user.updateDisplayName(username.trim());
      await user.sendEmailVerification();

      await _db.collection('users').doc(user.uid).set({
        'username': username.trim(),
        'email': user.email,
        'provider': 'password',
        'createdAt': FieldValue.serverTimestamp(),
        'lastLoginAt': FieldValue.serverTimestamp(),
        'hasSeenOnboarding': false,
      }, SetOptions(merge: true));
    }
    return user;
  }

  Future<User?> signInWithEmail({
    required String email,
    required String password,
  }) async {
    final normalizedEmail = email.trim();
    final cred = await _auth.signInWithEmailAndPassword(
      email: normalizedEmail,
      password: password,
    );
    final user = cred.user;

    if (user != null) {
      await _updateLastLogin(user.uid);
      // Ensure hasSeenOnboarding is initialized for existing users
      final doc = await _db.collection('users').doc(user.uid).get();
      if (doc.exists && !(doc.data()?['hasSeenOnboarding'] ?? false)) {
        // If field doesn't exist, set it to true (existing users have already seen app)
        if (!doc.data()!.containsKey('hasSeenOnboarding')) {
          await _db.collection('users').doc(user.uid).set({
            'hasSeenOnboarding': true,
          }, SetOptions(merge: true));
        }
      }
    }

    return user;
  }

  Future<User?> signInWithGoogle() async {
    final googleUser = await GoogleSignIn().signIn();
    if (googleUser == null) return null; // user cancelled

    final googleAuth = await googleUser.authentication;

    final credential = GoogleAuthProvider.credential(
      accessToken: googleAuth.accessToken,
      idToken: googleAuth.idToken,
    );

    UserCredential userCred;
    try {
      userCred = await _auth.signInWithCredential(credential);
    } on FirebaseAuthException catch (e) {
      if (e.code == 'account-exists-with-different-credential') {
        throw FirebaseAuthException(
          code: 'provider-mismatch',
          message:
              'This email is registered with email and password. Use email sign in instead.',
        );
      }
      rethrow;
    }
    final user = userCred.user;

    if (user != null) {
      // Fetch existing document to preserve/migrate onboarding flag for older accounts
      final docRef = _db.collection('users').doc(user.uid);
      final doc = await docRef.get();

      bool hasSeenOnboarding = false;

      if (doc.exists) {
        final data = doc.data();
        if (data != null && data.containsKey('hasSeenOnboarding')) {
          hasSeenOnboarding = (data['hasSeenOnboarding'] ?? false) as bool;
        } else {
          // Infer from createdAt if possible
          final createdAt = data?['createdAt'] as Timestamp?;
          if (createdAt != null) {
            final days = DateTime.now().difference(createdAt.toDate()).inDays;
            hasSeenOnboarding = days > 30;
          } else {
            // Default to true for safety (existing user)
            hasSeenOnboarding = true;
          }
        }
      } else {
        // New user signing in with Google — show onboarding
        hasSeenOnboarding = false;
      }

      await docRef.set({
        'username': user.displayName ?? '',
        'email': user.email,
        'provider': 'google',
        'photoUrl': user.photoURL,
        'updatedAt': FieldValue.serverTimestamp(),
        'lastLoginAt': FieldValue.serverTimestamp(),
        'hasSeenOnboarding': hasSeenOnboarding,
      }, SetOptions(merge: true));
    }

    return user;
  }

  Future<void> _updateLastLogin(String uid) async {
    await _db.collection('users').doc(uid).set({
      'lastLoginAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Check if user needs to re-authenticate (90 days since last login)
  Future<bool> isReAuthRequired() async {
    final user = _auth.currentUser;
    if (user == null) return true;

    try {
      final doc = await _db.collection('users').doc(user.uid).get();
      final lastLogin = doc.data()?['lastLoginAt'] as Timestamp?;

      if (lastLogin == null) return true;

      final daysSinceLogin = DateTime.now()
          .difference(lastLogin.toDate())
          .inDays;
      return daysSinceLogin >= 90;
    } catch (e) {
      return true;
    }
  }

  /// Check if user has seen onboarding
  Future<bool> hasSeenOnboarding() async {
    final user = _auth.currentUser;
    if (user == null) return false;

    try {
      final doc = await _db.collection('users').doc(user.uid).get();
      return (doc.data()?['hasSeenOnboarding'] ?? false) as bool;
    } catch (e) {
      return false;
    }
  }

  /// Mark onboarding as seen
  Future<void> markOnboardingAsSeen() async {
    final user = _auth.currentUser;
    if (user == null) return;

    await _db.collection('users').doc(user.uid).set({
      'hasSeenOnboarding': true,
    }, SetOptions(merge: true));
  }

  /// Change user password
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    final user = _auth.currentUser;
    if (user == null || user.email == null) {
      throw Exception('No user logged in');
    }

    // Re-authenticate first
    final credential = EmailAuthProvider.credential(
      email: user.email!,
      password: currentPassword,
    );

    await user.reauthenticateWithCredential(credential);
    await user.updatePassword(newPassword);
  }

  Future<void> sendPasswordReset(String email) async {
    await _auth.sendPasswordResetEmail(email: email.trim());
  }

  Future<void> signOut() async {
    try {
      await GoogleSignIn().signOut();
    } catch (e) {
      // Continue even if Google sign out fails
    }
    await _auth.signOut();
  }
}
