import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:visitarian_flutter/config/app_env.dart';
import 'package:visitarian_flutter/core/theme/theme.dart';

Future<void> bootstrapApp(Future<void> Function() run) async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppEnv.load();
  await Firebase.initializeApp(options: AppEnv.currentFirebaseOptions);
  final shouldActivateAppCheck =
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);
  if (shouldActivateAppCheck) {
    try {
      await FirebaseAppCheck.instance.activate(
        androidProvider: AndroidProvider.playIntegrity,
        appleProvider: AppleProvider.deviceCheck,
      );
    } catch (_) {
      // Keep app usable if App Check isn't configured yet for this environment.
      if (kDebugMode) {
        // no-op
      }
    }
  }
  await AppThemeController.instance.init();
  await run();
}
