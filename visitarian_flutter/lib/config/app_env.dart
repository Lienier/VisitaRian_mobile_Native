import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter_dotenv/flutter_dotenv.dart';

class AppEnv {
  AppEnv._();

  static const String _defaultOrsApiKey =
      'eyJvcmciOiI1YjNjZTM1OTc4NTExMTAwMDFjZjYyNDgiLCJpZCI6ImRmZWRmYTQ1MWQ4NzRlNjhhMjY1NzdmN2I0OWUwNWI5IiwiaCI6Im11cm11cjY0In0=';
  static const String _defaultTomTomApiKey = 'IpaCHRkQ82fuN7KDKciXG1JwppDL4DlA';
  static const String _defaultGoogleWebClientId =
      '112732840406-52hjfkukqpuumkbq8pqvnqr5rnd772aa.apps.googleusercontent.com';
  static const String _defaultGoogleIosClientId =
      '112732840406-dlnh8lajne9pcr8dsl0a3nu4oe09g7qr.apps.googleusercontent.com';
  static const String _defaultFirebaseProjectId = 'my-visitarian-project-287ab';
  static const String _defaultFirebaseMessagingSenderId = '112732840406';
  static const String _defaultFirebaseAuthDomain =
      'my-visitarian-project-287ab.firebaseapp.com';
  static const String _defaultFirebaseStorageBucket =
      'my-visitarian-project-287ab.firebasestorage.app';
  static const String _defaultFirebaseWebApiKey =
      'AIzaSyDHr0vQnnm4phqgVCO2yBDK2aSegiaYeno';
  static const String _defaultFirebaseWebAppId =
      '1:112732840406:web:ee4dd25314ed4894f10477';
  static const String _defaultFirebaseWebMeasurementId = 'G-WGB2J8Z97V';

  static Future<void> load() async {
    try {
      await dotenv.load(fileName: '.env');
    } catch (_) {
      // Prefer compile-time defines so web builds do not ship a public .env file.
    }
  }

  static String get orsApiKey => _optional(
    const String.fromEnvironment('ORS_API_KEY'),
    'ORS_API_KEY',
    fallback: _defaultOrsApiKey,
  );

  static String get tomTomApiKey => _optional(
    const String.fromEnvironment('TOMTOM_API_KEY'),
    'TOMTOM_API_KEY',
    fallback: _defaultTomTomApiKey,
  );

  static String get googleWebClientId => _optional(
    const String.fromEnvironment('GOOGLE_WEB_CLIENT_ID'),
    'GOOGLE_WEB_CLIENT_ID',
    fallback: _defaultGoogleWebClientId,
  );

  static String get googleIosClientId => _optional(
    const String.fromEnvironment('GOOGLE_IOS_CLIENT_ID'),
    'GOOGLE_IOS_CLIENT_ID',
    fallback: _defaultGoogleIosClientId,
  );

