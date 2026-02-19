import 'package:flutter/material.dart';
import 'package:visitarian_flutter/app/app_routes.dart';
import 'package:visitarian_flutter/core/theme/theme.dart';

class VisitaRianApp extends StatelessWidget {
  const VisitaRianApp({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: AppThemeController.instance,
      builder: (context, _) => MaterialApp(
        debugShowCheckedModeBanner: false,
        themeMode: AppThemeController.instance.themeMode,
        theme: ThemeData.light(),
        darkTheme: ThemeData.dark(),
        initialRoute: AppRoutes.splash,
        routes: AppRoutes.map,
      ),
    );
  }
}
