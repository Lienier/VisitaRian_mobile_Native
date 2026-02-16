import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'firebase_options.dart';
import 'screens/splash_screen.dart';
import 'theme/app_theme_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  await AppThemeController.instance.init();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: AppThemeController.instance,
      builder: (context, _) => MaterialApp(
        debugShowCheckedModeBanner: false,
        themeMode: AppThemeController.instance.themeMode,
        theme: ThemeData.light(),
        darkTheme: ThemeData.dark(),
        home: const SplashScreen(),
      ),
    );
  }
}
