import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:pgme/core/utils/page_slot_layout.dart';

// The view a page fills at its whole-page zoom, centred on the page.
Rect fittedView(Rect page, Size view) {
  final zoom = math.min(view.width / page.width, view.height / page.height);
  return Rect.fromCenter(
      center: page.center,
      width: view.width / zoom,
      height: view.height / zoom);
}

// Float tolerance: edges that touch must not count as overlapping, and a
// page that exactly fills the view is fully inside it.
bool showsAnyOf(Rect visible, Rect page) => visible.deflate(0.01).overlaps(page);
bool fullyShows(Rect visible, Rect page) =>
    visible.inflate(0.01).contains(page.topLeft) &&
    visible.inflate(0.01).contains(page.bottomRight);

void main() {
  const a4 = Size(595.32, 841.92);

  test('portrait phone: at page zoom only that page is on screen', () {
    const view = Size(393, 644); // iPhone 17 reader area
    final layout =
        PageSlotLayout.compute([a4, a4, a4], view.height / view.width);
    final visible = fittedView(layout.pageRects[1], view);
    expect(showsAnyOf(visible, layout.pageRects[0]), isFalse);
    expect(showsAnyOf(visible, layout.pageRects[2]), isFalse);
    // The whole page is visible, centred.
    expect(fullyShows(visible, layout.pageRects[1]), isTrue);
  });

  test('landscape: pages are fitted by height, still one per screen', () {
    const view = Size(852, 330);
    final layout = PageSlotLayout.compute([a4, a4], view.height / view.width);
    final visible = fittedView(layout.pageRects[0], view);
    expect(visible.height, closeTo(a4.height, 0.01));
    expect(showsAnyOf(visible, layout.pageRects[1]), isFalse);
    expect(fullyShows(visible, layout.pageRects[0]), isTrue);
  });

  test('mixed page sizes keep every page centred in its own slot', () {
    const cover = Size(500, 700);
    const view = Size(400, 700);
    final layout = PageSlotLayout.compute([cover, a4, cover], 700 / 400);
    for (int i = 0; i < 3; i++) {
      final visible = fittedView(layout.pageRects[i], view);
      for (int j = 0; j < 3; j++) {
        if (j == i) continue;
        expect(showsAnyOf(visible, layout.pageRects[j]), isFalse,
            reason: 'page ${i + 1} view shows page ${j + 1}');
      }
    }
    expect(layout.pageRects.first.center.dx,
        closeTo(layout.documentSize.width / 2, 0.001));
  });
}
