import 'package:flutter/material.dart';

/// Position of the line guide: the centre of its reading window as a
/// fraction (0..1) of the book view's height.
class EpubLineGuideController extends ValueNotifier<double> {
  EpubLineGuideController([super.value = 0.3]);

  /// Moves the window so its centre is at [fraction], kept on screen.
  void moveTo(double fraction) => value = fraction.clamp(0.0, 1.0);

  /// Moves by one window height (Apple Books-style "next line").
  void step(int direction, double bandFraction) =>
      moveTo(value + direction * bandFraction);
}

/// A reading window over the page, like Apple Books' Line Guide: the text
/// outside the window is dimmed so the eye stays on a few lines.
///
/// Only the handle on the right takes touches; the page itself stays fully
/// usable (select, tap, swipe). The reader moves the window when a line is
/// tapped and back to the top on a new page.
class EpubLineGuide extends StatelessWidget {
  const EpubLineGuide({
    super.key,
    required this.controller,
    required this.dimming,
    required this.accentColor,
    required this.bandHeight,
    required this.dark,
    this.showHint = false,
    this.stepHeight,
  });

  final EpubLineGuideController controller;
  final double dimming;
  final Color accentColor;

  /// Height of the reading window in logical pixels.
  final double bandHeight;
  final bool dark;

  /// Distance moved by the arrows (whole lines); the window height if null.
  final double? stepHeight;

  /// Shows the "how to move it" hint (first use).
  final bool showHint;

  /// Window rectangle for a view of [height], kept fully on screen.
  static Rect bandRect(double fraction, double band, Size size) {
    final h = band.clamp(24.0, size.height).toDouble();
    final top = (fraction * size.height - h / 2)
        .clamp(0.0, (size.height - h).clamp(0.0, double.infinity))
        .toDouble();
    return Rect.fromLTWH(0, top, size.width, h);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final size = constraints.biggest;
      if (size.height <= 0) return const SizedBox.shrink();
      return ValueListenableBuilder<double>(
        valueListenable: controller,
        builder: (context, fraction, _) {
          final band = bandRect(fraction, bandHeight, size);
          final stepFraction = (stepHeight ?? band.height) / size.height;
          // The handle sits in the dimmed area just below the window (above
          // it near the bottom), so it never covers the lines being read.
          const handleHeight = 36.0;
          final handleTop = band.bottom + 6 + handleHeight <= size.height
              ? band.bottom + 6
              : (band.top - 6 - handleHeight).clamp(0.0, size.height);
          return Stack(children: [
            Positioned.fill(
              child: IgnorePointer(
                child: TweenAnimationBuilder<Rect?>(
                  tween: RectTween(end: band),
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOutCubic,
                  builder: (context, rect, _) => CustomPaint(
                    painter: _GuidePainter(
                      band: rect ?? band,
                      dimming: dimming,
                      accentColor: accentColor,
                      dark: dark,
                    ),
                  ),
                ),
              ),
            ),
            AnimatedPositioned(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              right: 10,
              top: handleTop,
              child: _GuideHandle(
                dark: dark,
                accentColor: accentColor,
                onUp: () => controller.step(-1, stepFraction),
                onDown: () => controller.step(1, stepFraction),
                onDrag: (dy) =>
                    controller.moveTo(controller.value + dy / size.height),
              ),
            ),
            if (showHint)
              Positioned(
                left: 16,
                right: 48,
                top: band.bottom + 52 + 60 > size.height
                    ? (band.top - 104).clamp(0.0, size.height)
                    : band.bottom + 52,
                child: IgnorePointer(
                  child: Center(
                    child: Material(
                      color: dark
                          ? const Color(0xFF2C2C2E)
                          : const Color(0xFF1C1C1E),
                      elevation: 6,
                      borderRadius: BorderRadius.circular(14),
                      child: const Padding(
                        padding:
                            EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        child: Text(
                          'Tap any line to move the guide there, or use the '
                          'arrows.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              color: Colors.white, fontSize: 13, height: 1.3),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ]);
        },
      );
    });
  }
}

class _GuideHandle extends StatelessWidget {
  const _GuideHandle({
    required this.dark,
    required this.accentColor,
    required this.onUp,
    required this.onDown,
    required this.onDrag,
  });

  final bool dark;
  final Color accentColor;
  final VoidCallback onUp;
  final VoidCallback onDown;
  final ValueChanged<double> onDrag;

  @override
  Widget build(BuildContext context) {
    final fg = dark ? Colors.white : const Color(0xFF1C1C1E);
    Widget arrow(IconData icon, String label, VoidCallback onTap) => Semantics(
          button: true,
          label: label,
          child: InkResponse(
            onTap: onTap,
            radius: 20,
            child: SizedBox(
                width: 38, height: 36, child: Icon(icon, size: 22, color: fg)),
          ),
        );
    return Material(
      color: (dark ? const Color(0xFF2C2C2E) : Colors.white)
          .withValues(alpha: 0.94),
      elevation: 3,
      shadowColor: Colors.black38,
      borderRadius: BorderRadius.circular(16),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        arrow(Icons.keyboard_arrow_up, 'Move line guide up', onUp),
        Semantics(
          label: 'Drag to move line guide',
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onVerticalDragUpdate: (d) => onDrag(d.delta.dy),
            child: SizedBox(
              width: 34,
              height: 36,
              child: Icon(Icons.drag_handle, size: 20, color: accentColor),
            ),
          ),
        ),
        arrow(Icons.keyboard_arrow_down, 'Move line guide down', onDown),
      ]),
    );
  }
}

class _GuidePainter extends CustomPainter {
  const _GuidePainter({
    required this.band,
    required this.dimming,
    required this.accentColor,
    required this.dark,
  });

  final Rect band;
  final double dimming;
  final Color accentColor;
  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    final window = RRect.fromRectAndRadius(
        band.deflate(1).inflate(0), const Radius.circular(10));
    final shade = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size)
      ..addRRect(window);
    canvas.drawPath(
        shade,
        Paint()
          ..color = (dark ? Colors.black : const Color(0xFF1C1C1E))
              .withValues(alpha: dimming));
    // A soft tinted edge so the window reads as one shape.
    canvas.drawRRect(
        window,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = accentColor.withValues(alpha: 0.55));
  }

  @override
  bool shouldRepaint(covariant _GuidePainter old) =>
      band != old.band ||
      dimming != old.dimming ||
      accentColor != old.accentColor ||
      dark != old.dark;
}
