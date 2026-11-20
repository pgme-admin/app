import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pgme/core/utils/epub_annotation.dart';
import 'package:pgme/core/utils/epub_reader_bridge.dart';
import 'package:pgme/core/utils/epub_search.dart';
import 'package:pgme/core/widgets/epub_markup_focus.dart';

void main() {
  group('tap results', () {
    test('a tap on a note badge says so', () {
      final t = EpubTapTarget.fromJson(jsonEncode({
        'kind': 'annotation',
        'noteTap': true,
        'annotations': [
          {'cfi': 'epubcfi(/6/4!/4/2,/1:0,/1:5)', 'type': 'highlight'}
        ],
      }));
      expect(t.noteTap, isTrue);
      expect(t.annotations.single.type, 'highlight');
    });

    test('tables and figures carry their place on the page', () {
      final t = EpubTapTarget.fromJson({
        'kind': 'table',
        'label': 'Table 41.2 Colour coding',
        'rect': {'left': 0.05, 'top': 0.3, 'width': 0.9, 'height': 0.4},
      });
      expect(t.kind, 'table');
      expect(t.label, 'Table 41.2 Colour coding');
      expect(t.noteTap, isFalse);
      expect(t.rect!.width, closeTo(0.9, 1e-9));
    });
  });

  group('overlapping annotations', () {
    test('parses the overlapped marks and the joined range', () {
      final o = EpubOverlap.fromJson(jsonEncode({
        'cfis': ['epubcfi(/6/4!/4/2,/1:0,/1:5)', 7, null],
        'union': 'epubcfi(/6/4!/4/2,/1:0,/1:20)',
        'text': 'Biomedical waste',
      }))!;
      expect(o.cfis, ['epubcfi(/6/4!/4/2,/1:0,/1:5)']);
      expect(o.union, 'epubcfi(/6/4!/4/2,/1:0,/1:20)');
      expect(o.text, 'Biomedical waste');
    });

    test('no usable range means no merge', () {
      expect(EpubOverlap.fromJson(null), isNull);
      expect(EpubOverlap.fromJson({'cfis': [], 'union': 'nonsense'}), isNull);
    });

    test('a merged mark remembers what it replaced; notes are detected', () {
      final old = EpubAnnotation(cfi: 'a', type: 'highlight', note: '  ');
      final merged = EpubAnnotation(cfi: 'b', type: 'highlight', note: 'x')
        ..replaced = [old];
      expect(old.hasNote, isFalse);
      expect(merged.hasNote, isTrue);
      expect(merged.replaced.single.cfi, 'a');
    });
  });

  group('page numbers', () {
    test('parses printed, fixed and text page numbers', () {
      final p = EpubPageInfo.fromJson(
          jsonEncode({'mode': 'print', 'current': 12, 'total': 340}))!;
      expect(p.mode, 'print');
      expect(p.current, 12);
      expect(p.total, 340);
      final f = EpubPageInfo.fromJson(
          {'mode': 'fixed', 'current': null, 'total': 9})!;
      expect(f.current, isNull);
    });

    test('a book without page numbers has none', () {
      expect(EpubPageInfo.fromJson(null), isNull);
      expect(EpubPageInfo.fromJson({'mode': null}), isNull);
      expect(EpubPageInfo.fromJson({'mode': 'locations', 'total': 0}), isNull);
    });
  });

  group('table and figure focus page', () {
    test('reads page colours from the book; transparent falls back', () {
      expect(cssColor('rgb(255, 255, 255)'), const Color(0xFFFFFFFF));
      expect(cssColor('rgba(18, 18, 20, 1)'), const Color(0xFF121214));
      expect(cssColor('rgba(0, 0, 0, 0)'), isNull);
      expect(cssColor('transparent'), isNull);
    });

    test('a wide table starts fitted to the screen; a narrow one at 1:1', () {
      const wide = EpubFocusMarkup(
          html: '<table><tr><td>A</td></tr></table>',
          width: 900,
          background: '',
          color: '',
          fontFamily: '',
          fontSize: '');
      final page = epubMarkupPage(wide,
          screenWidth: 390, background: Colors.white, foreground: Colors.black);
      expect(page, contains('width=932'));
      expect(page, contains('<table><tr><td>A</td></tr></table>'));
      expect(page, contains('user-scalable=yes'));
      const narrow = EpubFocusMarkup(
          html: '<table></table>',
          width: 200,
          background: '',
          color: '',
          fontFamily: 'Georgia',
          fontSize: '18px');
      final small = epubMarkupPage(narrow,
          screenWidth: 390, background: Colors.white, foreground: Colors.black);
      expect(small, contains('width=390'));
      expect(small, contains('font-family:Georgia'));
      expect(small, contains('font-size:18px'));
    });
  });

  test('search excerpts show every match in bold, ignoring case', () {
    final span = searchExcerpt('Waste is waste; WASTE rules', 'waste');
    final bold = span.children!
        .whereType<TextSpan>()
        .where((s) => s.style?.fontWeight == FontWeight.w700)
        .map((s) => s.text)
        .toList();
    expect(bold, ['Waste', 'waste', 'WASTE']);
    expect(searchExcerpt('plain', '').text, 'plain');
  });
}
