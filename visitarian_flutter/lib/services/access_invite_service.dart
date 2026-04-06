import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

class AccessInviteDetails {
  final String inviteId;
  final String email;
  final String role;
  final String organizationName;
  final String subscriptionLabel;
  final DateTime? expiresAt;
  final DateTime? subscriptionEndsAt;
  final String status;
  final String redeemedByEmail;

  const AccessInviteDetails({
    required this.inviteId,
    required this.email,
    required this.role,
    required this.organizationName,
    required this.subscriptionLabel,
    required this.expiresAt,
    required this.subscriptionEndsAt,
    required this.status,
    required this.redeemedByEmail,
  });

  factory AccessInviteDetails.fromMap(Map<String, dynamic> map) {
    return AccessInviteDetails(
      inviteId: (map['inviteId'] ?? '').toString(),
      email: (map['email'] ?? '').toString(),
      role: (map['role'] ?? '').toString(),
      organizationName: (map['organizationName'] ?? '').toString(),
      subscriptionLabel: (map['subscriptionLabel'] ?? '').toString(),
      expiresAt: _parseDate(map['expiresAt']),
      subscriptionEndsAt: _parseDate(map['subscriptionEndsAt']),
      status: (map['status'] ?? '').toString(),
      redeemedByEmail: (map['redeemedByEmail'] ?? '').toString(),
    );
  }

  static DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    final text = value.toString().trim();
    if (text.isEmpty) return null;
    return DateTime.tryParse(text)?.toLocal();
  }
}

class CreateAccessInviteResult {
  final String inviteId;
  final String inviteToken;
  final String inviteUrl;
  final DateTime? expiresAt;

  const CreateAccessInviteResult({
    required this.inviteId,
    required this.inviteToken,
    required this.inviteUrl,
    required this.expiresAt,
  });

  factory CreateAccessInviteResult.fromMap(Map<String, dynamic> map) {
    return CreateAccessInviteResult(
      inviteId: (map['inviteId'] ?? '').toString(),
      inviteToken: (map['inviteToken'] ?? '').toString(),
      inviteUrl: (map['inviteUrl'] ?? '').toString(),
      expiresAt: AccessInviteDetails._parseDate(map['expiresAt']),
    );
  }
}

class AccessInviteService {
  AccessInviteService._();

  static final AccessInviteService instance = AccessInviteService._();
  final FirebaseFunctions _functions = FirebaseFunctions.instance;

  static String? currentInviteToken() {
    final value = Uri.base.queryParameters['invite']?.trim() ?? '';
    return value.isEmpty ? null : value;
  }

  static String? currentBaseUrl() {
    if (!kIsWeb) return null;
    final uri = Uri.base;
    return uri.replace(queryParameters: const {}, fragment: '').toString();
  }

  static String describeError(Object error) {
    if (error is FirebaseFunctionsException) {
      return error.message ?? 'The server rejected the request.';
    }
    if (error is FirebaseAuthException) {
      return error.message ?? 'Authentication failed.';
    }
    return error.toString();
  }

  Future<Map<String, dynamic>> _call(
    String name, [
    Map<String, dynamic>? data,
  ]) async {
    final callable = _functions.httpsCallable(name);
    final result = await callable.call<Map<String, dynamic>>(data ?? const {});
    return Map<String, dynamic>.from(result.data);
  }

  Future<void> refreshClaims() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    await user.getIdToken(true);
  }

  Future<void> bootstrapSuperAdmin() async {
    await _call('bootstrapSuperAdmin');
    await refreshClaims();
  }

  Future<CreateAccessInviteResult> createInvite({
    required String email,
    required String role,
    String organizationName = '',
    String subscriptionLabel = '',
    DateTime? expiresAt,
    DateTime? subscriptionEndsAt,
    String? baseUrl,
  }) async {
    final payload = await _call('createAccessInvite', {
      'email': email.trim(),
      'role': role.trim(),
      'organizationName': organizationName.trim(),
      'subscriptionLabel': subscriptionLabel.trim(),
      'expiresAt': expiresAt?.toUtc().toIso8601String(),
      'subscriptionEndsAt': subscriptionEndsAt?.toUtc().toIso8601String(),
      'baseUrl': (baseUrl ?? currentBaseUrl() ?? '').trim(),
    });
    return CreateAccessInviteResult.fromMap(payload);
  }

  Future<AccessInviteDetails> validateInvite(String token) async {
    final payload = await _call('validateAccessInvite', {
      'token': token.trim(),
    });
    return AccessInviteDetails.fromMap(
      Map<String, dynamic>.from(payload['invite'] as Map? ?? const {}),
    );
  }

  Future<String> redeemInvite(String token) async {
    final payload = await _call('redeemAccessInvite', {'token': token.trim()});
    await refreshClaims();
    return (payload['role'] ?? '').toString();
  }

  Future<void> revokeInvite(String inviteId) async {
    await _call('revokeAccessInvite', {'inviteId': inviteId.trim()});
  }

  Future<void> setManagedAccountStatus({
    required String targetUid,
    required bool disabled,
    String reason = '',
  }) async {
    await _call('setManagedAccountStatus', {
      'targetUid': targetUid.trim(),
      'disabled': disabled,
      'reason': reason.trim(),
    });
  }
}