  static FirebaseOptions get currentFirebaseOptions {
    if (kIsWeb) {
      return FirebaseOptions(
        apiKey: _required(
          const String.fromEnvironment('FIREBASE_WEB_API_KEY'),
          'FIREBASE_WEB_API_KEY',
          fallback: _defaultFirebaseWebApiKey,
        ),
        appId: _required(
          const String.fromEnvironment('FIREBASE_WEB_APP_ID'),
          'FIREBASE_WEB_APP_ID',
          fallback: _defaultFirebaseWebAppId,
        ),
        messagingSenderId: _required(
          const String.fromEnvironment('FIREBASE_MESSAGING_SENDER_ID'),
          'FIREBASE_MESSAGING_SENDER_ID',
          fallback: _defaultFirebaseMessagingSenderId,
        ),
        projectId: _required(
          const String.fromEnvironment('FIREBASE_PROJECT_ID'),
          'FIREBASE_PROJECT_ID',
          fallback: _defaultFirebaseProjectId,
        ),
        authDomain: _required(
          const String.fromEnvironment('FIREBASE_AUTH_DOMAIN'),
          'FIREBASE_AUTH_DOMAIN',
          fallback: _defaultFirebaseAuthDomain,
        ),
        storageBucket: _required(
          const String.fromEnvironment('FIREBASE_STORAGE_BUCKET'),
          'FIREBASE_STORAGE_BUCKET',
          fallback: _defaultFirebaseStorageBucket,
        ),
        measurementId: _required(
          const String.fromEnvironment('FIREBASE_WEB_MEASUREMENT_ID'),
          'FIREBASE_WEB_MEASUREMENT_ID',
          fallback: _defaultFirebaseWebMeasurementId,
        ),
      );
    }

    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return FirebaseOptions(
          apiKey: _required(
            const String.fromEnvironment('FIREBASE_ANDROID_API_KEY'),
            'FIREBASE_ANDROID_API_KEY',
          ),
          appId: _required(
            const String.fromEnvironment('FIREBASE_ANDROID_APP_ID'),
            'FIREBASE_ANDROID_APP_ID',
          ),
          messagingSenderId: _required(
            const String.fromEnvironment('FIREBASE_MESSAGING_SENDER_ID'),
            'FIREBASE_MESSAGING_SENDER_ID',
          ),
          projectId: _required(
            const String.fromEnvironment('FIREBASE_PROJECT_ID'),
            'FIREBASE_PROJECT_ID',
          ),
          storageBucket: _required(
            const String.fromEnvironment('FIREBASE_STORAGE_BUCKET'),
            'FIREBASE_STORAGE_BUCKET',
          ),
        );
      case TargetPlatform.iOS:
      case TargetPlatform.macOS:
        return FirebaseOptions(
          apiKey: _required(
            const String.fromEnvironment('FIREBASE_APPLE_API_KEY'),
            'FIREBASE_APPLE_API_KEY',
          ),
          appId: _required(
            const String.fromEnvironment('FIREBASE_APPLE_APP_ID'),
            'FIREBASE_APPLE_APP_ID',
          ),
          messagingSenderId: _required(
            const String.fromEnvironment('FIREBASE_MESSAGING_SENDER_ID'),
            'FIREBASE_MESSAGING_SENDER_ID',
          ),
          projectId: _required(
            const String.fromEnvironment('FIREBASE_PROJECT_ID'),
            'FIREBASE_PROJECT_ID',
          ),
          storageBucket: _required(
            const String.fromEnvironment('FIREBASE_STORAGE_BUCKET'),
            'FIREBASE_STORAGE_BUCKET',
          ),
          iosBundleId: _required(
            const String.fromEnvironment('FIREBASE_APPLE_BUNDLE_ID'),
            'FIREBASE_APPLE_BUNDLE_ID',
          ),
        );
      case TargetPlatform.windows:
        return FirebaseOptions(
          apiKey: _required(
            const String.fromEnvironment('FIREBASE_WINDOWS_API_KEY'),
            'FIREBASE_WINDOWS_API_KEY',
          ),
          appId: _required(
            const String.fromEnvironment('FIREBASE_WINDOWS_APP_ID'),
            'FIREBASE_WINDOWS_APP_ID',
          ),
          messagingSenderId: _required(
            const String.fromEnvironment('FIREBASE_MESSAGING_SENDER_ID'),
            'FIREBASE_MESSAGING_SENDER_ID',
          ),
          projectId: _required(
            const String.fromEnvironment('FIREBASE_PROJECT_ID'),
            'FIREBASE_PROJECT_ID',
          ),
          authDomain: _required(
            const String.fromEnvironment('FIREBASE_AUTH_DOMAIN'),
            'FIREBASE_AUTH_DOMAIN',
          ),
          storageBucket: _required(
            const String.fromEnvironment('FIREBASE_STORAGE_BUCKET'),
            'FIREBASE_STORAGE_BUCKET',
          ),
          measurementId: _required(
            const String.fromEnvironment('FIREBASE_WINDOWS_MEASUREMENT_ID'),
            'FIREBASE_WINDOWS_MEASUREMENT_ID',
          ),
        );
      case TargetPlatform.linux:
        throw UnsupportedError(
          'Firebase options have not been configured for linux.',
        );
      default:
        throw UnsupportedError(
          'Firebase options are not supported for this platform.',
        );
    }
  }

  static String _optional(
    String defineValue,
    String key, {
    String fallback = '',
  }) {
    if (defineValue.isNotEmpty) {
      return defineValue;
    }
    final fromEnv = _fromDotEnv(key);
    if (fromEnv.isNotEmpty) {
      return fromEnv;
    }
    return fallback;
  }

  static String _required(
    String defineValue,
    String key, {
    String fallback = '',
  }) {
    final value = _optional(defineValue, key, fallback: fallback);
    if (value.isEmpty) {
      throw StateError(
        'Missing $key. Pass it through --dart-define or --dart-define-from-file.',
      );
    }
    return value;
  }

  static String _fromDotEnv(String key) {
    try {
      return dotenv.env[key]?.trim() ?? '';
    } catch (_) {
      return '';
    }
  }
}
