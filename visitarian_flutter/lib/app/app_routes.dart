import 'package:flutter/material.dart';
import 'package:visitarian_flutter/features/auth/auth.dart';
import 'package:visitarian_flutter/features/tour/tour.dart';

abstract final class AppRoutes {
  static const splash = '/';
  static const authGate = '/auth-gate';
  static const auth = '/auth';
  static const onboarding = '/onboarding';
  static const tourSelection = '/tour-selection';

  static Map<String, WidgetBuilder> get map => {
    splash: (_) => const SplashScreen(),
    authGate: (_) => AuthGate(),
    auth: (_) => const AuthScreen(),
    onboarding: (_) => const OnboardingScreen(),
    tourSelection: (_) => const TourSelectionScreen(),
  };
}
