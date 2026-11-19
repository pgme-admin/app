import 'dart:async';
import 'dart:convert';
import 'dart:ui' show Rect;

import 'package:flutter/foundation.dart';
import 'package:flutter_epub_viewer/flutter_epub_viewer.dart';

/// What lies under a tap on the book: an image, a saved highlight/underline,
/// a link, or plain text.
class EpubTapTarget {
  const EpubTapTarget._(this.kind,
      {this.src, this.label, this.rect, this.annotations = const []});

  static const none = EpubTapTarget._('none');

  /// 'image', 'annotation', 'link' or 'none'.
  final String kind;
  final String? src;
  final String? label;

  /// Normalized (0..1) rectangle in the book view.
  final Rect? rect;

  /// (cfi, type) pairs of the annotations under the tap.
  final List<({String cfi, String type})> annotations;

  static EpubTapTarget fromJson(Object? raw) {
    final data = raw is String ? jsonDecode(raw) : raw;
    if (data is! Map) return none;
    final r = data['rect'];
    Rect? rect;
    if (r is Map) {
      double v(String k) => (r[k] as num?)?.toDouble() ?? 0;
      rect = Rect.fromLTWH(v('left'), v('top'), v('width'), v('height'));
    }
    final list = <({String cfi, String type})>[];
    final hits = data['annotations'];
    if (hits is List) {
      for (final h in hits) {
        if (h is Map && h['cfi'] is String && h['type'] is String) {
          list.add((cfi: h['cfi'] as String, type: h['type'] as String));
        }
      }
    }
    return EpubTapTarget._(data['kind'] as String? ?? 'none',
        src: data['src'] as String?,
        label: data['label'] as String?,
        rect: rect,
        annotations: list);
  }
}

/// JavaScript helpers for the EPUB reader, installed into the reader page
/// once per loaded book (the page is replaced when the book is reloaded).
///
/// Replaces three things in flutter_epub_viewer 1.2.8 that do not work:
/// * annotation taps (its page never forwards epub.js `markClicked`);
/// * underline styling (epub.js draws a 1px black line, invisible on dark
///   pages) and re-adding a mark (epub.js leaves the old one on the page);
/// * clearing a selection (the page keeps flags that block every page turn
///   until a `selectionchange` arrives, which does not always happen).
///
/// Page turns requested by the page itself (Android swipe) are sent to
/// Flutter as `pgmeTurnRequest`, so every turn goes through the reader's
/// turn animation. Flutter turns pages with [epubBridgeTurn].
class EpubReaderBridge {
  EpubReaderBridge._();

  static Future<bool> install(
    EpubController controller, {
    required bool dark,
    required void Function(bool forward) onTurnRequest,
  }) async {
    final webView = controller.webViewController;
    if (webView == null) return false;
    // Registered before the script runs: the page sends turn requests to it.
    webView.addJavaScriptHandler(
      handlerName: 'pgmeTurnRequest',
      callback: (args) {
        if (args.isNotEmpty) onTurnRequest(args.first == true);
      },
    );
    final result = await webView.evaluateJavascript(source: _script);
    await setDark(controller, dark);
    return result == true;
  }

  static Future<void> setDark(EpubController controller, bool dark) async {
    await controller.webViewController?.evaluateJavascript(
        source: 'window.pgme && window.pgme.setDark($dark)');
  }

  /// [x], [y]: normalized coordinates from the viewer's touch callbacks.
  static Future<EpubTapTarget> tapAt(
      EpubController controller, double x, double y) async {
    final webView = controller.webViewController;
    if (webView == null) return EpubTapTarget.none;
    try {
      final raw = await webView
          .evaluateJavascript(
              source: 'window.pgme ? window.pgme.tapAt($x, $y) : null')
          .timeout(const Duration(milliseconds: 800));
      return EpubTapTarget.fromJson(raw);
    } catch (e) {
      debugPrint('[EPUB] tap lookup failed: $e');
      return EpubTapTarget.none;
    }
  }

  static Future<void> addAnnotation(EpubController controller,
      {required String cfi, required String type, String color = 'yellow'}) {
    return _call(controller,
        'window.pgme && window.pgme.add(${jsonEncode(cfi)}, ${jsonEncode(type)}, ${jsonEncode(color)})');
  }

  static Future<void> removeAnnotation(EpubController controller,
      {required String cfi, required String type}) {
    return _call(controller,
        'window.pgme && window.pgme.remove(${jsonEncode(cfi)}, ${jsonEncode(type)})');
  }

  /// Clears the text selection in every chapter frame and the flags that
  /// make the page refuse to turn while text is selected.
  static Future<void> resetSelection(EpubController controller) {
    return _call(controller,
        'window.pgme ? window.pgme.resetSelection() : (window.clearSelection && clearSelection())');
  }

