import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:visitarian_flutter/app/app.dart';
import 'package:visitarian_flutter/app/bootstrap.dart';

Future<void> main() async {
  try {
    await bootstrapApp(() async {
      runApp(const VisitaRianApp());
    });
  } catch (e, stackTrace) {
    runApp(_StartupFailureApp(error: e, stackTrace: stackTrace));
  }
}

class _StartupFailureApp extends StatelessWidget {
  const _StartupFailureApp({required this.error, required this.stackTrace});

  final Object error;
  final StackTrace stackTrace;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.error_outline, color: Colors.red, size: 40),
                const SizedBox(height: 12),
                const Text(
                  'Startup failed',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                Text(error.toString()),
                if (kDebugMode) ...[
                  const SizedBox(height: 12),
                  Expanded(
                    child: SingleChildScrollView(
                      child: Text(stackTrace.toString()),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
