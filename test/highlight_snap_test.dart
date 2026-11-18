import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:pgme/core/utils/highlight_placement.dart';

// Line boxes (top-left origin, page points) shaped like page 150 of
// "The Essentials of Community Medicine": 12pt text, 14.5pt line pitch,
// each box running from the tallest letters to descender depth.
void main() {
  final lines = [
    // "Supportive supervision is a facilitative ..." (has descenders)
    const PageTextBox(Rect.fromLTRB(42, 400.0, 540, 413.0), 'Supportive supervision'),
    // "improving performance rather than fault-finding."
    const PageTextBox(Rect.fromLTRB(42, 414.5, 300, 427.5), 'improving performance'),
    // "Dashboard reviews" (no descenders; same band shape after the fix)
    const PageTextBox(Rect.fromLTRB(70, 600.0, 160, 613.0), 'Dashboard reviews'),
    const PageTextBox(Rect.fromLTRB(70, 614.5, 175, 627.5), 'On-site mentoring notes'),
  ];

  test('old ink-box row on a line without descenders snaps to the full line band', () {
    // Saved by an older build: bottom = baseline (610.2), so an underline
    // drawn at its bottom cut through the letters.
    final r = HighlightPlacement.snapToTextLine(
        const Rect.fromLTRB(70, 601.5, 160, 610.2), lines);
    expect(r, const Rect.fromLTRB(70, 600.0, 160, 613.0));
  });

  test('keeps the saved left/right edges (a partial-line selection)', () {
    final r = HighlightPlacement.snapToTextLine(
        const Rect.fromLTRB(120, 401.0, 260, 412.6), lines);
    expect(r.left, 120);
    expect(r.right, 260);
    expect(r.top, 400.0);
    expect(r.bottom, 413.0);
  });

  test('does not jump to the neighbouring line when the boxes touch', () {
    // A row that grazes the next line by 1pt still belongs to its own line.
    final r = HighlightPlacement.snapToTextLine(
        const Rect.fromLTRB(42, 401.0, 300, 415.5), lines);
    expect(r.top, 400.0);
    expect(r.bottom, 413.0);
  });

  test('row with no matching text line is left unchanged', () {
    const saved = Rect.fromLTRB(42, 700, 300, 712);
    expect(HighlightPlacement.snapToTextLine(saved, lines), saved);
    expect(HighlightPlacement.snapToTextLine(saved, const []), saved);
  });
}
