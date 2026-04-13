import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:visitarian_flutter/app/app.dart';
import 'package:visitarian_flutter/app/bootstrap.dart';

Future<void> main() async {
  try {
    await bootstrapApp(() async {
      runApp(const VisitaRianApp());
    });
  } catch (error, stackTrace) {
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: error,
        stack: stackTrace,
        library: 'app bootstrap',
        context: ErrorDescription('while starting VisitaRian'),
      ),
    );
    runApp(_BootstrapErrorApp(error: error));
  }
}

class _BootstrapErrorApp extends StatelessWidget {
  const _BootstrapErrorApp({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: const Color(0xFFF6F3EE),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: const [
                    BoxShadow(
                      blurRadius: 24,
                      color: Color(0x14000000),
                      offset: Offset(0, 12),
                    ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'App startup failed',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Local web runs need the expected Firebase and API values. '
                        'Start Flutter with --dart-define-from-file=.env.',
                      ),
                      const SizedBox(height: 16),
                      SelectableText(
                        error.toString(),
                        style: Theme.of(
                          context,
                        ).textTheme.bodyMedium?.copyWith(
                          fontFamily: 'monospace',
                        ),
                      ),
                      if (kDebugMode) ...[
                        const SizedBox(height: 16),
                        const SelectableText(
                          'Example:\nflutter run -d chrome --dart-define-from-file=.env',
                          style: TextStyle(fontFamily: 'monospace'),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
