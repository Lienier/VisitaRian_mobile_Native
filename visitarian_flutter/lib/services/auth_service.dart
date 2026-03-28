import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:visitarian_flutter/config/app_env.dart';

class AuthService {
  final _auth = FirebaseAuth.instance;
  final _db = FirebaseFirestore.instance;
  late final GoogleSignIn _googleSignIn = GoogleSignIn(
    clientId: kIsWeb
        ? AppEnv.googleWebClientId
        : (defaultTargetPlatform == TargetPlatform.iOS
              ? AppEnv.googleIosClientId
              : null),
    serverClientId: kIsWeb ? null : AppEnv.googleWebClientId,
    scopes: const <String>['email'],
  );

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
      final doc = await _db.collection('users').doc(user.uid).get();
      if (doc.exists && !(doc.data()?['hasSeenOnboarding'] ?? false)) {
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
    if (kIsWeb) {
      final provider = GoogleAuthProvider();
      provider.setCustomParameters(<String, String>{
        'prompt': 'select_account',
      });
      final userCred = await _auth.signInWithPopup(provider);
      final user = userCred.user;
      if (user != null) {
        await _syncGoogleUserProfile(user);
      }
      return user;
    }

    if (defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.linux) {
      throw FirebaseAuthException(
        code: 'google-sign-in-unsupported-platform',
        message:
            'Google sign-in is not supported in this desktop build yet. Use Chrome or Edge for now.',
      );
    }

    GoogleSignInAccount? googleUser;
    try {
      await _googleSignIn.signOut();
      googleUser = await _googleSignIn.signIn();
    } catch (_) {
      throw FirebaseAuthException(
        code: 'google-sign-in-failed',
        message:
            'Google sign-in could not start. Check the Firebase and Google app setup.',
      );
    }
    if (googleUser == null) return null;

    final googleAuth = await googleUser.authentication;
    final idToken = googleAuth.idToken;
    if (idToken == null || idToken.isEmpty) {
      throw FirebaseAuthException(
        code: 'google-sign-in-misconfigured',
        message:
            'Google sign-in is missing an ID token. Check the OAuth client IDs and platform configuration.',
      );
    }

    final credential = GoogleAuthProvider.credential(
      accessToken: googleAuth.accessToken,
      idToken: idToken,
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
      await _syncGoogleUserProfile(user);
    }

    return user;
  }

  Future<void> _syncGoogleUserProfile(User user) async {
    final docRef = _db.collection('users').doc(user.uid);
    final doc = await docRef.get();

    bool hasSeenOnboarding = false;

    if (doc.exists) {
      final data = doc.data();
      if (data != null && data.containsKey('hasSeenOnboarding')) {
        hasSeenOnboarding = (data['hasSeenOnboarding'] ?? false) as bool;
      } else {
        final createdAt = data?['createdAt'] as Timestamp?;
        if (createdAt != null) {
          final days = DateTime.now().difference(createdAt.toDate()).inDays;
          hasSeenOnboarding = days > 30;
        } else {
          hasSeenOnboarding = true;
        }
      }
    } else {
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

  Future<void> _updateLastLogin(String uid) async {
    await _db.collection('users').doc(uid).set({
      'lastLoginAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

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

  Future<void> markOnboardingAsSeen() async {
    final user = _auth.currentUser;
    if (user == null) return;

    await _db.collection('users').doc(user.uid).set({
      'hasSeenOnboarding': true,
    }, SetOptions(merge: true));
  }

  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    final user = _auth.currentUser;
    if (user == null || user.email == null) {
      throw Exception('No user logged in');
    }

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
      await _googleSignIn.signOut();
    } catch (e) {
      // Continue even if Google sign out fails.
    }
    await _auth.signOut();
  }
}
