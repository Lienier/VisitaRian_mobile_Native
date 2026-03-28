import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter_dotenv/flutter_dotenv.dart';

class AppEnv {
  AppEnv._();

  static Future<void> load() async {
    try {
      await dotenv.load(fileName: '.env');
    } catch (_) {
      // Allow builds that provide values only through --dart-define.
    }
  }

  static String get orsApiKey =>
      _optional(const String.fromEnvironment('ORS_API_KEY'), 'ORS_API_KEY');

  static String get tomTomApiKey => _optional(
    const String.fromEnvironment('TOMTOM_API_KEY'),
    'TOMTOM_API_KEY',
  );

  static FirebaseOptions get currentFirebaseOptions {
    if (kIsWeb) {
      return FirebaseOptions(
        apiKey: _required(
          const String.fromEnvironment('FIREBASE_WEB_API_KEY'),
          'FIREBASE_WEB_API_KEY',
        ),
        appId: _required(
          const String.fromEnvironment('FIREBASE_WEB_APP_ID'),
          'FIREBASE_WEB_APP_ID',
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
          const String.fromEnvironment('FIREBASE_WEB_MEASUREMENT_ID'),
          'FIREBASE_WEB_MEASUREMENT_ID',
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

  static String _optional(String defineValue, String key) {
    if (defineValue.isNotEmpty) {
      return defineValue;
    }
    return _fromDotEnv(key);
  }

  static String _required(String defineValue, String key) {
    final value = _optional(defineValue, key);
    if (value.isEmpty) {
      throw StateError(
        'Missing $key. Add it to .env or pass it through --dart-define.',
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
