import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Lifts a book image off the page into a focused, zoomable view, the way
/// Apple Books does: the image grows from where it sits on the page, the page
/// dims behind it, and closing returns it to the same spot.
///
/// Pinch or double-tap to zoom, drag to pan while zoomed, drag down (or tap
/// the close button, press Escape or go back) to close.
Future<void> showEpubImageFocus(
  BuildContext context, {
  required Uint8List bytes,
  required Rect origin,
  String? label,
}) async {
  final ui.Image image;
  try {
    final codec = await ui.instantiateImageCodec(bytes);
    image = (await codec.getNextFrame()).image;
    codec.dispose();
  } catch (e) {
    debugPrint('[EPUB] image could not be decoded: $e');
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('This image could not be opened.')));
    }
    return;
  }
  if (!context.mounted) {
    image.dispose();
    return;
  }
  final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
  await Navigator.of(context, rootNavigator: true).push(PageRouteBuilder<void>(
    opaque: false,
    barrierColor: null,
    transitionDuration:
        reduceMotion ? Duration.zero : const Duration(milliseconds: 320),
    reverseTransitionDuration:
        reduceMotion ? Duration.zero : const Duration(milliseconds: 260),
    pageBuilder: (context, animation, _) => _ImageFocus(
      image: image,
      origin: origin,
      label: label,
      animation: animation,
    ),
  ));
  // Freed after the closing animation has finished drawing it.
  WidgetsBinding.instance.addPostFrameCallback((_) => image.dispose());
}

class _ImageFocus extends StatefulWidget {
  const _ImageFocus({
    required this.image,
    required this.origin,
    required this.animation,
    this.label,
  });

  final ui.Image image;
  final Rect origin;
  final String? label;
  final Animation<double> animation;

  @override
  State<_ImageFocus> createState() => _ImageFocusState();
}

