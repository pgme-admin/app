import 'dart:math' as math;
import 'dart:ui';

/// One line (or text fragment) of a PDF page with its rectangle in page
/// points, top-left origin (y grows downward).
class PageTextBox {
  final Rect rect;
  final String text;
  const PageTextBox(this.rect, this.text);
}

/// Decides how saved highlight bounds must be read.
///
/// Highlights reach the backend in two coordinate conventions and nothing
/// stored says which one a row uses:
///  * top-left origin, y down — the Syncfusion reader and current pdfrx code;
///  * bottom-left origin, y up (PDF-native) — rows saved by older pdfrx builds.
/// The offset fields cannot tell them apart reliably: early pdfrx rows used the
/// same `start_offset = left edge` marker as Syncfusion, and the backend trims
/// `highlighted_text`, so `end_offset` no longer equals its length.
///
/// So the row is placed both ways and the placement that actually lands on the
/// row's own saved words (the `text` of each bounds entry) wins. Only when the
/// page has no extractable text, or both placements score the same, does it
/// fall back to the marker old pdfrx builds wrote most often (start == 0).
class HighlightPlacement {
  HighlightPlacement._();

  /// Returns true when [bounds] (raw `bounds_data` maps) are stored y-up and
  /// must be flipped (`top = pageHeight - top`) before drawing.
  ///
  /// [pageHeight] and [pageText] are looked up per bounds entry by its
  /// `page_number`; [pageText] may return null or an empty list when the
  /// page text is unavailable.
  static bool isYUp({
    required List<Map<String, dynamic>> bounds,
    required double? Function(int pageNumber) pageHeight,
    required List<PageTextBox>? Function(int pageNumber) pageText,
    required int? startOffset,
  }) {
    final asStored = _score(bounds, pageHeight, pageText, flip: false);
    final flipped = _score(bounds, pageHeight, pageText, flip: true);
    if (asStored != flipped) return flipped > asStored;
    return startOffset == 0;
  }

  /// Stretches a saved line rectangle (top-left origin) vertically to the
  /// text line it sits on, keeping its left/right edges. [lines] are the
  /// page's text boxes in the same coordinates.
  ///
  /// Older rows were saved from each glyph's ink box, whose bottom is the
  /// baseline on lines without descenders and the descender tip on lines
  /// with them. Snapping gives old rows the same line band new annotations
  /// use, so their highlights and underlines line up too. Returns [rect]
  /// unchanged when no text line matches.
  static Rect snapToTextLine(Rect rect, List<PageTextBox> lines) {
    double? top;
    double? bottom;
    for (final line in lines) {
      final overlap = rect.intersect(line.rect);
      if (overlap.width <= 0 || overlap.height <= 0) continue;
      // Same rule as _score: share most of the line's height, not graze it.
      if (overlap.height < 0.5 * math.min(rect.height, line.rect.height)) {
        continue;
      }
      top = top == null ? line.rect.top : math.min(top, line.rect.top);
      bottom = bottom == null
          ? line.rect.bottom
          : math.max(bottom, line.rect.bottom);
    }
    if (top == null || bottom == null) return rect;
    return Rect.fromLTRB(rect.left, top, rect.right, bottom);
  }

  static String _normalize(String s) =>
      s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

  /// Number of bounds entries whose rectangle covers its own saved text.
  static int _score(
    List<Map<String, dynamic>> bounds,
    double? Function(int pageNumber) pageHeight,
    List<PageTextBox>? Function(int pageNumber) pageText, {
    required bool flip,
  }) {
    var hits = 0;
    for (final b in bounds) {
      final want = _normalize(b['text'] as String? ?? '');
      final page = (b['page_number'] as num?)?.toInt();
      if (want.isEmpty || page == null) continue;
      final lines = pageText(page);
      final h = pageHeight(page);
      if (lines == null || lines.isEmpty || h == null) continue;

      final top = (b['top'] as num).toDouble();
      final rect = Rect.fromLTWH(
        (b['left'] as num).toDouble(),
        flip ? h - top : top,
        (b['width'] as num).toDouble(),
        (b['height'] as num).toDouble(),
      );

      final covered = StringBuffer();
      for (final line in lines) {
        final overlap = rect.intersect(line.rect);
        if (overlap.width <= 0 || overlap.height <= 0) continue;
        // Must share most of a line's height, not just graze it.
        if (overlap.height < 0.5 * math.min(rect.height, line.rect.height)) {
          continue;
        }
        covered.write(line.text);
      }

      final probe = want.length > 12 ? want.substring(0, 12) : want;
      if (_normalize(covered.toString()).contains(probe)) hits++;
    }
    return hits;
  }
}
