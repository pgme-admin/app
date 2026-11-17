import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pgme/core/widgets/resizable_split_view.dart';

// The video + PDF split view shares one ratio between portrait (vertical) and
// landscape (horizontal). A video made large in portrait used to squeeze the
// PDF pane to ~25% of the landscape width, cutting off the reader's toolbar
// ("RIGHT OVERFLOWED BY 59 PIXELS"). minSecondExtent keeps it usable.
void main() {
  const divider = 28.0; // ResizableSplitView's divider thickness

  Future<Size> pumpSplit(
    WidgetTester tester, {
    required Size screen,
    required Axis axis,
    required double initialRatio,
    double minSecondExtent = 0,
  }) async {
    tester.view.physicalSize = screen;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: ResizableSplitView(
        axis: axis,
        initialRatio: initialRatio,
        minRatio: 0.25,
        maxRatio: 0.75,
        minSecondExtent: minSecondExtent,
        firstChild: const ColoredBox(color: Colors.black, key: Key('first')),
        secondChild: const ColoredBox(color: Colors.white, key: Key('second')),
      ),
    ));
    return tester.getSize(find.byKey(const Key('second')));
  }

  testWidgets('landscape: PDF pane never narrower than minSecondExtent',
      (tester) async {
    // iPhone 17 in landscape, video previously enlarged to the 0.75 maximum.
    final second = await pumpSplit(tester,
        screen: const Size(874, 402),
        axis: Axis.horizontal,
        initialRatio: 0.75,
        minSecondExtent: 360);
    expect(second.width, greaterThanOrEqualTo(360 - 1e-6));
    expect(tester.getSize(find.byKey(const Key('first'))).width,
        closeTo(874 - divider - 360, 0.5));
  });

  testWidgets('landscape: dragging the divider cannot squeeze the PDF pane',
      (tester) async {
    await pumpSplit(tester,
        screen: const Size(874, 402),
        axis: Axis.horizontal,
        initialRatio: 0.4,
        minSecondExtent: 360);
    // Drag the divider far towards the PDF side.
    final dividerCenter = tester.getTopRight(find.byKey(const Key('first'))) +
        const Offset(divider / 2, 201);
    await tester.dragFrom(dividerCenter, const Offset(600, 0));
    await tester.pump();
    expect(tester.getSize(find.byKey(const Key('second'))).width,
        greaterThanOrEqualTo(360 - 1e-6));
  });

  testWidgets('portrait: the user-chosen ratio is unchanged', (tester) async {
    final second = await pumpSplit(tester,
        screen: const Size(402, 874),
        axis: Axis.vertical,
        initialRatio: 0.75);
    expect(tester.getSize(find.byKey(const Key('first'))).height,
        closeTo((874 - divider) * 0.75, 0.5));
    expect(second.height, closeTo((874 - divider) * 0.25, 0.5));
  });

  testWidgets('without minSecondExtent the old limits still apply',
      (tester) async {
    final second = await pumpSplit(tester,
        screen: const Size(874, 402),
        axis: Axis.horizontal,
        initialRatio: 0.75);
    expect(second.width, closeTo((874 - divider) * 0.25, 0.5));
  });
}