class _ImageFocusState extends State<_ImageFocus>
    with SingleTickerProviderStateMixin {
  static const double _maxScale = 5;

  double _scale = 1;
  Offset _offset = Offset.zero;
  // Drag-to-close offset, used while the image is not zoomed.
  Offset _dismissDrag = Offset.zero;
  bool _dismissing = false;

  double _startScale = 1;
  Offset _startOffset = Offset.zero;
  Offset _startFocal = Offset.zero;
  Offset? _doubleTapAt;

  late final AnimationController _settle = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 220));
  Animation<double>? _scaleAnim;
  Animation<Offset>? _offsetAnim;
  Animation<Offset>? _dragAnim;

  @override
  void initState() {
    super.initState();
    _settle.addListener(() {
      setState(() {
        if (_scaleAnim != null) _scale = _scaleAnim!.value;
        if (_offsetAnim != null) _offset = _offsetAnim!.value;
        if (_dragAnim != null) _dismissDrag = _dragAnim!.value;
      });
    });
  }

  @override
  void dispose() {
    _settle.dispose();
    super.dispose();
  }

  Size get _imageSize =>
      Size(widget.image.width.toDouble(), widget.image.height.toDouble());

  /// Where the image rests when focused: as large as fits, centred.
  Rect _restingRect(Size screen, EdgeInsets padding) {
    final area = Rect.fromLTRB(16, padding.top + 56, screen.width - 16,
        screen.height - math.max(padding.bottom, 16) - 24);
    final fitted = applyBoxFit(BoxFit.contain, _imageSize, area.size).destination;
    return Alignment.center.inscribe(fitted, area);
  }

  void _animateTo({double? scale, Offset? offset, Offset? drag}) {
    _scaleAnim = scale == null
        ? null
        : Tween(begin: _scale, end: scale).animate(
            CurvedAnimation(parent: _settle, curve: Curves.easeOutCubic));
    _offsetAnim = offset == null
        ? null
        : Tween(begin: _offset, end: offset).animate(
            CurvedAnimation(parent: _settle, curve: Curves.easeOutCubic));
    _dragAnim = drag == null
        ? null
        : Tween(begin: _dismissDrag, end: drag).animate(
            CurvedAnimation(parent: _settle, curve: Curves.easeOutCubic));
    _settle.forward(from: 0);
  }

  Offset _clampOffset(Offset offset, double scale, Rect resting) {
    final maxX = math.max(0.0, (resting.width * scale - resting.width) / 2);
    final maxY = math.max(0.0, (resting.height * scale - resting.height) / 2);
    return Offset(offset.dx.clamp(-maxX, maxX), offset.dy.clamp(-maxY, maxY));
  }

  void _close() {
    if (!mounted) return;
    Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final screen = media.size;
    final resting = _restingRect(screen, media.padding);

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): _close,
      },
      child: Focus(
        autofocus: true,
        child: AnimatedBuilder(
          animation: widget.animation,
          builder: (context, _) {
            final t = Curves.easeOutCubic.transform(widget.animation.value);
            final dragFade = (1 - _dismissDrag.distance / 400).clamp(0.0, 1.0);
            final backdrop = t * dragFade;
            final settled = widget.animation.status == AnimationStatus.completed;
            // While opening/closing, fly between the page spot and the
            // focused spot; once open, apply zoom and drag.
            final base = Rect.lerp(widget.origin, resting, t)!;
            final shown = settled || _dismissing
                ? Rect.fromCenter(
                    center: base.center + _offset + _dismissDrag,
                    width: base.width * _scale,
                    height: base.height * _scale)
                : base.shift(_dismissDrag);
            return Stack(children: [
              Positioned.fill(
                child: ColoredBox(
                    color: Colors.black.withValues(alpha: 0.92 * backdrop)),
              ),
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onScaleStart: (d) {
                    _settle.stop();
                    _startScale = _scale;
                    _startOffset = _offset;
                    _startFocal = d.focalPoint;
                    _dismissing = false;
                  },
                  onScaleUpdate: (d) {
                    setState(() {
                      if (d.pointerCount > 1 || _startScale > 1.01) {
                        final scale =
                            (_startScale * d.scale).clamp(1.0, _maxScale);
                        // Keep the point under the fingers in place.
                        final anchor = _startFocal - resting.center;
                        final moved = d.focalPoint - _startFocal;
                        final offset = anchor -
                            (anchor - _startOffset) * (scale / _startScale) +
                            moved;
                        _scale = scale;
                        _offset = _clampOffset(offset, scale, resting);
                        _dismissDrag = Offset.zero;
                      } else {
                        _dismissing = true;
                        _dismissDrag = d.focalPoint - _startFocal;
                      }
                    });
                  },
                  onScaleEnd: (d) {
                    if (_dismissing) {
                      final v = d.velocity.pixelsPerSecond;
                      if (_dismissDrag.dy.abs() > 110 || v.dy.abs() > 800) {
                        _close();
                      } else {
                        _dismissing = false;
                        _animateTo(drag: Offset.zero);
                      }
                    } else if (_scale < 1.05) {
                      _animateTo(scale: 1, offset: Offset.zero);
                    }
                  },
                  onDoubleTapDown: (d) => _doubleTapAt = d.globalPosition,
                  onDoubleTap: () {
                    if (_scale > 1.05) {
                      _animateTo(scale: 1, offset: Offset.zero);
                    } else {
                      const target = 2.5;
                      final at = _doubleTapAt ?? resting.center;
                      final offset = (resting.center - at) * (target - 1);
                      _animateTo(
                          scale: target,
                          offset: _clampOffset(offset, target, resting));
                    }
                  },
                  // A tap beside the image closes it, as in Apple Books.
                  onTapUp: (d) {
                    if (!shown.contains(d.globalPosition)) _close();
                  },
                ),
              ),
              Positioned.fromRect(
                rect: shown,
                child: IgnorePointer(
                  child: Semantics(
                    image: true,
                    label: (widget.label?.trim().isNotEmpty ?? false)
                        ? widget.label
                        : 'Book image',
                    child: RawImage(
                      image: widget.image,
                      fit: BoxFit.fill,
                      filterQuality: FilterQuality.medium,
                    ),
                  ),
                ),
              ),
              Positioned(
                top: media.padding.top + 8,
                right: 12,
                child: Opacity(
                  opacity: backdrop,
                  child: Material(
                    color: Colors.white.withValues(alpha: 0.16),
                    shape: const CircleBorder(),
                    child: IconButton(
                      tooltip: 'Close',
                      icon: const Icon(Icons.close, color: Colors.white),
                      onPressed: _close,
                    ),
                  ),
                ),
              ),
            ]);
          },
        ),
      ),
    );
  }
}
