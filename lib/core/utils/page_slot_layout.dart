import 'dart:math' as math;
import 'dart:ui';

/// Page positions for the one-page-at-a-time PDF reader.
///
/// Pages are stacked vertically, each centred in a "slot" with the view's
/// shape (`viewAspect` = view height / view width) and never smaller than the
/// page itself. At the zoom that fits a page whole into the view, its slot
/// fills the view exactly, so nothing of the neighbouring pages shows.
class PageSlotLayout {
  PageSlotLayout._(this.pageRects, this.documentSize);

  /// Where each page is drawn, in document coordinates (page points).
  final List<Rect> pageRects;

  /// Size of the whole document (all slots).
  final Size documentSize;

  static PageSlotLayout compute(List<Size> pageSizes, double viewAspect) {
    double docW = 0;
    for (final s in pageSizes) {
      docW = math.max(docW, math.max(s.width, s.height / viewAspect));
    }
    final rects = <Rect>[];
    var y = 0.0;
    for (final s in pageSizes) {
      final slotH = math.max(s.height, s.width * viewAspect);
      rects.add(Rect.fromLTWH(
          (docW - s.width) / 2, y + (slotH - s.height) / 2, s.width, s.height));
      y += slotH;
    }
    return PageSlotLayout._(rects, Size(docW, y));
  }
}
