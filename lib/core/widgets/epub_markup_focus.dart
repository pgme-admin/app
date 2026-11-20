import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:pgme/core/utils/epub_reader_bridge.dart';

/// Opens a table or figure from the book on its own, the way Apple Books
/// does: it grows out of its spot on the page into a full-screen view where
/// it can be pinched, zoomed and scrolled in both directions. A table wider
/// than the screen first appears whole (zoomed out to fit).
///
/// Closes with Done, Back or Escape.
Future<void> showEpubMarkupFocus(
  BuildContext context, {
  required EpubFocusMarkup markup,
  required Rect origin,
  required bool dark,
  required String title,
}) {
  final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
  return Navigator.of(context, rootNavigator: true).push(PageRouteBuilder<void>(
    opaque: false,
    barrierColor: null,
    transitionDuration:
        reduceMotion ? Duration.zero : const Duration(milliseconds: 300),
    reverseTransitionDuration:
        reduceMotion ? Duration.zero : const Duration(milliseconds: 220),
    pageBuilder: (context, animation, _) => _MarkupFocus(
      markup: markup,
      origin: origin,
      dark: dark,
      title: title,
      animation: animation,
    ),
  ));
}

/// Parses a CSS colour as returned by getComputedStyle ("rgb(r, g, b)" or
/// "rgba(r, g, b, a)"). Null when it is missing or fully transparent.
@visibleForTesting
Color? cssColor(String value) {
  final m =
      RegExp(r'rgba?\(\s*([\d.]+)[ ,]+([\d.]+)[ ,]+([\d.]+)(?:[ ,/]+([\d.]+))?')
          .firstMatch(value);
  if (m == null) return null;
  final alpha = m.group(4) == null ? 1.0 : double.tryParse(m.group(4)!) ?? 1;
  if (alpha <= 0.01) return null;
  int c(int i) => (double.tryParse(m.group(i)!) ?? 0).round().clamp(0, 255);
  return Color.fromARGB((alpha * 255).round().clamp(0, 255), c(1), c(2), c(3));
}

String _css(Color c) =>
    'rgb(${(c.r * 255).round()}, ${(c.g * 255).round()}, ${(c.b * 255).round()})';

/// The page shown in the focus view. Its layout width is the table's own
/// width (at least the screen's), so a wide table starts fitted to the
/// screen and zooms in from there.
@visibleForTesting
String epubMarkupPage(EpubFocusMarkup markup,
    {required double screenWidth,
    required Color background,
    required Color foreground}) {
  final layoutWidth = math.max(screenWidth, markup.width + 32).ceil();
  final font = markup.fontFamily.isEmpty
      ? '-apple-system, Roboto, sans-serif'
      : markup.fontFamily;
  final size = markup.fontSize.isEmpty ? '16px' : markup.fontSize;
  return '<!DOCTYPE html><html><head><meta charset="utf-8">'
      '<meta name="viewport" content="width=$layoutWidth, minimum-scale=0.2, '
      'maximum-scale=6, user-scalable=yes">'
      '<style>'
      'html,body{margin:0;padding:0;background:${_css(background)};'
      'color:${_css(foreground)};-webkit-text-size-adjust:100%;}'
      'body{padding:16px 16px 40px;font-family:$font;font-size:$size;}'
      'table{margin:0 auto;}'
      'img,svg{max-width:100%;height:auto;}'
      '</style></head><body>${markup.html}</body></html>';
}

class _MarkupFocus extends StatelessWidget {
  const _MarkupFocus({
    required this.markup,
    required this.origin,
    required this.dark,
    required this.title,
    required this.animation,
  });

  final EpubFocusMarkup markup;
  final Rect origin;
  final bool dark;
  final String title;
  final Animation<double> animation;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final background = cssColor(markup.background) ??
        (dark ? const Color(0xFF121214) : Colors.white);
    final foreground = cssColor(markup.color) ??
        (dark ? const Color(0xFFE8E8EA) : const Color(0xFF1C1C1E));
    final isDarkPage = background.computeLuminance() < 0.4;
    final barText = isDarkPage ? Colors.white : const Color(0xFF1C1C1E);
    final page = epubMarkupPage(markup,
        screenWidth: media.size.width,
        background: background,
        foreground: foreground);
    // Grows from the table's spot on the page.
    final screen = Offset.zero & media.size;
    final alignment = Alignment(
      screen.width <= 0
          ? 0
          : (origin.center.dx / screen.width * 2 - 1).clamp(-1.0, 1.0),
      screen.height <= 0
          ? 0
          : (origin.center.dy / screen.height * 2 - 1).clamp(-1.0, 1.0),
    );
    final curve = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic);

    void close() => Navigator.of(context).maybePop();

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value:
          isDarkPage ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.escape): close,
        },
        child: Focus(
          autofocus: true,
          child: AnimatedBuilder(
            animation: curve,
            builder: (context, child) {
              final t = curve.value;
              final startScale = origin.width <= 0
                  ? 0.9
                  : (origin.width / media.size.width).clamp(0.3, 0.95);
              return Opacity(
                opacity: t.clamp(0.0, 1.0),
                child: Transform.scale(
                  scale: startScale + (1 - startScale) * t,
                  alignment: alignment,
                  child: child,
                ),
              );
            },
            child: Material(
              color: background,
              child: Column(children: [
                SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 6, 10, 6),
                    child: Row(children: [
                      Expanded(
                        child: Text(title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontFamily: 'SF Pro Display',
                                fontSize: 17,
                                fontWeight: FontWeight.w600,
                                color: barText)),
                      ),
                      Semantics(
                        button: true,
                        label: 'Close',
                        child: TextButton(
                          onPressed: close,
                          style: TextButton.styleFrom(
                            backgroundColor: barText.withValues(
                                alpha: isDarkPage ? 0.16 : 0.08),
                            shape: const StadiumBorder(),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 8),
                          ),
                          child: Text('Done',
                              style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  color: barText)),
                        ),
                      ),
                    ]),
                  ),
                ),
                Divider(
                    height: 1,
                    color: barText.withValues(alpha: isDarkPage ? 0.14 : 0.08)),
                Expanded(
                  child: InAppWebView(
                    initialData: InAppWebViewInitialData(
                        data: page, mimeType: 'text/html', encoding: 'utf-8'),
                    initialSettings: InAppWebViewSettings(
                      // Book content only; nothing here needs scripts.
                      javaScriptEnabled: false,
                      transparentBackground: true,
                      supportZoom: true,
                      builtInZoomControls: true,
                      displayZoomControls: false,
                      useWideViewPort: true,
                      loadWithOverviewMode: true,
                      allowsLinkPreview: false,
                      disableContextMenu: true,
                      disableHorizontalScroll: false,
                      disableVerticalScroll: false,
                    ),
                  ),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
