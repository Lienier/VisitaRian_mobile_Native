import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/widgets.dart';
import 'package:visitarian_flutter/core/theme/theme.dart';
import 'package:visitarian_flutter/firebase_options.dart';

Future<void> bootstrapApp(Future<void> Function() run) async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await AppThemeController.instance.init();
  await run();
}
