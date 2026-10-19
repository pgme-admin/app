import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:pgme/core/providers/theme_provider.dart';
import 'package:pgme/core/widgets/terms_gate_sheet.dart';

/// The gate exists so that "agreed" means the document was actually scrolled
/// through. These tests pin that down: a user must not be able to accept
/// without reaching the end, and must not be *stuck* when there is no end to
/// scroll to.
Widget _host(Widget child) {
  return ChangeNotifierProvider<ThemeProvider>(
    create: (_) => ThemeProvider(),
    child: MaterialApp(home: Scaffold(body: child)),
  );
}

ElevatedButton _agreeButton(WidgetTester tester) {
  return tester.widget<ElevatedButton>(
    find.ancestor(
      of: find.text('I Agree'),
      matching: find.byType(ElevatedButton),
    ),
  );
}

void main() {
  group('TermsGateSheet', () {
    testWidgets('"I Agree" is disabled before the document is scrolled', (tester) async {
      // A short viewport guarantees the terms overflow and must be scrolled.
      tester.view.physicalSize = const Size(400, 700);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_host(const TermsGateSheet()));
      await tester.pumpAndSettle();

      expect(_agreeButton(tester).onPressed, isNull,
          reason: 'agreement must not be possible before reading');
      expect(find.text('Scroll to the bottom to continue'), findsOneWidget);
    });

    testWidgets('scrolling to the bottom enables "I Agree"', (tester) async {
      tester.view.physicalSize = const Size(400, 700);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_host(const TermsGateSheet()));
      await tester.pumpAndSettle();

      expect(_agreeButton(tester).onPressed, isNull);

      final scrollable = find.byType(Scrollable).first;
      await tester.scrollUntilVisible(
        find.textContaining('support@pgmemedicalteaching.com'),
        600,
        scrollable: scrollable,
      );
      await tester.pumpAndSettle();

      expect(_agreeButton(tester).onPressed, isNotNull,
          reason: 'reaching the end of the terms should unlock agreement');
      expect(find.text('Scroll to the bottom to continue'), findsNothing);
    });

    testWidgets('a viewport tall enough to fit the terms does not trap the user', (tester) async {
      // Without the post-frame "already at the end" check, a document that
      // needs no scrolling would leave the button permanently disabled.
      tester.view.physicalSize = const Size(1200, 20000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_host(const TermsGateSheet()));
      await tester.pumpAndSettle();

      expect(_agreeButton(tester).onPressed, isNotNull,
          reason: 'nothing to scroll means the document has been shown in full');
    });
  });
}