  static Future<bool> hasSelection(EpubController controller) async {
    try {
      final r = await controller.webViewController
          ?.evaluateJavascript(
              source: 'window.pgme ? window.pgme.hasSelection() : false')
          .timeout(const Duration(milliseconds: 600));
      return r == true;
    } catch (_) {
      return false;
    }
  }

  /// Turns the page in the book (bypassing the turn-request hook).
  static Future<void> turn(EpubController controller, bool forward) {
    return _call(
        controller,
        'window.pgme ? window.pgme.turn($forward) : '
        '(${forward ? 'next()' : 'previous()'})');
  }

  /// The bytes of an image shown in the book (EPUB images are blob: URLs
  /// that only the reader page can read).
  static Future<Uint8List?> imageBytes(
      EpubController controller, String src) async {
    final webView = controller.webViewController;
    if (webView == null) return null;
    try {
      final result = await webView.callAsyncJavaScript(
        functionBody: '''
          const response = await fetch(src);
          if (!response.ok) return null;
          const blob = await response.blob();
          return await new Promise(function (resolve, reject) {
            const reader = new FileReader();
            reader.onload = function () { resolve(reader.result); };
            reader.onerror = function () { reject(reader.error); };
            reader.readAsDataURL(blob);
          });
        ''',
        arguments: {'src': src},
      ).timeout(const Duration(seconds: 6));
      final value = result?.value;
      if (value is! String) return null;
      final comma = value.indexOf(',');
      if (!value.startsWith('data:') || comma < 0) return null;
      if (!value.substring(0, comma).contains(';base64')) return null;
      return base64Decode(value.substring(comma + 1));
    } catch (e) {
      debugPrint('[EPUB] image bytes unavailable: $e');
      return null;
    }
  }

  static Future<void> _call(EpubController controller, String source) async {
    try {
      await controller.webViewController?.evaluateJavascript(source: source);
    } catch (e) {
      debugPrint('[EPUB] bridge call failed: $e');
    }
  }

