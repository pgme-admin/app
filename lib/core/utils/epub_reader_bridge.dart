import 'dart:async';
import 'dart:convert';
import 'dart:ui' show Rect;

import 'package:flutter/foundation.dart';
import 'package:flutter_epub_viewer/flutter_epub_viewer.dart';

/// What lies under a tap on the book: an image, a table or figure, a saved
/// highlight/underline (or its note badge), a link, or plain text.
class EpubTapTarget {
  const EpubTapTarget._(this.kind,
      {this.src,
      this.label,
      this.rect,
      this.annotations = const [],
      this.noteTap = false});

  static const none = EpubTapTarget._('none');

  /// 'image', 'table', 'figure', 'annotation', 'link' or 'none'.
  final String kind;
  final String? src;
  final String? label;

  /// Normalized (0..1) rectangle in the book view.
  final Rect? rect;

  /// (cfi, type) pairs of the annotations under the tap.
  final List<({String cfi, String type})> annotations;

  /// The tap was on the note badge drawn after an annotation with a note.
  final bool noteTap;

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
        annotations: list,
        noteTap: data['noteTap'] == true);
  }
}

/// Existing annotations a new one overlaps, and the range covering them all.
class EpubOverlap {
  const EpubOverlap(
      {required this.cfis, required this.union, required this.text});

  /// CFIs of the overlapping annotations of the same type.
  final List<String> cfis;

  /// CFI of the new range joined with every overlapping one.
  final String union;

  /// Text of [union].
  final String text;

  static EpubOverlap? fromJson(Object? raw) {
    final data = raw is String ? jsonDecode(raw) : raw;
    if (data is! Map) return null;
    final union = data['union'];
    if (union is! String || !union.startsWith('epubcfi(')) return null;
    return EpubOverlap(
      cfis: [
        for (final c in (data['cfis'] as List? ?? const []))
          if (c is String) c
      ],
      union: union,
      text: data['text'] as String? ?? '',
    );
  }
}

/// The book's page numbering at the current location.
///
/// [mode] is 'print' (the printed page numbers the book lists), 'fixed'
/// (one page per fixed-layout page) or 'locations' (equal-length sections
/// of text, the same at every font size).
class EpubPageInfo {
  const EpubPageInfo(
      {required this.mode, required this.current, required this.total});
  final String mode;
  final int? current;
  final int total;

  static EpubPageInfo? fromJson(Object? raw) {
    final data = raw is String ? jsonDecode(raw) : raw;
    if (data is! Map) return null;
    final mode = data['mode'];
    final total = (data['total'] as num?)?.toInt() ?? 0;
    if (mode is! String || total < 1) return null;
    return EpubPageInfo(
        mode: mode, current: (data['current'] as num?)?.toInt(), total: total);
  }
}

/// Where a location is in the book: chapter title and page, for the
/// bookmarks and notes lists.
class EpubPlace {
  const EpubPlace({required this.cfi, required this.chapter, this.page});
  final String cfi;
  final String chapter;
  final int? page;
}

/// A table or figure copied out of the page for the focus view: markup with
/// its look inlined (no book stylesheets needed) and the page colours.
class EpubFocusMarkup {
  const EpubFocusMarkup({
    required this.html,
    required this.width,
    required this.background,
    required this.color,
    required this.fontFamily,
    required this.fontSize,
  });
  final String html;
  final double width;
  final String background;
  final String color;
  final String fontFamily;
  final String fontSize;
}

/// JavaScript helpers for the EPUB reader, installed into the reader page
/// once per loaded book (the page is replaced when the book is reloaded).
///
/// Replaces or adds what flutter_epub_viewer 1.2.8 / epub.js lack:
/// * hit-testing a tap (images, tables, figures, annotations, note badges);
///   taps are detected in Flutter, not from the page's touch events, which
///   do not reliably arrive from inside the book's frame on iOS;
/// * marks drawn on the text only: epub.js draws the boxes of whole elements
///   when a highlight crosses paragraphs (colour outside the text), and
///   overlapping boxes darken;
/// * merging an annotation with the ones it overlaps, so highlighting the
///   same words again never stacks colour;
/// * note badges, page numbers, bookmarks on the visible page, a brief flash
///   on a search result;
/// * underline styling and clearing a selection (stale selection flags
///   block every page turn).
///
/// Page turns requested by the page itself (Android swipe) are sent to
/// Flutter as `pgmeTurnRequest`, so every turn goes through the reader's
/// turn animation.
class EpubReaderBridge {
  EpubReaderBridge._();

