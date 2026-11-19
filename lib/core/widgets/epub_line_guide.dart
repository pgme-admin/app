import 'package:flutter/material.dart';

/// A movable reading band that leaves page taps and text selection available.
class EpubLineGuide extends StatefulWidget {
  const EpubLineGuide(
      {super.key, required this.dimming, required this.accentColor});

  final double dimming;
  final Color accentColor;

  @override
  State<EpubLineGuide> createState() => _EpubLineGuideState();
}

class _EpubLineGuideState extends State<EpubLineGuide> {
  double _position = 0.5;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final height = constraints.maxHeight;
          final bandHeight = height < 56
              ? height
              : (height * 0.105).clamp(56.0, 92.0).toDouble();
          final top = (_position * height - bandHeight / 2)
              .clamp(0.0, height - bandHeight)
              .toDouble();
          return Stack(children: [
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: _GuidePainter(
                    top: top,
                    bandHeight: bandHeight,
                    dimming: widget.dimming,
                    accentColor: widget.accentColor,
                  ),
                ),
              ),
            ),
            Positioned(
              right: 40,
              top: (top + bandHeight / 2 - 27)
                  .clamp(0.0, height < 54 ? 0.0 : height - 54)
                  .toDouble(),
              child: Semantics(
                label: 'Move reading guide',
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onVerticalDragUpdate: (details) => setState(() {
                    _position = (_position + details.delta.dy / height)
                        .clamp(0.05, 0.95)
                        .toDouble();
                  }),
                  child: SizedBox(
                    width: 36,
                    height: 54,
                    child: Center(
                      child: Container(
                        width: 5,
                        height: 32,
                        decoration: BoxDecoration(
                          color: widget.accentColor,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ]);
        },
      );
}

class _GuidePainter extends CustomPainter {
  const _GuidePainter({
    required this.top,
    required this.bandHeight,
    required this.dimming,
    required this.accentColor,
  });

  final double top;
  final double bandHeight;
  final double dimming;
  final Color accentColor;

  @override
  void paint(Canvas canvas, Size size) {
    final shade = Paint()..color = Colors.black.withValues(alpha: dimming);
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, top), shade);
    canvas.drawRect(
      Rect.fromLTWH(
          0, top + bandHeight, size.width, size.height - top - bandHeight),
      shade,
    );
    final line = Paint()
      ..color = accentColor.withValues(alpha: 0.45)
      ..strokeWidth = 1;
    canvas.drawLine(Offset(0, top), Offset(size.width, top), line);
    canvas.drawLine(Offset(0, top + bandHeight),
        Offset(size.width, top + bandHeight), line);
  }

  @override
  bool shouldRepaint(covariant _GuidePainter oldDelegate) =>
      top != oldDelegate.top ||
      bandHeight != oldDelegate.bandHeight ||
      dimming != oldDelegate.dimming ||
      accentColor != oldDelegate.accentColor;
}
