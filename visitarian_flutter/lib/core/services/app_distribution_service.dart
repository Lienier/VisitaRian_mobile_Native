import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

class AppDistributionConfig {
  const AppDistributionConfig({
    required this.websiteUrl,
    required this.androidApkUrl,
    required this.latestVersion,
    required this.minSupportedVersion,
    required this.forceUpdate,
    required this.releaseNotes,
  });

  factory AppDistributionConfig.fromMap(Map<String, dynamic>? data) {
    final source = data ?? const <String, dynamic>{};
    return AppDistributionConfig(
      websiteUrl: (source['websiteUrl'] ?? 'https://visitarian.app')
          .toString()
          .trim(),
      androidApkUrl: (source['androidApkUrl'] ?? '').toString().trim(),
      latestVersion: (source['latestVersion'] ?? '').toString().trim(),
      minSupportedVersion: (source['minSupportedVersion'] ?? '')
          .toString()
          .trim(),
      forceUpdate: source['forceUpdate'] == true,
      releaseNotes: (source['releaseNotes'] ?? '').toString().trim(),
    );
  }

  final String websiteUrl;
  final String androidApkUrl;
  final String latestVersion;
  final String minSupportedVersion;
  final bool forceUpdate;
  final String releaseNotes;

  Map<String, Object?> toMap() => <String, Object?>{
    'websiteUrl': websiteUrl,
    'androidApkUrl': androidApkUrl,
    'latestVersion': latestVersion,
    'minSupportedVersion': minSupportedVersion,
    'forceUpdate': forceUpdate,
    'releaseNotes': releaseNotes,
    'updatedAt': FieldValue.serverTimestamp(),
  };

  String get preferredDownloadUrl {
    if (_isAndroidLikePlatform && androidApkUrl.isNotEmpty) {
      return androidApkUrl;
    }
    return websiteUrl;
  }

  static bool get _isAndroidLikePlatform =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
}

class AppUpdateStatus {
  const AppUpdateStatus({
    required this.currentVersion,
    required this.config,
    required this.updateAvailable,
    required this.updateRequired,
  });

  final String currentVersion;
  final AppDistributionConfig config;
  final bool updateAvailable;
  final bool updateRequired;
}

class AppDistributionService {
  AppDistributionService._();

  static final instance = AppDistributionService._();
  static const String _collection = 'appConfig';
  static const String _docId = 'mobileDistribution';

  final FirebaseFirestore _db = FirebaseFirestore.instance;

  Stream<AppDistributionConfig> watchConfig() {
    return _db
        .collection(_collection)
        .doc(_docId)
        .snapshots()
        .map((doc) => AppDistributionConfig.fromMap(doc.data()));
  }

  Future<AppDistributionConfig> fetchConfig() async {
    final doc = await _db.collection(_collection).doc(_docId).get();
    return AppDistributionConfig.fromMap(doc.data());
  }

  Future<void> saveConfig(AppDistributionConfig config) async {
    await _db
        .collection(_collection)
        .doc(_docId)
        .set(config.toMap(), SetOptions(merge: true));
  }

  Future<AppUpdateStatus> checkForUpdates() async {
    final packageInfo = await PackageInfo.fromPlatform();
    final config = await fetchConfig();
    final currentVersion = packageInfo.version.trim();

    final updateAvailable =
        config.latestVersion.isNotEmpty &&
        compareVersions(currentVersion, config.latestVersion) < 0;
    final updateRequired =
        config.forceUpdate &&
        config.minSupportedVersion.isNotEmpty &&
        compareVersions(currentVersion, config.minSupportedVersion) < 0;

    return AppUpdateStatus(
      currentVersion: currentVersion,
      config: config,
      updateAvailable: updateAvailable,
      updateRequired: updateRequired,
    );
  }

  Future<bool> openPreferredDownload(AppDistributionConfig config) async {
    final url = config.preferredDownloadUrl;
    if (url.isEmpty) return false;
    return _openUrl(url);
  }

  Future<bool> openWebsite(AppDistributionConfig config) async {
    if (config.websiteUrl.isEmpty) return false;
    return _openUrl(config.websiteUrl);
  }

  Future<bool> openAndroidApk(AppDistributionConfig config) async {
    if (config.androidApkUrl.isEmpty) return false;
    return _openUrl(config.androidApkUrl);
  }

  Future<bool> _openUrl(String value) async {
    final uri = Uri.tryParse(value);
    if (uri == null) return false;
    return launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  static int compareVersions(String left, String right) {
    final leftParts = _normalizeVersion(left);
    final rightParts = _normalizeVersion(right);
    final maxLength = leftParts.length > rightParts.length
        ? leftParts.length
        : rightParts.length;

    for (var i = 0; i < maxLength; i++) {
      final leftValue = i < leftParts.length ? leftParts[i] : 0;
      final rightValue = i < rightParts.length ? rightParts[i] : 0;
      if (leftValue != rightValue) {
        return leftValue.compareTo(rightValue);
      }
    }
    return 0;
  }

  static List<int> _normalizeVersion(String value) {
    return value
        .split('+')
        .first
        .split('.')
        .map((part) => int.tryParse(part.trim()) ?? 0)
        .toList(growable: false);
  }
}