  static Future<bool> install(
    EpubController controller, {
    required bool dark,
    required void Function(bool forward) onTurnRequest,
    VoidCallback? onPagesReady,
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
    webView.addJavaScriptHandler(
      handlerName: 'pgmePagesReady',
      callback: (_) => onPagesReady?.call(),
    );
    final result = await webView.evaluateJavascript(source: _script);
    await setDark(controller, dark);
    return result == true;
  }

  static Future<void> setDark(EpubController controller, bool dark) async {
    await controller.webViewController?.evaluateJavascript(
        source: 'window.pgme && window.pgme.setDark($dark)');
  }

  /// [x], [y]: normalized (0..1) position in the book view.
  static Future<EpubTapTarget> tapAt(
      EpubController controller, double x, double y) async {
    final raw = await _eval(
        controller, 'window.pgme ? window.pgme.tapAt($x, $y) : null',
        timeout: const Duration(milliseconds: 800));
    return EpubTapTarget.fromJson(raw);
  }

  static Future<void> addAnnotation(EpubController controller,
      {required String cfi,
      required String type,
      String color = 'yellow',
      bool hasNote = false}) {
    return _call(controller,
        'window.pgme && window.pgme.add(${jsonEncode(cfi)}, ${jsonEncode(type)}, ${jsonEncode(color)}, $hasNote)');
  }

  static Future<void> removeAnnotation(EpubController controller,
      {required String cfi, required String type}) {
    return _call(controller,
        'window.pgme && window.pgme.remove(${jsonEncode(cfi)}, ${jsonEncode(type)})');
  }

  /// Saved annotations of [type] that overlap [cfi] (same chapter), with
  /// the range joining them. Null when the book cannot tell.
  static Future<EpubOverlap?> overlaps(EpubController controller,
      {required String cfi, required String type}) async {
    final raw = await _eval(controller,
        'window.pgme ? window.pgme.overlaps(${jsonEncode(cfi)}, ${jsonEncode(type)}) : null');
    return EpubOverlap.fromJson(raw);
  }

  /// Clears the text selection in every chapter frame and the flags that
  /// make the page refuse to turn while text is selected.
  static Future<void> resetSelection(EpubController controller) {
    return _call(controller,
        'window.pgme ? window.pgme.resetSelection() : (window.clearSelection && clearSelection())');
  }

  static Future<bool> hasSelection(EpubController controller) async {
    final r = await _eval(
        controller, 'window.pgme ? window.pgme.hasSelection() : false',
        timeout: const Duration(milliseconds: 600));
    return r == true;
  }

  /// The text line at (or, with [scan], first below) a normalized point:
  /// its top and the distance to the next line, both as fractions of the
  /// book view height. Null when there is no text there.
  static Future<({double top, double pitch})?> lineAt(
      EpubController controller, double x, double y,
      {bool scan = false}) async {
    final raw = await _eval(
        controller, 'window.pgme ? window.pgme.lineAt($x, $y, $scan) : null',
        timeout: const Duration(milliseconds: 600));
    try {
      final data = raw is String ? jsonDecode(raw) : raw;
      if (data is! Map) return null;
      final top = (data['top'] as num?)?.toDouble();
      final pitch = (data['pitch'] as num?)?.toDouble();
      if (top == null || pitch == null || pitch <= 0) return null;
      return (top: top, pitch: pitch);
    } catch (e) {
      debugPrint('[EPUB] line lookup failed: $e');
      return null;
    }
  }

  /// Redraws highlights/underlines after the text was re-laid out.
  static Future<void> refreshMarks(EpubController controller) {
    return _call(controller, 'window.pgme && window.pgme.refreshMarks()');
  }

  /// Hides (or shows again) the image last returned by [tapAt] while it is
  /// shown in the focus view.
  static Future<void> setFocusedImageHidden(
      EpubController controller, bool hidden) {
    return _call(controller,
        'window.pgme && window.pgme.setFocusedImageHidden($hidden)');
  }

  /// Turns the page in the book (bypassing the turn-request hook).
  static Future<void> turn(EpubController controller, bool forward) {
    return _call(
        controller,
        'window.pgme ? window.pgme.turn($forward) : '
        '(${forward ? 'next()' : 'previous()'})');
  }

  /// Shows [target] (a CFI or a chapter href). With [flash], the text at a
  /// CFI range is briefly marked once it is on screen (search results).
  static Future<bool> goTo(EpubController controller, String target,
      {bool flash = false}) async {
    final r = await _eval(controller,
        'window.pgme ? window.pgme.goTo(${jsonEncode(target)}, $flash) : false');
    return r == true;
  }

  /// Starts (re)building the book's page numbers for the current page size
  /// when needed; [install]'s onPagesReady fires when they are ready.
  static Future<void> paginate(EpubController controller, String layoutKey) {
    return _call(controller,
        'window.pgme && window.pgme.paginate(${jsonEncode(layoutKey)})');
  }

  static Future<EpubPageInfo?> pageInfo(EpubController controller) async {
    return EpubPageInfo.fromJson(
        await _eval(controller, 'window.pgme ? window.pgme.pageInfo() : null'));
  }

  /// Where page [page] starts (CFI or chapter href), or null.
  static Future<String?> targetForPage(
      EpubController controller, int page) async {
    final r = await _eval(
        controller, 'window.pgme ? window.pgme.targetForPage($page) : null');
    return r is String && r.isNotEmpty ? r : null;
  }

  /// Which of [cfis] lie on the visible page.
  static Future<List<String>> onScreen(
      EpubController controller, List<String> cfis) async {
    if (cfis.isEmpty) return const [];
    final raw = await _eval(controller,
        'window.pgme ? window.pgme.onScreen(${jsonEncode(cfis)}) : "[]"');
    try {
      final data = raw is String ? jsonDecode(raw) : raw;
      return [
        for (final c in (data as List? ?? const []))
          if (c is String) c
      ];
    } catch (_) {
      return const [];
    }
  }

  /// Chapter and page for each of [cfis], in book order.
  static Future<List<EpubPlace>> describe(
      EpubController controller, List<String> cfis) async {
    if (cfis.isEmpty) return const [];
    final raw = await _eval(controller,
        'window.pgme ? window.pgme.describe(${jsonEncode(cfis)}) : null',
        timeout: const Duration(seconds: 3));
    try {
      final data = raw is String ? jsonDecode(raw) : raw;
      if (data is! List) return const [];
      return [
        for (final e in data)
          if (e is Map && e['cfi'] is String)
            EpubPlace(
                cfi: e['cfi'] as String,
                chapter: (e['chapter'] as String? ?? '').trim(),
                page: (e['page'] as num?)?.toInt())
      ];
    } catch (_) {
      return const [];
    }
  }

  /// The table or figure returned by the last [tapAt], ready for the focus
  /// view. Images inside it are embedded.
  static Future<EpubFocusMarkup?> focusMarkup(EpubController controller) async {
    final webView = controller.webViewController;
    if (webView == null) return null;
    try {
      final result = await webView
          .callAsyncJavaScript(
              functionBody:
                  'return window.pgme ? await window.pgme.focusMarkup() : null;')
          .timeout(const Duration(seconds: 6));
      final raw = result?.value;
      final data = raw is String ? jsonDecode(raw) : raw;
      if (data is! Map || data['html'] is! String) return null;
      return EpubFocusMarkup(
        html: data['html'] as String,
        width: (data['width'] as num?)?.toDouble() ?? 0,
        background: data['background'] as String? ?? '',
        color: data['color'] as String? ?? '',
        fontFamily: data['font'] as String? ?? '',
        fontSize: data['size'] as String? ?? '',
      );
    } catch (e) {
      debugPrint('[EPUB] focus markup unavailable: $e');
      return null;
    }
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

  static Future<Object?> _eval(EpubController controller, String source,
      {Duration timeout = const Duration(seconds: 2)}) async {
    try {
      return await controller.webViewController
          ?.evaluateJavascript(source: source)
          .timeout(timeout);
    } catch (e) {
      debugPrint('[EPUB] bridge call failed: $e');
      return null;
    }
  }

  static Future<void> _call(EpubController controller, String source) async {
    await _eval(controller, source);
  }

  static const String _script = r'''
(function () {
  if (typeof rendition === 'undefined' || !rendition) return false;
  if (window.pgme && window.pgme.rendition === rendition) return true;
  var pgme = window.pgme = { rendition: rendition, directTurn: false };
  var SVG_NS = 'http://www.w3.org/2000/svg';

  function call(name, arg) {
    try { window.flutter_inappwebview.callHandler(name, arg); } catch (e) {}
  }
  function own(obj, key) { return Object.prototype.hasOwnProperty.call(obj, key); }

  // ---- Marks on the text only ----------------------------------------------
  // epub.js (marks-pane) draws range.getClientRects() and drops boxes that
  // sit inside bigger ones. When a highlight crosses paragraphs, only the
  // paragraphs' full boxes survive: colour fills margins and line gaps. The
  // marks are drawn from the text itself instead, one band per line.
  function mergeLines(rects) {
    rects.sort(function (a, b) { return (a.top - b.top) || (a.left - b.left); });
    var lines = [];
    rects.forEach(function (r) {
      var h = r.bottom - r.top;
      for (var i = lines.length - 1; i >= 0; i--) {
        var L = lines[i];
        var minH = Math.min(L.bottom - L.top, h);
        var overlap = Math.min(L.bottom, r.bottom) - Math.max(L.top, r.top);
        if (overlap < minH * 0.5) continue;
        var gap = Math.max(r.left - L.right, L.left - r.right);
        if (gap > Math.max(6, minH * 1.2)) continue;
        L.left = Math.min(L.left, r.left); L.right = Math.max(L.right, r.right);
        L.top = Math.min(L.top, r.top); L.bottom = Math.max(L.bottom, r.bottom);
        return;
      }
      lines.push({ left: r.left, top: r.top, right: r.right, bottom: r.bottom });
    });
    return lines.map(function (L) {
      return { left: L.left, top: L.top, right: L.right, bottom: L.bottom,
        x: L.left, y: L.top, width: L.right - L.left, height: L.bottom - L.top };
    });
  }
  function textRects(range) {
    var out = [];
    try {
      var root = range.commonAncestorContainer;
      if (root.nodeType === 3) root = root.parentNode;
      var doc = root.ownerDocument;
      var walker = doc.createTreeWalker(root, 4 /* SHOW_TEXT */, null);
      for (var node = walker.nextNode(); node; node = walker.nextNode()) {
        if (!range.intersectsNode(node)) continue;
        var s = node === range.startContainer ? range.startOffset : 0;
        var e = node === range.endContainer ? range.endOffset : node.length;
        if (e <= s || !/\S/.test(node.data.substring(s, e))) continue;
        var r = doc.createRange();
        r.setStart(node, s);
        r.setEnd(node, e);
        var list = r.getClientRects();
        for (var i = 0; i < list.length; i++) {
          var b = list[i];
          if (b.width < 0.5 || b.height < 0.5) continue;
          out.push({ left: b.left, top: b.top, right: b.right, bottom: b.bottom });
        }
      }
    } catch (err) {}
    return mergeLines(out);
  }
  function ownerOf(obj, key) {
    var p = obj;
    while (p && !own(p, key)) p = Object.getPrototypeOf(p);
    return p;
  }
  // Patches the marks-pane classes (not exported) through a live mark.
  function patchMark(mark) {
    if (!mark || typeof mark !== 'object') return;
    var base = ownerOf(mark, 'filteredRanges');
    if (base && !own(base, '__pgmeRects')) {
      base.__pgmeRects = true;
      base.filteredRanges = function () { return textRects(this.range); };
    }
    var proto = ownerOf(mark, 'render');
    if (proto && !own(proto, '__pgmeRender')) {
      proto.__pgmeRender = true;
      var original = proto.render;
      proto.render = function () {
        original.apply(this, arguments);
        try { drawNoteBadge(this); } catch (e) {}
      };
    }
  }
  function patchViews() {
    try {
      rendition.views().forEach(function (v) {
        if (v && v.pane && v.pane.marks) v.pane.marks.forEach(patchMark);
      });
    } catch (e) {}
  }
  // Where the note dot of an annotation goes: in the margin to the right
  // of the text column, level with the annotation's last line (never on
  // top of the text), as Apple Books marks notes. In iframe coordinates.
  function noteDot(range, rects) {
    var last = rects[rects.length - 1];
    if (!last) return null;
    var right = last.right;
    try {
      var node = range.endContainer.nodeType === 1 ? range.endContainer : range.endContainer.parentNode;
      var block = node.closest ? node.closest('p, li, blockquote, td, th, dd, dt, h1, h2, h3, h4, h5, h6, div') : null;
      var pieces = block ? block.getClientRects() : [];
      var mid = (last.top + last.bottom) / 2;
      for (var i = 0; i < pieces.length; i++) {
        var b = pieces[i];
        if (mid >= b.top && mid <= b.bottom && last.left >= b.left - 1 && last.left <= b.right) {
          right = Math.max(right, b.right);
          break;
        }
      }
    } catch (e) {}
    var r = Math.max(3.5, Math.min(4.5, (last.bottom - last.top) * 0.2));
    return { x: right + r + 4, y: (last.top + last.bottom) / 2, r: r };
  }
  function drawNoteBadge(mark) {
    var data = mark.data || {};
    if (!data.pgmeNote || !mark.element) return;
    var rects = mark.filteredRanges();
    var first = mark.element.querySelector('rect');
    if (!rects.length || !first) return;
    var dx = parseFloat(first.getAttribute('x')) - rects[0].left;
    var dy = parseFloat(first.getAttribute('y')) - rects[0].top;
    var spot = noteDot(mark.range, rects);
    if (!spot) return;
    var dot = document.createElementNS(SVG_NS, 'circle');
    dot.setAttribute('class', 'pgme-note-badge');
    dot.setAttribute('cx', spot.x + dx);
    dot.setAttribute('cy', spot.y + dy);
    dot.setAttribute('r', spot.r);
    mark.element.appendChild(dot);
  }
  rendition.on('rendered', function () {
    setTimeout(function () { patchViews(); pgme.refreshMarks(); }, 0);
  });

  // ---- Annotation colours ------------------------------------------------
  // Colours come from CSS classes so a theme change needs no redraw. The
  // group carries the opacity, so lines that touch never darken.
  pgme.setDark = function (dark) {
    var style = document.getElementById('pgme-annotation-style');
    if (!style) {
      style = document.createElement('style');
      style.id = 'pgme-annotation-style';
      (document.head || document.documentElement).appendChild(style);
    }
    var colours = dark
      ? { yellow: ['#C9A227', '#FFD54A'], green: ['#3F9E5A', '#7EE29A'],
          blue: ['#3F7FC7', '#8EC1FF'], pink: ['#C2527E', '#FF9CC4'] }
      : { yellow: ['#FFE45C', '#B98900'], green: ['#9BE3A6', '#2E8B47'],
          blue: ['#9CCBFF', '#1F6FD1'], pink: ['#FFA9CB', '#C93A79'] };
    var ink = dark ? '#8ABFFF' : '#1565C0';
    var css = '.epub-view > svg{mix-blend-mode:' + (dark ? 'screen' : 'multiply') + ';}';
    css += 'g[class*="pgme-hl-"] rect{rx:3px;ry:3px;}';
    for (var name in colours) {
      css += 'g.pgme-hl-' + name + '{fill:' + colours[name][0] +
        ' !important;fill-opacity:1 !important;opacity:' + (dark ? '0.55' : '0.5') + ';}' +
        'g.pgme-hl-' + name + ' circle.pgme-note-badge{fill:' + colours[name][1] + ' !important;}';
    }
    // epub.js draws each underline as a rect (hit area) plus a line, and
    // puts the stroke on the group: the rect would show as a box around the
    // text. Only the line under the text is drawn.
    css += 'g.pgme-ul rect, g.epubjs-ul rect{fill:transparent !important;' +
      'stroke:none !important;stroke-width:0 !important;}' +
      'g.pgme-ul, g.epubjs-ul{stroke:none !important;}' +
      'g.pgme-ul line{stroke:' + ink + ' !important;stroke-width:2px !important;' +
      'stroke-opacity:0.95 !important;stroke-linecap:round !important;}' +
      'g.pgme-ul circle.pgme-note-badge{fill:' + ink + ' !important;stroke:none !important;}';
    // Search result: a short pulse, then gone.
    css += 'g.pgme-flash{fill:' + (dark ? '#FF9F0A' : '#FF9500') +
      ' !important;fill-opacity:1 !important;opacity:0;' +
      'animation:pgmeFlash 2.4s ease-out forwards;}' +
      'g.pgme-flash rect{rx:3px;ry:3px;}' +
      '@keyframes pgmeFlash{0%{opacity:0}12%{opacity:.6}70%{opacity:.6}100%{opacity:0}}';
    style.textContent = css;
    return true;
  };

  function store() { return (rendition.annotations && rendition.annotations._annotations) || {}; }

  pgme.add = function (cfi, type, colour, hasNote) {
    try { rendition.annotations.remove(cfi, type); } catch (e) {}
    try {
      var data = hasNote ? { pgmeNote: '1' } : {};
      var ann = type === 'underline'
        ? rendition.annotations.underline(cfi, data, null, 'pgme-ul', {})
        : rendition.annotations.highlight(cfi, data, null, 'pgme-hl-' + (colour || 'yellow'), {});
      if (ann && ann.mark) {
        patchMark(ann.mark);
        ann.mark.render();
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

  // ---- Ranges ----------------------------------------------------------------
  function contentsFor(cfi) {
    var spine;
    try { spine = new ePub.CFI(cfi).spinePos; } catch (e) { return null; }
    var list = rendition.getContents();
    for (var i = 0; i < list.length; i++) {
      if (list[i].sectionIndex === spine) return list[i];
    }
    return null;
  }
  // <0: point A before B, 0: same, >0: A after B.
  function comparePoints(aNode, aOffset, bNode, bOffset) {
    var r = aNode.ownerDocument.createRange();
    r.setStart(aNode, aOffset);
    r.collapse(true);
    return -r.comparePoint(bNode, bOffset);
  }

  // Saved annotations of `type` overlapping `cfi`, and the range joining
  // them, so a new highlight replaces them instead of stacking on top.
  pgme.overlaps = function (cfi, type) {
    var c = contentsFor(cfi);
    if (!c) return null;
    var range;
    try { range = c.range(cfi); } catch (e) { return null; }
    if (!range) return null;
    var sN = range.startContainer, sO = range.startOffset;
    var eN = range.endContainer, eO = range.endOffset;
    var hits = [];
    var all = store();
    Object.keys(all).forEach(function (hash) {
      var a = all[hash];
      if (!a || a.type !== type || a.className === 'pgme-flash') return;
      if (a.sectionIndex !== c.sectionIndex) return;
      var r;
      try { r = c.range(a.cfiRange); } catch (e) { return; }
      if (!r) return;
      // Overlap: a.start < new.end and new.start < a.end.
      if (comparePoints(r.startContainer, r.startOffset, range.endContainer, range.endOffset) >= 0) return;
      if (comparePoints(range.startContainer, range.startOffset, r.endContainer, r.endOffset) >= 0) return;
      hits.push(a.cfiRange);
      if (comparePoints(r.startContainer, r.startOffset, sN, sO) < 0) { sN = r.startContainer; sO = r.startOffset; }
      if (comparePoints(r.endContainer, r.endOffset, eN, eO) > 0) { eN = r.endContainer; eO = r.endOffset; }
    });
    var union = c.document.createRange();
    union.setStart(sN, sO);
    union.setEnd(eN, eO);
    return JSON.stringify({ cfis: hits, union: c.cfiFromRange(union), text: union.toString() });
  };

  // ---- Selection -----------------------------------------------------------
  function clearSelectionFlags() {
    try {
      isSelecting = false;
      lastCfiRange = null;
      hasSentSelection = false;
      if (selectionTimeout) { clearTimeout(selectionTimeout); selectionTimeout = null; }
    } catch (e) {}
  }
  pgme.resetSelection = function () {
    try {
      rendition.getContents().forEach(function (c) {
        try { c.window.getSelection().removeAllRanges(); } catch (e) {}
      });
    } catch (e) {}
    try { window.getSelection().removeAllRanges(); } catch (e) {}
    clearSelectionFlags();
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

  // ---- Page turns and jumps ---------------------------------------------------
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
    if (!pgme.hasSelection()) clearSelectionFlags();
    pgme.directTurn = true;
    try {
      if (forward) { next(); } else { previous(); }
    } finally {
      pgme.directTurn = false;
    }
    return true;
  };
  pgme.goTo = function (target, flash) {
    if (!pgme.hasSelection()) clearSelectionFlags();
    var shown;
    try { shown = rendition.display(target); } catch (e) { return false; }
    if (flash && shown && shown.then) {
      shown.then(function () { setTimeout(function () { pgme.flash(target); }, 80); });
    }
    return true;
  };
  pgme.flash = function (cfi) {
    if (typeof cfi !== 'string' || cfi.indexOf('epubcfi(') !== 0) return false;
    // Already highlighted by the reader: it is visible as it is.
    if (store()[encodeURI(cfi + 'highlight')]) return false;
    try {
      var ann = rendition.annotations.highlight(cfi, {}, null, 'pgme-flash', {});
      if (ann && ann.mark) { patchMark(ann.mark); ann.mark.render(); }
    } catch (e) { return false; }
    setTimeout(function () {
      var a = store()[encodeURI(cfi + 'highlight')];
      if (a && a.className === 'pgme-flash') {
        try { rendition.annotations.remove(cfi, 'highlight'); } catch (e) {}
      }
    }, 2600);
    return true;
  };

  // ---- Page numbers ----------------------------------------------------------
  function fixedLayout() {
    try {
      if (rendition.settings && rendition.settings.layout === 'pre-paginated') return true;
      var meta = book.packaging && book.packaging.metadata;
      return !!(meta && meta.layout === 'pre-paginated');
    } catch (e) { return false; }
  }
  function printPages() {
    try {
      var pl = book.pageList;
      return !!(pl && pl.pages && pl.pages.length > 1 && isFinite(pl.lastPage));
    } catch (e) { return false; }
  }
  function pageMode() {
    if (printPages()) return 'print';
    if (fixedLayout()) return 'fixed';
    // Text pages only once they match the screen (see paginate).
    try { if (pgme.pageSize && book.locations && book.locations.length() > 0) return 'locations'; } catch (e) {}
    return null;
  }
  // Page numbers for a reflowable book: epub.js locations sized to what one
  // screen page holds, so turning a page moves the number by about one.
  // Built in the background in a separate index and swapped in at once;
  // rebuilt when the font, spacing or screen change the page size.
  pgme.pageSize = 0;
  pgme.pageKey = null;
  pgme.paginating = false;
  // `key` names the layout (font, size, spacing, screen). Pages are measured
  // once per layout, so the numbers stay put while reading.
  pgme.paginate = function (key) {
    if (printPages() || fixedLayout() || pgme.paginating) return false;
    if (key && key === pgme.pageKey) return false;
    var loc = rendition.location;
    if (!loc || !loc.start || !loc.start.displayed) return false;
    var total = loc.start.displayed.total;
    if (!(total >= 3)) return false;
    var c = contentsFor(loc.start.cfi);
    if (!c || !c.document || !c.document.body) return false;
    var chars = (c.document.body.textContent || '').replace(/\s+/g, ' ').length;
    var size = Math.max(300, Math.round(chars / total));
    // The book makes its own first index; wait for it.
    if (!book.locations || book.locations.length() === 0) return false;
    pgme.pageKey = key || null;
    if (pgme.pageSize && Math.abs(size - pgme.pageSize) / pgme.pageSize < 0.08) return false;
    pgme.paginating = true;
    var Locations = book.locations.constructor;
    var fresh = new Locations(book.spine, book.load.bind(book), 20);
    fresh.generate(size).then(function () {
      book.locations._locations = fresh._locations;
      book.locations.total = fresh.total;
      book.locations.break = size;
      pgme.pageSize = size;
      pgme.paginating = false;
      call('pgmePagesReady', true);
    }, function () { pgme.paginating = false; });
    return true;
  };
  // Text pages: page N starts at location N-1, so a position's page is the
  // number of page starts at or before it.
  function startsUpTo(cfi) {
    var L = book.locations._locations;
    if (!L || !L.length) return null;
    var cmp = new ePub.CFI();
    var idx = book.locations.locationFromCfi(cfi);
    if (idx < 0) return null;
    // locationFromCfi clips past the last start.
    if (idx === L.length - 1 && cmp.compare(cfi, L[idx]) > 0) idx = L.length;
    else if (idx < L.length && cmp.compare(cfi, L[idx]) === 0) idx += 1;
    return Math.max(1, Math.min(idx, L.length));
  }
  function pageOf(cfi, mode) {
    try {
      if (mode === 'print') { var p = book.pageList.pageFromCfi(cfi); return p > 0 ? p : null; }
      if (mode === 'fixed') { var s = new ePub.CFI(cfi).spinePos; return s >= 0 ? s + 1 : null; }
      if (mode === 'locations') return startsUpTo(cfi);
    } catch (e) {}
    return null;
  }
  // The page an item shows on, counted like the current page (to the end
  // of its screen), when its chapter is laid out; null otherwise.
  function screenPageOf(cfi) {
    try {
      var m = rendition.manager;
      if (!m || !m.mapping || !m.layout || rendition.settings.flow === 'scrolled') return null;
      var c = contentsFor(cfi);
      if (!c) return null;
      var range = c.range(cfi);
      var rects = range ? textRects(range) : [];
      var r = rects.length ? rects[0] : (range ? range.getBoundingClientRect() : null);
      if (!r) return null;
      var step = m.layout.delta || m.layout.width;
      if (!step) return null;
      var view = null;
      rendition.views().forEach(function (v) { if (v.contents === c) view = v; });
      if (!view) return null;
      var left = Math.floor(Math.max(0, r.left) / step) * step;
      var page = m.mapping.page(c, view.section.cfiBase, left, left + (m.layout.width || step));
      return page && page.end ? startsUpTo(page.end) : null;
    } catch (e) { return null; }
  }
  function pageTotal(mode) {
    try {
      if (mode === 'print') return book.pageList.lastPage;
      if (mode === 'fixed') return book.spine.length || book.spine.spineItems.length;
      if (mode === 'locations') return book.locations.length();
    } catch (e) {}
    return 0;
  }
  pgme.pageInfo = function () {
    var loc = rendition.location;
    var mode = pageMode();
    if (!loc || !loc.start || !mode) return null;
    // A screen holds about one page start: count up to the screen's end,
    // so "go to page N" shows N.
    var at = mode === 'locations' && loc.end && loc.end.cfi ? loc.end.cfi : loc.start.cfi;
    return JSON.stringify({ mode: mode, current: pageOf(at, mode), total: pageTotal(mode) });
  };
  pgme.targetForPage = function (n) {
    var mode = pageMode();
    try {
      if (mode === 'print') { var c = book.pageList.cfiFromPage(n); return typeof c === 'string' ? c : null; }
      if (mode === 'fixed') { var item = book.spine.get(n - 1); return item ? item.href : null; }
      if (mode === 'locations') { var l = book.locations.cfiFromLocation(n - 1); return typeof l === 'string' ? l : null; }
    } catch (e) {}
    return null;
  };

  // Which of `cfis` lie on the visible page (bookmarks survive font changes).
  pgme.onScreen = function (cfis) {
    var loc = rendition.location;
    if (!loc || !loc.start || !loc.end) return '[]';
    var cmp = new ePub.CFI();
    var out = [];
    (cfis || []).forEach(function (c) {
      try {
        if (cmp.compare(loc.start.cfi, c) <= 0 && cmp.compare(c, loc.end.cfi) <= 0) out.push(c);
      } catch (e) {}
    });
    return JSON.stringify(out);
  };

  // Chapter title and page for each location, in book order.
  function baseName(href) {
    var h = (href || '').split('#')[0];
    return h.substring(h.lastIndexOf('/') + 1);
  }
  function spineIndexOf(href) {
    var name = baseName(href);
    if (!name) return -1;
    var items = (book.spine && book.spine.spineItems) || [];
    for (var i = 0; i < items.length; i++) {
      if (baseName(items[i].href) === name) return items[i].index;
    }
    return -1;
  }
  var tocCache = null;
  function toc() {
    if (tocCache) return tocCache;
    var out = [];
    function walk(items) {
      (items || []).forEach(function (it) {
        out.push({ label: (it.label || '').trim(), spine: spineIndexOf(it.href) });
        walk(it.subitems);
      });
    }
    try { walk(book.navigation.toc); } catch (e) {}
    tocCache = out;
    return out;
  }
  pgme.describe = function (cfis) {
    var entries = toc(), mode = pageMode(), cmp = new ePub.CFI(), list = [];
    (cfis || []).forEach(function (cfi) {
      var spine = -1;
      try { spine = new ePub.CFI(cfi).spinePos; } catch (e) {}
      var chapter = '', before = '';
      for (var i = 0; i < entries.length; i++) {
        var t = entries[i];
        if (t.spine === spine && !chapter) chapter = t.label;
        if (t.spine >= 0 && t.spine < spine) before = t.label;
      }
      var page = mode === 'locations' ? (screenPageOf(cfi) || pageOf(cfi, mode)) : pageOf(cfi, mode);
      list.push({ cfi: cfi, chapter: chapter || before, page: page });
    });
    list.sort(function (a, b) {
      try { return cmp.compare(a.cfi, b.cfi); } catch (e) { return 0; }
    });
    return JSON.stringify(list);
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
    var view = window.innerWidth * window.innerHeight;
    var contents = rendition.getContents();
    for (var i = 0; i < contents.length; i++) {
      var c = contents[i], doc = c.document, fr = frameRect(c);
      if (!doc || !fr) continue;
      var lx = x - fr.left, ly = y - fr.top;
      if (lx < 0 || ly < 0 || lx > fr.width || ly > fr.height) continue;

      // Saved highlights and underlines, and the note badge after them.
      var hits = [], hitRects = [], noteTap = false;
      var all = store();
      Object.keys(all).forEach(function (hash) {
        var a = all[hash];
        if (!a || (a.type !== 'highlight' && a.type !== 'underline')) return;
        if (a.className === 'pgme-flash') return;
        if (c.sectionIndex !== undefined && a.sectionIndex !== c.sectionIndex) return;
        var range;
        try { range = c.range(a.cfiRange); } catch (e) { return; }
        if (!range) return;
        var rects = textRects(range);
        var hit = false;
        for (var k = 0; k < rects.length && !hit; k++) {
          var rr = rects[k];
          hit = lx >= rr.left - 4 && lx <= rr.right + 4 && ly >= rr.top - 4 && ly <= rr.bottom + 6;
        }
        var spot = a.data && a.data.pgmeNote ? noteDot(range, rects) : null;
        if (spot && Math.abs(lx - spot.x) <= 16 && Math.abs(ly - spot.y) <= 16) {
          hit = true;
          noteTap = true;
        }
        if (!hit) return;
        hits.push({ cfi: a.cfiRange, type: a.type });
        for (var m = 0; m < rects.length; m++) hitRects.push(rects[m]);
      });
      if (hits.length) {
        var hb = bounds(hitRects);
        return JSON.stringify({ kind: 'annotation', annotations: hits, noteTap: noteTap,
          rect: hb ? normalized(hb, fr) : null });
      }

      var elements = doc.elementsFromPoint ? doc.elementsFromPoint(lx, ly)
        : [doc.elementFromPoint(lx, ly)];
      for (var j = 0; j < elements.length; j++) {
        var el = elements[j];
        if (!el || !el.closest) continue;
        if (el.closest('a[href]')) return JSON.stringify({ kind: 'link' });

        var image = el.closest('img, image');
        if (image) {
          var box = image.getBoundingClientRect();
          // A fixed-layout page is one big image: tapping it shows/hides
          // the controls, as on any page.
          var wholePage = fixedLayout() && box.width * box.height > view * 0.5;
          var src = imageSource(image, doc);
          if (box.width >= 24 && box.height >= 24 && !wholePage && src) {
            pgme.focusedImage = image;
            return JSON.stringify({ kind: 'image', src: src,
              label: image.getAttribute('alt') || image.getAttribute('aria-label') || '',
              rect: normalized(box, fr) });
          }
        }

        var table = el.closest('table');
        if (table) {
          var tb = table.getBoundingClientRect();
          if (tb.width >= 40 && tb.height >= 24) {
            pgme.focusTarget = table;
            return JSON.stringify({ kind: 'table', rect: normalized(tb, fr),
              label: (table.querySelector('caption') || {}).textContent || '' });
          }
        }

        var figure = el.closest('svg');
        if (figure) {
          var fb = figure.getBoundingClientRect();
          if (fb.width >= 48 && fb.height >= 48 && !(fixedLayout() && fb.width * fb.height > view * 0.5)) {
            pgme.focusTarget = figure;
            return JSON.stringify({ kind: 'figure', rect: normalized(fb, fr), label: '' });
          }
        }
      }
    }
    return JSON.stringify({ kind: 'none' });
  };

  // ---- Focus view markup ------------------------------------------------------
  var FOCUS_PROPS = ['color', 'background-color', 'font-family', 'font-size',
    'font-weight', 'font-style', 'font-variant', 'line-height', 'text-align',
    'vertical-align', 'text-decoration-line', 'text-transform', 'letter-spacing',
    'white-space', 'text-indent', 'list-style-type',
    'padding-top', 'padding-right', 'padding-bottom', 'padding-left',
    'border-top-width', 'border-top-style', 'border-top-color',
    'border-right-width', 'border-right-style', 'border-right-color',
    'border-bottom-width', 'border-bottom-style', 'border-bottom-color',
    'border-left-width', 'border-left-style', 'border-left-color',
    'border-collapse', 'border-spacing', 'caption-side'];
  function inlineStyles(src, dst) {
    if (!src || !dst || src.nodeType !== 1) return;
    var cs = src.ownerDocument.defaultView.getComputedStyle(src);
    var s = '';
    for (var i = 0; i < FOCUS_PROPS.length; i++) {
      var v = cs.getPropertyValue(FOCUS_PROPS[i]);
      if (v !== '') s += FOCUS_PROPS[i] + ':' + v + ';';
    }
    dst.setAttribute('style', s);
    dst.removeAttribute('class');
    if (dst.localName === 'a') dst.removeAttribute('href');
    var sc = src.children, dc = dst.children;
    for (var j = 0; j < sc.length && j < dc.length; j++) inlineStyles(sc[j], dc[j]);
  }
  function dataUrl(src) {
    return fetch(src).then(function (r) { return r.blob(); }).then(function (blob) {
      return new Promise(function (resolve, reject) {
        var reader = new FileReader();
        reader.onload = function () { resolve(reader.result); };
        reader.onerror = function () { reject(reader.error); };
        reader.readAsDataURL(blob);
      });
    });
  }
  pgme.focusMarkup = async function () {
    var el = pgme.focusTarget;
    if (!el || !el.ownerDocument) return null;
    var doc = el.ownerDocument;
    var clone = el.cloneNode(true);
    if (el.localName !== 'svg') inlineStyles(el, clone);
    var from = el.querySelectorAll('img, image'), to = clone.querySelectorAll('img, image');
    for (var i = 0; i < from.length && i < to.length; i++) {
      var src = imageSource(from[i], doc);
      if (!src) continue;
      try {
        var data = await dataUrl(src);
        if (to[i].localName === 'img') {
          to[i].setAttribute('src', data);
          to[i].removeAttribute('srcset');
        } else {
          to[i].setAttribute('href', data);
          to[i].setAttributeNS('http://www.w3.org/1999/xlink', 'xlink:href', data);
        }
      } catch (e) {}
    }
    var html = clone.outerHTML;
    if (!html || html.length > 4000000) return null;
    var body = doc.defaultView.getComputedStyle(doc.body);
    // A table split across pages has one box per page: its width is the
    // widest piece (or its own width when it is wider than the column).
    var width = 0, pieces = el.getClientRects();
    for (var p = 0; p < pieces.length; p++) width = Math.max(width, pieces[p].width);
    if (!width) width = el.getBoundingClientRect().width;
    width = Math.max(width, el.offsetWidth || 0);
    return JSON.stringify({ html: html, width: Math.ceil(width),
      background: body.backgroundColor, color: body.color,
      font: body.fontFamily, size: body.fontSize });
  };

  // Text line under a point (for the line guide). Uses the character box
  // at the caret, then probes below it for the next line to get the line
  // pitch (line spacing differs per book and setting).
  function charBox(nx, ny) {
    var x = nx * window.innerWidth, y = ny * window.innerHeight;
    var contents = rendition.getContents();
    for (var i = 0; i < contents.length; i++) {
      var c = contents[i], doc = c.document, fr = frameRect(c);
      if (!doc || !fr || !doc.caretRangeFromPoint) continue;
      var lx = x - fr.left, ly = y - fr.top;
      if (lx < 0 || ly < 0 || lx > fr.width || ly > fr.height) continue;
      var caret = doc.caretRangeFromPoint(lx, ly);
      if (!caret || !caret.startContainer || caret.startContainer.nodeType !== 3) continue;
      var node = caret.startContainer;
      var offset = Math.min(caret.startOffset, node.length - 1);
      if (offset < 0) continue;
      var r = doc.createRange();
      r.setStart(node, offset);
      r.setEnd(node, offset + 1);
      var b = r.getBoundingClientRect();
      if (!b.height || ly < b.top - 3 || ly > b.bottom + 3) continue;
      return { top: b.top + fr.top, bottom: b.bottom + fr.top, height: b.height };
    }
    return null;
  }
  pgme.lineAt = function (nx, ny, scan) {
    var h = window.innerHeight, box = null;
    var limit = scan ? 0.6 : 0;
    for (var d = 0; d <= limit && !box; d += 4 / h) {
      box = charBox(nx, ny + d);
      if (!box && scan) box = charBox(0.5, ny + d);
    }
    if (!box) return null;
    var pitch = box.height * 1.35;
    for (var y = box.bottom + 1; y < box.bottom + box.height * 2.5; y += 2) {
      var next = charBox(nx, y / h) || charBox(0.5, y / h);
      if (next && next.top > box.top + box.height * 0.5) {
        pitch = next.top - box.top;
        break;
      }
    }
    return JSON.stringify({ top: box.top / h, pitch: pitch / h });
  };

  pgme.refreshMarks = function () {
    patchViews();
    try {
      rendition.views().forEach(function (view) {
        if (view && view.pane) view.pane.render();
      });
    } catch (e) {}
    return true;
  };

  pgme.setFocusedImageHidden = function (hidden) {
    var image = pgme.focusedImage;
    if (!image) return false;
    try { image.style.visibility = hidden ? 'hidden' : ''; } catch (e) {}
    if (!hidden) pgme.focusedImage = null;
    return true;
  };

  patchViews();
  return true;
})();
''';
}
