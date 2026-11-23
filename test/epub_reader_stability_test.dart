import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pgme/core/utils/epub_reader_theme.dart';

void main() {
  group('page colour', () {
    // Page-turn stills, the curl and the loading cover are drawn on this
    // colour; it must be exactly the page's, or the page blinks mid-turn
    // (white on Warm before the fix).
    test('matches the reading page for every theme', () {
      for (final theme in EpubReadingTheme.values) {
        for (final appDark in [false, true]) {
          final page =
              epubReadingTheme(theme, EpubReadingFont.original, appDark)
                  .backgroundDecoration as BoxDecoration;
          expect(epubPageColor(theme, appDark), page.color,
              reason: '$theme appDark=$appDark');
        }
      }
    });

    test('warm is the warm paper, not white', () {
      expect(
          epubPageColor(EpubReadingTheme.warm, false), const Color(0xFFF7F0E3));
      expect(epubPageColor(EpubReadingTheme.warm, false), isNot(Colors.white));
      expect(
          epubPageColor(EpubReadingTheme.dark, false), const Color(0xFF121212));
      expect(epubPageColor(EpubReadingTheme.followApp, true),
          const Color(0xFF121212));
      expect(epubPageColor(EpubReadingTheme.light, true), Colors.white);
    });
  });

  group('reader insets ignore the keyboard', () {
    const noKeyboard = MediaQueryData(
      size: Size(402, 874),
      padding: EdgeInsets.only(top: 62, bottom: 34),
      viewPadding: EdgeInsets.only(top: 62, bottom: 34),
    );
    // What Flutter reports while the keyboard is up: the bottom padding is
    // consumed by the keyboard.
    const keyboardUp = MediaQueryData(
      size: Size(402, 874),
      padding: EdgeInsets.only(top: 62),
      viewPadding: EdgeInsets.only(top: 62, bottom: 34),
      viewInsets: EdgeInsets.only(bottom: 336),
    );

    test('same insets with and without a keyboard', () {
      final a = readerMediaWithoutKeyboard(noKeyboard);
      final b = readerMediaWithoutKeyboard(keyboardUp);
      expect(b.padding, a.padding);
      expect(b.viewInsets, EdgeInsets.zero);
      expect(b.padding.bottom, 34);
      expect(b.padding.top, 62);
    });

    testWidgets('a bottom bar keeps its height when the keyboard shows',
        (tester) async {
      Future<double> barHeight(MediaQueryData media) async {
        await tester.pumpWidget(MediaQuery(
          data: readerMediaWithoutKeyboard(media),
          child: const Directionality(
            textDirection: TextDirection.ltr,
            child: Align(
              alignment: Alignment.bottomCenter,
              child: SafeArea(
                  top: false, child: SizedBox(key: Key('bar'), height: 50)),
            ),
          ),
        ));
        return tester.getSize(find.byType(SafeArea)).height;
      }

      final without = await barHeight(noKeyboard);
      final withKeyboard = await barHeight(keyboardUp);
      expect(without, 84);
      expect(withKeyboard, without);
    });
  });
}
