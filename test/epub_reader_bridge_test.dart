import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pgme/core/utils/epub_annotation.dart';
import 'package:pgme/core/utils/epub_reader_bridge.dart';
import 'package:pgme/core/utils/epub_reader_theme.dart';

void main() {
  group('EpubTapTarget.fromJson', () {
    test('parses an image tap from the page (JSON string)', () {
      final t = EpubTapTarget.fromJson(jsonEncode({
        'kind': 'image',
        'src': 'blob:null/abc',
        'label': 'Table 41.1',
        'rect': {'left': 0.1, 'top': 0.2, 'width': 0.8, 'height': 0.3},
      }));
      expect(t.kind, 'image');
      expect(t.src, 'blob:null/abc');
      expect(t.label, 'Table 41.1');
      expect(t.rect!.left, closeTo(0.1, 1e-9));
      expect(t.rect!.height, closeTo(0.3, 1e-9));
    });

    test('parses annotation hits and ignores malformed ones', () {
      final t = EpubTapTarget.fromJson({
        'kind': 'annotation',
        'annotations': [
          {'cfi': 'epubcfi(/6/4!/4/2,/1:0,/1:5)', 'type': 'highlight'},
          {'cfi': 42, 'type': 'underline'},
          'junk',
        ],
        'rect': null,
      });
      expect(t.kind, 'annotation');
      expect(t.annotations, hasLength(1));
      expect(t.annotations.single.type, 'highlight');
      expect(t.rect, isNull);
    });

    test('anything unexpected is a plain tap', () {
      expect(EpubTapTarget.fromJson(null).kind, 'none');
      expect(EpubTapTarget.fromJson('not json at all'.length).kind, 'none');
      expect(EpubTapTarget.fromJson(<String, dynamic>{}).kind, 'none');
    });
  });

  test('annotation keys separate a highlight and an underline on one range',
      () {
    const cfi = 'epubcfi(/6/4!/4/2,/1:0,/1:5)';
    final h = EpubAnnotation(cfi: cfi, type: 'highlight');
    final u = EpubAnnotation(cfi: cfi, type: 'underline');
    expect(h.key, isNot(u.key));
    expect(h.key, EpubAnnotation.keyFor('highlight', cfi));
    expect(h.isHighlight, isTrue);
    expect(u.isHighlight, isFalse);
  });

  test('page turn preference: old values still load, unknown is Slide', () {
    expect(pageTurnFromName('slide'), EpubPageTurn.slide);
    expect(pageTurnFromName('fastFade'), EpubPageTurn.fastFade);
    expect(pageTurnFromName('curl'), EpubPageTurn.curl);
    expect(pageTurnFromName('bogus'), EpubPageTurn.slide);
    expect(pageTurnFromName(null), EpubPageTurn.slide);
  });
}
