import 'dart:async';
import 'package:flutter/material.dart';
import 'auth_gate.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();

    _timer = Timer(const Duration(seconds: 3), () {
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => AuthGate()),
      );
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const bg = Color(0xFF0E3B2E);
    const lightText = Color(0xFFE6F1EC);

    final size = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: bg,
      body: SafeArea(
        child: Stack(
          children: [
            Align(
              alignment: const Alignment(0, -1.5),
              child: Image.asset(
                'assets/images/logo.png',
                width: size.width * 1.5,
                height: size.width * 1.5,
                fit: BoxFit.contain,
              ),
            ),

            Positioned(
              left: 0,
              right: 0,
              bottom: size.height * 0.05,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Visita',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: lightText,
                      fontSize: size.width * 0.12,
                      fontWeight: FontWeight.w800,
                      height: 0.85,
                      letterSpacing: -0.5,
                    ),
                  ),
                  Transform.translate(
                    offset: Offset(0, -size.width * 0.03),
                    child: Text(
                      'Rian',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: lightText,
                        fontSize: size.width * 0.12,
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
                      color: lightText.withOpacity(0.9),
                      fontSize: size.width * 0.033,
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
    );
  }
}
