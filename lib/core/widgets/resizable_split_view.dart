import 'package:flutter/material.dart';

/// A split-view widget with a draggable divider that lets the user adjust
/// the ratio between two children.
///
/// Uses fixed pixel sizes (not Flexible) so children always receive bounded
/// constraints — required for SfPdfViewer's text selection to work.
class ResizableSplitView extends StatefulWidget {
  final Widget firstChild;
  final Widget secondChild;
  final Axis axis;
  final double initialRatio;
  final double minRatio;
  final double maxRatio;

  const ResizableSplitView({
    super.key,
    required this.firstChild,
    required this.secondChild,
    this.axis = Axis.vertical,
    this.initialRatio = 0.4,
    this.minRatio = 0.25,
    this.maxRatio = 0.75,
  });

  @override
  State<ResizableSplitView> createState() => _ResizableSplitViewState();
}

class _ResizableSplitViewState extends State<ResizableSplitView> {
  // ValueNotifier so divider drags rebuild ONLY the layout shell — not the
  // expensive PlatformView children (BetterPlayer, SfPdfViewer). Previously
  // setState on every drag delta was recreating the entire native view tree
  // and tripping the Android ANR watchdog on tablets.
  late final ValueNotifier<double> _ratio;

  // Bumped from 20 → 28 so the divider reads as a real bar (not a hairline
  // gap) and gives users a comfortable touch target. The grip handle inside
  // gets its own contrasting fill so it stays visible regardless of what
  // the two children are painting at the seam (white PDF vs black video).
  static const _dividerThickness = 28.0;

  @override
  void initState() {
    super.initState();
    _ratio = ValueNotifier<double>(widget.initialRatio);
  }

  @override
  void didUpdateWidget(ResizableSplitView oldWidget) {
    super.didUpdateWidget(oldWidget);
    _ratio.value = _ratio.value.clamp(widget.minRatio, widget.maxRatio);
  }

  @override
  void dispose() {
    _ratio.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isVertical = widget.axis == Axis.vertical;

    return LayoutBuilder(
      builder: (context, constraints) {
        final totalSize =
            isVertical ? constraints.maxHeight : constraints.maxWidth;
        final available = totalSize - _dividerThickness;

        // Children are captured ONCE per layout pass and reused across every
        // ratio change — the ValueListenableBuilder only rebuilds the Flex
        // wrapper, not the children themselves.
        final firstChild = widget.firstChild;
        final secondChild = widget.secondChild;
        final divider = _buildDivider(isVertical, totalSize);

        return ValueListenableBuilder<double>(
          valueListenable: _ratio,
          builder: (context, ratio, _) {
            final firstSize = (available * ratio).clamp(0.0, available);
            final secondSize = (available - firstSize).clamp(0.0, available);
            return Flex(
              direction: widget.axis,
              children: [
                SizedBox(
                  width: isVertical ? constraints.maxWidth : firstSize,
                  height: isVertical ? firstSize : constraints.maxHeight,
                  child: firstChild,
                ),
                divider,
                SizedBox(
                  width: isVertical ? constraints.maxWidth : secondSize,
                  height: isVertical ? secondSize : constraints.maxHeight,
                  child: secondChild,
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildDivider(bool isVertical, double totalSize) {
    return MouseRegion(
      cursor: isVertical
          ? SystemMouseCursors.resizeUpDown
          : SystemMouseCursors.resizeLeftRight,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onVerticalDragUpdate: isVertical
            ? (details) => _onDrag(details.delta.dy, totalSize)
            : null,
        onHorizontalDragUpdate: !isVertical
            ? (details) => _onDrag(details.delta.dx, totalSize)
            : null,
        child: Container(
          width: isVertical ? double.infinity : _dividerThickness,
          height: isVertical ? _dividerThickness : double.infinity,
          // Solid dark bar so the divider is visible against either child
          // (PDF white, video black). Hairline borders top/bottom (or
          // left/right in horizontal mode) sharpen the seam.
          decoration: BoxDecoration(
            color: const Color(0xFF1F1F1F),
            border: Border(
              top: isVertical
                  ? const BorderSide(color: Colors.black54, width: 0.5)
                  : BorderSide.none,
              bottom: isVertical
                  ? const BorderSide(color: Colors.black54, width: 0.5)
                  : BorderSide.none,
              left: !isVertical
                  ? const BorderSide(color: Colors.black54, width: 0.5)
                  : BorderSide.none,
              right: !isVertical
                  ? const BorderSide(color: Colors.black54, width: 0.5)
                  : BorderSide.none,
            ),
          ),
          child: Center(
            // Pill-shaped grip handle, sized big enough to be obviously
            // draggable even on a tablet held at arm's length.
            child: Container(
              width: isVertical ? 56 : 5,
              height: isVertical ? 5 : 56,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.85),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _onDrag(double delta, double totalSize) {
    if (totalSize <= 0) return;
    _ratio.value =
        (_ratio.value + delta / totalSize).clamp(widget.minRatio, widget.maxRatio);
  }
}
