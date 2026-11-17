import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:pgme/core/utils/highlight_placement.dart';

// Coordinates below are taken from real saved highlights on page 1 of
// "The Essentials of Community Medicine 3rd Edition" (page height 841.92pt),
// which rendered in the wrong place before placement checked the page text.
void main() {
  const pageHeight = 841.92;

  // Page 1 text lines, top-left origin (y down), in page points.
  final page1 = [
    const PageTextBox(Rect.fromLTRB(76, 152, 516, 192), 'THE ESSENTIALS'),
    const PageTextBox(Rect.fromLTRB(198, 372, 396, 391), 'THIRD EDITION'),
    const PageTextBox(Rect.fromLTRB(222, 466, 378, 482), 'Editor in Chief'),
    const PageTextBox(Rect.fromLTRB(263, 610, 514, 626), 'Dr. Swathi V Koramboor'),
    const PageTextBox(Rect.fromLTRB(263, 650, 468, 672), 'Dr. Anamica Suresh'),
  ];

  double? height(int page) => page == 1 ? pageHeight : null;
  List<PageTextBox>? text(int page) => page == 1 ? page1 : null;

  Map<String, dynamic> bound(double left, double top, double w, double h,
          String t) =>
      {'left': left, 'top': top, 'width': w, 'height': h, 'text': t, 'page_number': 1};

  test('old pdfrx row with Syncfusion-style offsets (start = left edge) is y-up', () {
    // Saved 2026-05-04: start_offset 303 / end_offset 393, yet the bounds are
    // PDF-native y-up. Read as top-left it lands on the book title instead.
    final yUp = HighlightPlacement.isYUp(
      bounds: [bound(303.0, 186.62, 90.22, 16.01, 'Anamica')],
      pageHeight: height,
      pageText: text,
      startOffset: 303,
    );
    expect(yUp, isTrue);
  });

  test('old pdfrx row whose end_offset != trimmed text length is still y-up', () {
    // start 0 / end 7 but highlighted_text "Chief" (5): the backend trims it.
    final yUp = HighlightPlacement.isYUp(
      bounds: [bound(320.02, 359.38, 57.85, 16.13, 'Chief')],
      pageHeight: height,
      pageText: text,
      startOffset: 0,
    );
    expect(yUp, isTrue);
  });

  test('a top-left (Syncfusion / current pdfrx) row is left as stored', () {
    final yUp = HighlightPlacement.isYUp(
      bounds: [bound(306.0, 652.0, 66.8, 18.0, 'Anamica')],
      pageHeight: height,
      pageText: text,
      startOffset: 306,
    );
    expect(yUp, isFalse);
  });

  test('with no page text it falls back to the old pdfrx marker', () {
    List<PageTextBox>? none(int _) => null;
    expect(
      HighlightPlacement.isYUp(
        bounds: [bound(303.98, 221.74, 66.79, 16.13, 'Swathi')],
        pageHeight: height,
        pageText: none,
        startOffset: 0,
      ),
      isTrue,
    );
    expect(
      HighlightPlacement.isYUp(
        bounds: [bound(303.0, 186.62, 90.22, 16.01, 'Anamica')],
        pageHeight: height,
        pageText: none,
        startOffset: 303,
      ),
      isFalse,
    );
  });
}
