import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// The page-curl shader (shaders/page_curl.frag) behind the EPUB reader's
// page-turn animation on iOS. A still of the page is laid over the book and
// curled away, so the turn must start from exactly the page as it was (no
// jump when the curl begins) and end with nothing drawn (the real next page
// shows, no jump when the still is removed).
void main() {
  const w = 40, h = 60;
  late ui.FragmentProgram program;

  setUpAll(() async {
    program = await ui.FragmentProgram.fromAsset('shaders/page_curl.frag');
  });

  Future<ui.Image> solidImage(Color color) async {
    final recorder = ui.PictureRecorder();
    Canvas(recorder).drawPaint(Paint()..color = color);
    final picture = recorder.endRecording();
    final image = await picture.toImage(w, h);
    picture.dispose();
    return image;
  }

  // Renders the curl and returns its RGBA pixels.
  Future<Uint8List> render(
    ui.Image page,
    double progress, {
    Color paper = Colors.white,
    Color background = Colors.white,
  }) async {
    final shader = program.fragmentShader()
      ..setFloat(0, w.toDouble())
      ..setFloat(1, h.toDouble())
      ..setFloat(2, progress)
      ..setFloat(3, paper.r)
      ..setFloat(4, paper.g)
      ..setFloat(5, paper.b)
      ..setFloat(6, paper.a)
      ..setFloat(7, background.r)
      ..setFloat(8, background.g)
      ..setFloat(9, background.b)
      ..setFloat(10, background.a)
      ..setImageSampler(0, page);
    final recorder = ui.PictureRecorder();
    Canvas(recorder).drawRect(
        Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()), Paint()..shader = shader);
    final picture = recorder.endRecording();
    final image = await picture.toImage(w, h);
    final bytes = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    picture.dispose();
    image.dispose();
    shader.dispose();
    return bytes.buffer.asUint8List();
  }

  List<int> px(Uint8List rgba, int x, int y) {
    final i = (y * w + x) * 4;
    return rgba.sublist(i, i + 4);
  }

  const green = Color(0xFF00A050);

  test('progress 0: the page is drawn exactly as it was', () async {
    final page = await solidImage(green);
    final out = await render(page, 0);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final p = px(out, x, y);
        expect(p[0], closeTo(0x00, 2), reason: 'r at $x,$y');
        expect(p[1], closeTo(0xA0, 2), reason: 'g at $x,$y');
        expect(p[2], closeTo(0x50, 2), reason: 'b at $x,$y');
        expect(p[3], 255, reason: 'alpha at $x,$y');
      }
    }
    page.dispose();
  });

  test('progress 1: the page has turned away, nothing is drawn', () async {
    final page = await solidImage(green);
    final out = await render(page, 1);
    for (var i = 3; i < out.length; i += 4) {
      expect(out[i], 0, reason: 'alpha at pixel ${i ~/ 4}');
    }
    page.dispose();
  });

  test('half-way: flat page by the spine, the next page showing at the '
      'lower-right corner, the back of the sheet in between', () async {
    final page = await solidImage(green);
    final out = await render(page, 0.5);

    // Top-left: still flat, unchanged.
    expect(px(out, 0, 0), [0x00, 0xA0, 0x50, 255]);
    // Lower-right corner: already turned, the next page shows through.
    expect(px(out, w - 1, h - 1)[3], 0);
    // Somewhere the curled-over back of the sheet: opaque and nearly paper
    // white (only a faint tint of the print showing through).
    var backPixels = 0;
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final p = px(out, x, y);
        if (p[3] == 255 && p[0] > 180) backPixels++;
      }
    }
    expect(backPixels, greaterThan(0));
    page.dispose();
  });

  test('transparent parts of the still take the background colour', () async {
    final page = await solidImage(const Color(0x00000000));
    const bg = Color(0xFF123456);
    final out = await render(page, 0, background: bg);
    for (final (x, y) in [(0, 0), (w ~/ 2, h ~/ 2), (w - 1, h - 1)]) {
      final p = px(out, x, y);
      expect(p[0], closeTo(0x12, 2));
      expect(p[1], closeTo(0x34, 2));
      expect(p[2], closeTo(0x56, 2));
      expect(p[3], 255);
    }
    page.dispose();
  });
}
