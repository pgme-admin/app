import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pgme/main.dart';

// Smoke test: the app builds, wires up its providers and router, and shows
// its first screen without throwing. (This file used to be Flutter's stock
// "counter increments" template, which looked for a counter and a '+' button
// this app has never had, so it could not pass.)
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('MyApp boots into the router and renders its first screen',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(const MyApp());
    await tester.pump();

    // The router-driven MaterialApp is mounted and showing a page.
    expect(find.byType(MaterialApp), findsOneWidget);
    expect(find.byType(Scaffold), findsWidgets);
    expect(tester.takeException(), isNull);

    // Let the splash screen's startup work and timers run out so nothing is
    // left pending when the test ends.
    await tester.pump(const Duration(seconds: 5));
    expect(tester.takeException(), isNull);
  });
}