  static const String _script = r'''
(function () {
  if (typeof rendition === 'undefined' || !rendition) return false;
  if (window.pgme && window.pgme.rendition === rendition) return true;
  var pgme = window.pgme = { rendition: rendition, directTurn: false };

  function call(name, arg) {
    try { window.flutter_inappwebview.callHandler(name, arg); } catch (e) {}
  }

  // ---- Annotation colours ------------------------------------------------
  // marks-pane draws highlights in an SVG layer above each chapter frame.
  // Colours come from CSS classes so a theme change needs no redraw.
  pgme.setDark = function (dark) {
    var style = document.getElementById('pgme-annotation-style');
    if (!style) {
      style = document.createElement('style');
      style.id = 'pgme-annotation-style';
      (document.head || document.documentElement).appendChild(style);
    }
    var colours = dark
      ? { yellow: '#C9A227', green: '#3F9E5A', blue: '#3F7FC7', pink: '#C2527E' }
      : { yellow: '#FFE45C', green: '#9BE3A6', blue: '#9CCBFF', pink: '#FFA9CB' };
    var css = '.epub-view > svg{mix-blend-mode:' + (dark ? 'screen' : 'multiply') + ';}';
    for (var name in colours) {
      css += 'g.pgme-hl-' + name + '{fill:' + colours[name] +
        ' !important;fill-opacity:' + (dark ? '0.55' : '0.5') + ' !important;}';
    }
    css += 'g.pgme-ul rect{fill:transparent !important;}' +
      'g.pgme-ul line{stroke:' + (dark ? '#8ABFFF' : '#1565C0') +
      ' !important;stroke-width:2px !important;stroke-opacity:0.95 !important;}';
    style.textContent = css;
    return true;
  };

  pgme.add = function (cfi, type, colour) {
    try { rendition.annotations.remove(cfi, type); } catch (e) {}
    try {
      if (type === 'underline') {
        rendition.annotations.underline(cfi, {}, null, 'pgme-ul', {});
      } else {
        rendition.annotations.highlight(cfi, {}, null, 'pgme-hl-' + (colour || 'yellow'), {});
      }
      return true;
    } catch (e) {
      console.error('pgme add annotation failed', e);
      return false;
    }
  };

  pgme.remove = function (cfi, type) {
    try { rendition.annotations.remove(cfi, type); return true; } catch (e) { return false; }
  };

  // ---- Selection -----------------------------------------------------------
  pgme.resetSelection = function () {
    try {
      rendition.getContents().forEach(function (c) {
        try { c.window.getSelection().removeAllRanges(); } catch (e) {}
      });
    } catch (e) {}
    try { window.getSelection().removeAllRanges(); } catch (e) {}
    try {
      isSelecting = false;
      lastCfiRange = null;
      hasSentSelection = false;
      if (selectionTimeout) { clearTimeout(selectionTimeout); selectionTimeout = null; }
    } catch (e) {}
    try { blockGesturesWhenSelected(false); } catch (e) {}
    return true;
  };

  pgme.hasSelection = function () {
    try {
      var found = false;
      rendition.getContents().forEach(function (c) {
        try {
          var s = c.window.getSelection();
          if (s && s.rangeCount > 0 && !s.getRangeAt(0).collapsed && s.toString()) found = true;
        } catch (e) {}
      });
      return found;
    } catch (e) { return false; }
  };

  // ---- Page turns ----------------------------------------------------------
  ['next', 'prev'].forEach(function (name) {
    var original = rendition[name];
    rendition[name] = function () {
      if (pgme.directTurn) return original.apply(rendition, arguments);
      call('pgmeTurnRequest', name === 'next');
      return Promise.resolve(rendition.location);
    };
  });
  pgme.turn = function (forward) {
    // The page refuses to turn while its selection flags are set. When no
    // text is actually selected those flags are stale: clear them, or every
    // later turn would be silently ignored (a frozen book).
    if (!pgme.hasSelection()) {
      try {
        isSelecting = false;
        lastCfiRange = null;
        hasSentSelection = false;
      } catch (e) {}
    }
    pgme.directTurn = true;
    try {
      if (forward) { next(); } else { previous(); }
    } finally {
      pgme.directTurn = false;
    }
    return true;
  };

  // ---- Tap lookup ----------------------------------------------------------
  function frameRect(contents) {
    var frame = contents.window && contents.window.frameElement;
    return frame ? frame.getBoundingClientRect() : null;
  }
  function normalized(r, fr) {
    return {
      left: (r.left + fr.left) / window.innerWidth,
      top: (r.top + fr.top) / window.innerHeight,
      width: r.width / window.innerWidth,
      height: r.height / window.innerHeight
    };
  }
  function bounds(rects) {
    var l = Infinity, t = Infinity, r = -Infinity, b = -Infinity;
    for (var i = 0; i < rects.length; i++) {
      var x = rects[i];
      if (!x.width && !x.height) continue;
      l = Math.min(l, x.left); t = Math.min(t, x.top);
      r = Math.max(r, x.right); b = Math.max(b, x.bottom);
    }
    return l === Infinity ? null : { left: l, top: t, width: r - l, height: b - t };
  }
  function imageSource(image, doc) {
    var src = image.currentSrc || image.src ||
      image.getAttribute('href') || image.getAttribute('xlink:href');
    if (src && typeof src === 'object' && src.baseVal) src = src.baseVal;
    if (!src || typeof src !== 'string') return null;
    if (!/^(blob:|data:|https?:|file:)/i.test(src)) {
      try { src = new URL(src, doc.baseURI).href; } catch (e) { return null; }
    }
    return src;
  }

  pgme.tapAt = function (nx, ny) {
    var x = nx * window.innerWidth, y = ny * window.innerHeight;
    var contents = rendition.getContents();
    for (var i = 0; i < contents.length; i++) {
      var c = contents[i], doc = c.document, fr = frameRect(c);
      if (!doc || !fr) continue;
      var lx = x - fr.left, ly = y - fr.top;
      if (lx < 0 || ly < 0 || lx > fr.width || ly > fr.height) continue;

      // Saved highlights and underlines (drawn over the text).
      var hits = [], hitRects = [];
      var store = rendition.annotations._annotations || {};
      Object.keys(store).forEach(function (hash) {
        var a = store[hash];
        if (!a || (a.type !== 'highlight' && a.type !== 'underline')) return;
        if (c.sectionIndex !== undefined && a.sectionIndex !== c.sectionIndex) return;
        var range;
        try { range = c.range(a.cfiRange); } catch (e) { return; }
        if (!range) return;
        var rects = range.getClientRects();
        for (var k = 0; k < rects.length; k++) {
          var rr = rects[k];
          if (lx >= rr.left - 4 && lx <= rr.right + 4 && ly >= rr.top - 4 && ly <= rr.bottom + 6) {
            hits.push({ cfi: a.cfiRange, type: a.type });
            for (var m = 0; m < rects.length; m++) hitRects.push(rects[m]);
            break;
          }
        }
      });
      if (hits.length) {
        var hb = bounds(hitRects);
        return JSON.stringify({ kind: 'annotation', annotations: hits,
          rect: hb ? normalized(hb, fr) : null });
      }

      var elements = doc.elementsFromPoint ? doc.elementsFromPoint(lx, ly)
        : [doc.elementFromPoint(lx, ly)];
      for (var j = 0; j < elements.length; j++) {
        var el = elements[j];
        if (!el || !el.closest) continue;
        if (el.closest('a[href]')) return JSON.stringify({ kind: 'link' });
        var image = el.closest('img, image');
        if (!image) continue;
        var box = image.getBoundingClientRect();
        if (box.width < 24 || box.height < 24) continue;
        var src = imageSource(image, doc);
        if (!src) continue;
        return JSON.stringify({ kind: 'image', src: src,
          label: image.getAttribute('alt') || image.getAttribute('aria-label') || '',
          rect: normalized(box, fr) });
      }
    }
    return JSON.stringify({ kind: 'none' });
  };

  return true;
})();
''';
}
