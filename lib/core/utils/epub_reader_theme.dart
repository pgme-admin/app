import 'package:flutter/material.dart';
import 'package:flutter_epub_viewer/flutter_epub_viewer.dart';

enum EpubReadingTheme { followApp, light, warm, dark }

enum EpubReadingFont { original, serif, sans }

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

bool readingThemeIsDark(EpubReadingTheme theme, bool appIsDark) =>
    theme == EpubReadingTheme.dark ||
    (theme == EpubReadingTheme.followApp && appIsDark);

/// Keep the publisher's typography unless the reader chooses a font.
EpubTheme epubReadingTheme(
  EpubReadingTheme theme,
  EpubReadingFont font,
  bool appIsDark,
) {
  final dark = readingThemeIsDark(theme, appIsDark);
  final warm = theme == EpubReadingTheme.warm;
  final background = dark
      ? const Color(0xFF121212)
      : warm
          ? const Color(0xFFF7F0E3)
          : Colors.white;
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
  if (font != EpubReadingFont.original) {
    final family = font == EpubReadingFont.serif
        ? 'Georgia, "Times New Roman", serif'
        : '-apple-system, BlinkMacSystemFont, "Helvetica Neue", Arial, sans-serif';
    css['body, p, li, blockquote'] = <String, String>{
      'font-family': '$family !important',
    };
  }
  return EpubTheme.custom(
    backgroundDecoration: BoxDecoration(color: background),
    foregroundColor: foreground,
    customCss: css,
  );
}
