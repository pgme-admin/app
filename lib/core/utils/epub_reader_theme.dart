import 'package:flutter/material.dart';
import 'package:flutter_epub_viewer/flutter_epub_viewer.dart';

enum EpubReadingTheme { followApp, light, warm, dark }

enum EpubReadingFont { original, serif, sans }

enum EpubLineSpacing { original, compact, relaxed }

/// How a page turns in paginated mode (Apple Books: Slide, Curl, Fast Fade).
enum EpubPageTurn { slide, curl, fastFade }

EpubReadingTheme readingThemeFromName(String? name) =>
    EpubReadingTheme.values.firstWhere(
      (value) => value.name == name,
      orElse: () => EpubReadingTheme.followApp,
    );

EpubReadingFont readingFontFromName(String? name) =>
    EpubReadingFont.values.firstWhere(
      (value) => value.name == name,
      orElse: () => EpubReadingFont.original,
    );

EpubLineSpacing lineSpacingFromName(String? name) =>
    EpubLineSpacing.values.firstWhere(
      (value) => value.name == name,
      orElse: () => EpubLineSpacing.original,
    );

EpubPageTurn pageTurnFromName(String? name) => EpubPageTurn.values.firstWhere(
      (value) => value.name == name,
      orElse: () => EpubPageTurn.slide,
    );

bool readingThemeIsDark(EpubReadingTheme theme, bool appIsDark) =>
    theme == EpubReadingTheme.dark ||
    (theme == EpubReadingTheme.followApp && appIsDark);

/// The colour of the reading page. The book page itself is transparent, so
/// this is the colour seen behind the text; everything drawn in its place
/// (page-turn stills, the curl, the loading cover) must use exactly this
/// colour, or the page blinks to another colour (white on Warm) mid-turn.
Color epubPageColor(EpubReadingTheme theme, bool appIsDark) {
  if (readingThemeIsDark(theme, appIsDark)) return const Color(0xFF121212);
  if (theme == EpubReadingTheme.warm) return const Color(0xFFF7F0E3);
  return Colors.white;
}

/// The reader's screen insets with any keyboard left out. Flutter drops the
/// bottom safe-area padding while a keyboard shows; the reader lays out with
/// the screen's own insets instead, so a keyboard (note editor, search, go
/// to page) never changes the size of the book, which would re-lay out the
/// book and move it to another page.
MediaQueryData readerMediaWithoutKeyboard(MediaQueryData media) =>
    media.copyWith(
      viewInsets: EdgeInsets.zero,
      padding: media.padding.copyWith(bottom: media.viewPadding.bottom),
    );

/// Keep the publisher's typography unless the reader chooses a font.
EpubTheme epubReadingTheme(
  EpubReadingTheme theme,
  EpubReadingFont font,
  bool appIsDark, {
  bool boldText = false,
  EpubLineSpacing lineSpacing = EpubLineSpacing.original,
}) {
  final dark = readingThemeIsDark(theme, appIsDark);
  final warm = theme == EpubReadingTheme.warm;
  final background = epubPageColor(theme, appIsDark);
  final foreground = dark
      ? const Color(0xFFF1F1F1)
      : warm
          ? const Color(0xFF332B23)
          : const Color(0xFF1C1C1E);
  final backgroundCss = dark
      ? '#121212'
      : warm
          ? '#F7F0E3'
          : '#FFFFFF';
  final foregroundCss = dark
      ? '#F1F1F1'
      : warm
          ? '#332B23'
          : '#1C1C1E';
  final css = <String, dynamic>{
    'html, body': <String, String>{
      'background-color': backgroundCss,
      'color': foregroundCss,
    },
  };
  if (dark) {
    // Publisher link blue can be almost invisible on a dark reading page.
    // Keep links distinct without changing non-link text or image colors.
    css['a, a:link, a:visited, a *'] = <String, String>{
      'color': '#8ABFFF !important',
    };
  }
  final textCss = <String, String>{};
  if (font != EpubReadingFont.original) {
    final family = font == EpubReadingFont.serif
        ? 'Georgia, "Times New Roman", serif'
        : '-apple-system, BlinkMacSystemFont, "Helvetica Neue", Arial, sans-serif';
    textCss['font-family'] = '$family !important';
  }
  if (boldText) textCss['font-weight'] = '600 !important';
  if (lineSpacing != EpubLineSpacing.original) {
    textCss['line-height'] = lineSpacing == EpubLineSpacing.compact
        ? '1.35 !important'
        : '1.7 !important';
  }
  if (textCss.isNotEmpty) css['body, p, li, blockquote'] = textCss;
  return EpubTheme.custom(
    backgroundDecoration: BoxDecoration(color: background),
    foregroundColor: foreground,
    customCss: css,
  );
}

/// EPUB navigation files often keep the browser's dark blue link color even
/// after epub.js changes the body text. Apply contrast to the rendered book
/// documents, including sections loaded after a page turn.
Future<void> applyEpubLinkContrast(EpubController controller, bool dark) async {
  await controller.webViewController?.evaluateJavascript(source: '''
    (function () {
      if (typeof rendition === 'undefined') return;
      window.pgmeLinkContrastDark = $dark;
      window.pgmeApplyLinkContrast = function (contents) {
        var doc = contents && contents.document;
        if (!doc) return;
        var style = doc.getElementById('pgme-link-contrast');
        if (!window.pgmeLinkContrastDark) {
          if (style) style.remove();
          return;
        }
        if (!style) {
          style = doc.createElement('style');
          style.id = 'pgme-link-contrast';
          (doc.head || doc.getElementsByTagName('head')[0]).appendChild(style);
        }
        style.textContent = 'a, a:link, a:visited, a strong, a em, a span'
          + '{color:#8ABFFF !important;}';
      };
      if (!window.pgmeLinkContrastHook) {
        rendition.hooks.content.register(function (contents) {
          window.pgmeApplyLinkContrast(contents);
        });
        window.pgmeLinkContrastHook = true;
      }
      rendition.getContents().forEach(window.pgmeApplyLinkContrast);
    })();
  ''');
}
