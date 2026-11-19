import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Draws [image] as a page being turned with a paper curl, like Apple Books
/// (shader: shaders/page_curl.frag).
///
/// [progress] 0 shows the page flat; 1 has it turned away completely
/// (nothing drawn), so whatever lies underneath — the next page — shows
/// through as the page curls off.
class PageCurl extends StatefulWidget {
  final ui.FragmentProgram program;
  final ui.Image image;
  final Animation<double> progress;

  /// Colour of the paper, seen on the back of the turning sheet.
  final Color paperColor;

  /// Colour the page is normally drawn on; fills the image's transparent
  /// parts so the turning page looks exactly as it did on screen.
  final Color backgroundColor;

  const PageCurl({
    super.key,
    required this.program,
    required this.image,
    required this.progress,
    required this.paperColor,
    required this.backgroundColor,
  });

  static Future<ui.FragmentProgram?>? _program;

  /// The compiled curl shader, or null when it cannot be loaded (callers then
  /// turn pages without the animation).
  static Future<ui.FragmentProgram?> load() => _program ??= _load();

  static Future<ui.FragmentProgram?> _load() async {
    final ui.FragmentProgram program;
    try {
      program = await ui.FragmentProgram.fromAsset('shaders/page_curl.frag');
    } catch (e) {
      debugPrint('[EPUB] page curl unavailable: $e');
      return null;
    }
    await _warmUp(program);
    return program;
  }

  /// Draws the shader once off screen so the GPU compiles it now, while the
  /// book is loading, instead of in the middle of the first page turn (a
  /// first-time compile holds up that frame).
  static Future<void> _warmUp(ui.FragmentProgram program) async {
    ui.Image? sample;
    ui.Image? result;
    ui.FragmentShader? shader;
    try {
      final sampleRecorder = ui.PictureRecorder();
      Canvas(sampleRecorder).drawPaint(Paint()..color = const Color(0xFFFFFFFF));
      final samplePicture = sampleRecorder.endRecording();
      sample = await samplePicture.toImage(4, 4);
      samplePicture.dispose();

      shader = program.fragmentShader()
        ..setFloat(0, 4)
        ..setFloat(1, 4)
        ..setFloat(2, 0.5);
      for (var i = 3; i <= 10; i++) {
        shader.setFloat(i, 1);
      }
      shader.setImageSampler(0, sample, filterQuality: FilterQuality.low);

      final recorder = ui.PictureRecorder();
      Canvas(recorder)
          .drawRect(const Rect.fromLTWH(0, 0, 4, 4), Paint()..shader = shader);
      final picture = recorder.endRecording();
      result = await picture.toImage(4, 4);
      picture.dispose();
    } catch (e) {
      debugPrint('[EPUB] page curl warm-up failed: $e');
    } finally {
      result?.dispose();
      shader?.dispose();
      sample?.dispose();
    }
  }

  @override
  State<PageCurl> createState() => _PageCurlState();
}

class _PageCurlState extends State<PageCurl> {
  late ui.FragmentShader _shader = widget.program.fragmentShader();

  @override
  void didUpdateWidget(PageCurl oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.program != widget.program) {
      _shader.dispose();
      _shader = widget.program.fragmentShader();
    }
  }

  @override
  void dispose() {
    _shader.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.infinite,
      painter: _PageCurlPainter(_shader, widget.image, widget.progress,
          widget.paperColor, widget.backgroundColor),
    );
  }
}

class _PageCurlPainter extends CustomPainter {
  _PageCurlPainter(
      this.shader, this.image, this.progress, this.paper, this.background)
      : super(repaint: progress);

  final ui.FragmentShader shader;
  final ui.Image image;
  final Animation<double> progress;
  final Color paper;
  final Color background;

  @override
  void paint(Canvas canvas, Size size) {
    shader
      ..setFloat(0, size.width)
      ..setFloat(1, size.height)
      ..setFloat(2, progress.value.clamp(0.0, 1.0))
      ..setFloat(3, paper.r)
      ..setFloat(4, paper.g)
      ..setFloat(5, paper.b)
      ..setFloat(6, paper.a)
      ..setFloat(7, background.r)
      ..setFloat(8, background.g)
      ..setFloat(9, background.b)
      ..setFloat(10, background.a)
      ..setImageSampler(0, image, filterQuality: FilterQuality.low);
    canvas.drawRect(Offset.zero & size, Paint()..shader = shader);
  }

  @override
  bool shouldRepaint(_PageCurlPainter old) =>
      old.shader != shader ||
      old.image != image ||
      old.progress != progress ||
      old.paper != paper ||
      old.background != background;
}
