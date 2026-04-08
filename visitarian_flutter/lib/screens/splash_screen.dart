import 'dart:async';
import 'package:flutter/material.dart';
import 'package:visitarian_flutter/core/services/services.dart';
import 'package:visitarian_flutter/screens/auth_gate.dart';
import 'package:visitarian_flutter/screens/update_required_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  bool _navigated = false;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _boot() async {
    final wait = Future<void>.delayed(const Duration(seconds: 3));
    AppUpdateStatus? status;
    try {
      status = await AppDistributionService.instance.checkForUpdates();
    } catch (_) {
      // Keep startup usable if version lookup fails.
    }
    await wait;
    if (!mounted || _navigated) return;

    if (status?.updateRequired ?? false) {
      _navigated = true;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => UpdateRequiredScreen(status: status!),
        ),
      );
      return;
    }

    _navigated = true;
    Navigator.of(
      context,
    ).pushReplacement(MaterialPageRoute(builder: (_) => AuthGate()));
  }

  @override
  Widget build(BuildContext context) {
    const bg = Color(0xFF0E3B2E);
    const lightText = Color(0xFFE6F1EC);

    final size = MediaQuery.of(context).size;
    final isDesktop = size.width >= 1000;
    final logoSize = (size.width * (isDesktop ? 0.55 : 1.5))
        .clamp(340.0, 980.0)
        .toDouble();
    final titleSize = (size.width * (isDesktop ? 0.075 : 0.12))
        .clamp(54.0, 112.0)
        .toDouble();
    final subtitleSize = (size.width * (isDesktop ? 0.016 : 0.033))
        .clamp(13.0, 24.0)
        .toDouble();
    final rianShift = -(titleSize * 0.24);
    final bottomOffset = (size.height * (isDesktop ? 0.09 : 0.05))
        .clamp(24.0, 90.0)
        .toDouble();
    final contentMaxWidth = isDesktop ? 1200.0 : size.width;

    return Scaffold(
      backgroundColor: bg,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: contentMaxWidth),
            child: Stack(
              children: [
                Align(
                  alignment: const Alignment(0, -1.45),
                  child: Image.asset(
                    'assets/images/logo.png',
                    width: logoSize,
                    height: logoSize,
                    fit: BoxFit.contain,
                  ),
                ),

                Positioned(
                  left: 0,
                  right: 0,
                  bottom: bottomOffset,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Visita',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: lightText,
                          fontSize: titleSize,
                          fontWeight: FontWeight.w800,
                          height: 0.85,
                          letterSpacing: -0.5,
                        ),
                      ),
                      Transform.translate(
                        offset: Offset(0, rianShift),
                        child: Text(
                          'Rian',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: lightText,
                            fontSize: titleSize,
                            fontWeight: FontWeight.w800,
                            height: 0.85,
                            letterSpacing: -0.5,
                          ),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Explore through your eyes',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: lightText.withValues(alpha: 0.9),
                          fontSize: subtitleSize,
                          fontWeight: FontWeight.w500,
                          letterSpacing: 1.2,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
