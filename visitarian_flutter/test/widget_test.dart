// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter_test/flutter_test.dart';

import 'package:visitarian_flutter/main.dart';

void main() {
  testWidgets('Splash screen is shown on startup', (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());

    expect(find.text('Visita'), findsOneWidget);
    expect(find.text('Rian'), findsOneWidget);
    expect(find.text('Explore through your eyes'), findsOneWidget);
  });
}
