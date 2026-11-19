import 'package:flutter/material.dart';
import 'package:pgme/core/utils/epub_reader_theme.dart';

/// Preferences shared by all three app entry points.
Future<void> showEpubAppearanceSheet(
  BuildContext context, {
  required int fontSize,
  required bool isTablet,
  required bool supportsAnimatedPageTurns,
  required bool twoPageLayout,
  required bool isScrollMode,
  required bool portraitLock,
  required bool boldText,
  required double pageBrightness,
  required bool lineGuide,
  required double guideDimming,
  int guideLines = 2,
  ValueChanged<int>? onGuideLinesChanged,
  required EpubReadingTheme readingTheme,
  required EpubReadingFont readingFont,
  required EpubLineSpacing lineSpacing,
  required EpubPageTurn pageTurn,
  required Color accentColor,
  required ValueChanged<int> onFontSizeChanged,
  required ValueChanged<bool> onTwoPageLayoutChanged,
  required ValueChanged<bool> onReadingModeChanged,
  required ValueChanged<bool> onPortraitLockChanged,
  required ValueChanged<bool> onBoldTextChanged,
  required ValueChanged<double> onPageBrightnessChanged,
  required ValueChanged<bool> onLineGuideChanged,
  required ValueChanged<double> onGuideDimmingChanged,
  required ValueChanged<EpubReadingTheme> onReadingThemeChanged,
  required ValueChanged<EpubReadingFont> onReadingFontChanged,
  required ValueChanged<EpubLineSpacing> onLineSpacingChanged,
  required ValueChanged<EpubPageTurn> onPageTurnChanged,
}) {
  var size = fontSize.toDouble();
  var twoPages = twoPageLayout;
  var scroll = isScrollMode;
  var lock = portraitLock;
  var bold = boldText;
  var brightness = pageBrightness;
  var guide = lineGuide;
  var dimming = guideDimming;
  var lines = guideLines;
  var palette = readingTheme;
  var font = readingFont;
  var spacing = lineSpacing;
  var turn = pageTurn;

  return showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    showDragHandle: false,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (sheetContext) => StatefulBuilder(
      builder: (sheetContext, updateSheet) {
        final dark = readingThemeIsDark(
            palette, Theme.of(sheetContext).brightness == Brightness.dark);
        final sheetTheme = ThemeData.from(
          colorScheme: ColorScheme.fromSeed(
            seedColor: accentColor,
            brightness: dark ? Brightness.dark : Brightness.light,
          ),
          useMaterial3: true,
        );
        return Theme(
          data: sheetTheme,
          child: Material(
            color: sheetTheme.colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            child: Builder(
                builder: (context) => SizedBox(
                      height: MediaQuery.sizeOf(context).height * 0.78,
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(24, 0, 24, 28),
                        children: [
                          Center(
                              child: Container(
                            width: 36,
                            height: 4,
                            margin: const EdgeInsets.only(top: 10, bottom: 20),
                            decoration: BoxDecoration(
                              color: sheetTheme.colorScheme.onSurface
                                  .withValues(alpha: 0.35),
                              borderRadius: BorderRadius.circular(2),
                            ),
                          )),
                          Text('Reading appearance',
                              style: Theme.of(context).textTheme.titleLarge),
                          const SizedBox(height: 4),
                          Text('Make the page comfortable for you',
                              style: Theme.of(context).textTheme.bodySmall),
                          const SizedBox(height: 22),
                          Text('Text size',
                              style: Theme.of(context).textTheme.titleSmall),
                          Row(children: [
                            const Text('A', style: TextStyle(fontSize: 14)),
                            Expanded(
                              child: Slider(
                                value: size,
                                min: 13,
                                max: 24,
                                divisions: 11,
                                activeColor: accentColor,
                                label: '${size.round()}',
                                onChanged: (value) =>
                                    updateSheet(() => size = value),
                                onChangeEnd: (value) =>
                                    onFontSizeChanged(value.round()),
                              ),
                            ),
                            const Text('A', style: TextStyle(fontSize: 24)),
                          ]),
                          const SizedBox(height: 8),
                          Text('Page color',
                              style: Theme.of(context).textTheme.titleSmall),
                          const SizedBox(height: 8),
                          Wrap(spacing: 8, runSpacing: 8, children: [
                            for (final (value, label, color) in [
                              (EpubReadingTheme.followApp, 'App', accentColor),
                              (EpubReadingTheme.light, 'White', Colors.white),
                              (
                                EpubReadingTheme.warm,
                                'Warm',
                                const Color(0xFFF7F0E3)
                              ),
                              (
                                EpubReadingTheme.dark,
                                'Dark',
                                const Color(0xFF121212)
                              ),
                            ])
                              ChoiceChip(
                                label: Text(label),
                                avatar: CircleAvatar(
                                    backgroundColor: color, radius: 8),
                                selected: palette == value,
                                selectedColor:
                                    accentColor.withValues(alpha: 0.15),
                                onSelected: (_) {
                                  updateSheet(() => palette = value);
                                  onReadingThemeChanged(value);
                                },
                              ),
                          ]),
                          const SizedBox(height: 20),
                          Text('Font',
                              style: Theme.of(context).textTheme.titleSmall),
                          const SizedBox(height: 8),
                          Wrap(spacing: 8, runSpacing: 8, children: [
                            for (final (value, label) in [
                              (EpubReadingFont.original, 'Book'),
                              (EpubReadingFont.serif, 'Serif'),
                              (EpubReadingFont.sans, 'Sans serif'),
                            ])
                              ChoiceChip(
                                label: Text(label),
                                selected: font == value,
                                selectedColor:
                                    accentColor.withValues(alpha: 0.15),
                                onSelected: (_) {
                                  updateSheet(() => font = value);
                                  onReadingFontChanged(value);
                                },
                              ),
                          ]),
                          SwitchListTile.adaptive(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('Bold text'),
                            subtitle:
                                const Text('Increase the weight of body text'),
                            activeTrackColor: accentColor,
                            value: bold,
                            onChanged: (value) {
                              updateSheet(() => bold = value);
                              onBoldTextChanged(value);
                            },
                          ),
                          Text('Line spacing',
                              style: Theme.of(context).textTheme.titleSmall),
                          const SizedBox(height: 8),
                          Wrap(spacing: 8, runSpacing: 8, children: [
                            for (final (value, label) in [
                              (EpubLineSpacing.original, 'Book'),
                              (EpubLineSpacing.compact, 'Compact'),
                              (EpubLineSpacing.relaxed, 'Relaxed'),
                            ])
                              ChoiceChip(
                                label: Text(label),
                                selected: spacing == value,
                                selectedColor:
                                    accentColor.withValues(alpha: 0.15),
                                onSelected: (_) {
                                  updateSheet(() => spacing = value);
                                  onLineSpacingChanged(value);
                                },
                              ),
                          ]),
                          const SizedBox(height: 20),
                          Text('Page brightness',
                              style: Theme.of(context).textTheme.titleSmall),
                          Row(children: [
                            const Icon(Icons.brightness_low, size: 18),
                            Expanded(
                                child: Slider(
                              value: brightness,
                              min: 0.75,
                              max: 1,
                              divisions: 5,
                              activeColor: accentColor,
                              label: '${(brightness * 100).round()}%',
                              onChanged: (value) {
                                updateSheet(() => brightness = value);
                                onPageBrightnessChanged(value);
                              },
                            )),
                            const Icon(Icons.brightness_high, size: 20),
                          ]),
                          const SizedBox(height: 20),
                          Text('Navigation',
                              style: Theme.of(context).textTheme.titleSmall),
                          const SizedBox(height: 8),
                          Wrap(spacing: 8, runSpacing: 8, children: [
                            for (final (value, label, icon) in [
                              (EpubPageTurn.slide, 'Slide', Icons.swipe),
                              if (supportsAnimatedPageTurns) ...[
                                (
                                  EpubPageTurn.curl,
                                  'Curl',
                                  Icons.auto_stories
                                ),
                                (
                                  EpubPageTurn.fastFade,
                                  'Fast fade',
                                  Icons.blur_on
                                ),
                              ],
                            ])
                              ChoiceChip(
                                label: Text(label),
                                avatar: Icon(icon, size: 18),
                                selected: !scroll && turn == value,
                                selectedColor:
                                    accentColor.withValues(alpha: 0.15),
                                onSelected: (_) {
                                  updateSheet(() {
                                    scroll = false;
                                    turn = value;
                                  });
                                  onPageTurnChanged(value);
                                  onReadingModeChanged(false);
                                },
                              ),
                            ChoiceChip(
                              label: const Text('Scroll'),
                              avatar: const Icon(Icons.view_day, size: 18),
                              selected: scroll,
                              selectedColor:
                                  accentColor.withValues(alpha: 0.15),
                              onSelected: (_) {
                                updateSheet(() => scroll = true);
                                onReadingModeChanged(true);
                              },
                            ),
                          ]),
                          if (isTablet)
                            SwitchListTile.adaptive(
                              contentPadding: EdgeInsets.zero,
                              title: const Text('Two-page layout'),
                              subtitle: const Text(
                                  'Show facing pages when space allows'),
                              activeTrackColor: accentColor,
                              value: twoPages,
                              onChanged: (value) {
                                updateSheet(() => twoPages = value);
                                onTwoPageLayoutChanged(value);
                              },
                            ),
                          SwitchListTile.adaptive(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('Lock reader to portrait'),
                            activeTrackColor: accentColor,
                            value: lock,
                            onChanged: (value) {
                              updateSheet(() => lock = value);
                              onPortraitLockChanged(value);
                            },
                          ),
                          SwitchListTile.adaptive(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('Line guide'),
                            subtitle: const Text(
                                'Keeps your eyes on a few lines and dims the '
                                'rest. Tap any line to move it there.'),
                            activeTrackColor: accentColor,
                            value: guide,
                            onChanged: (value) {
                              updateSheet(() => guide = value);
                              onLineGuideChanged(value);
                            },
                          ),
                          if (guide) ...[
                            const SizedBox(height: 4),
                            const Text('Guide height'),
                            const SizedBox(height: 8),
                            Wrap(spacing: 8, children: [
                              for (final n in const [1, 2, 3])
                                ChoiceChip(
                                  label: Text(n == 1 ? '1 line' : '$n lines'),
                                  selected: lines == n,
                                  selectedColor:
                                      accentColor.withValues(alpha: 0.15),
                                  onSelected: (_) {
                                    updateSheet(() => lines = n);
                                    onGuideLinesChanged?.call(n);
                                  },
                                ),
                            ]),
                            const SizedBox(height: 12),
                            const Text('Dim outside the guide'),
                            Slider(
                              value: dimming,
                              min: 0,
                              max: 0.7,
                              divisions: 7,
                              activeColor: accentColor,
                              label: '${(dimming * 100).round()}%',
                              onChanged: (value) =>
                                  updateSheet(() => dimming = value),
                              onChangeEnd: onGuideDimmingChanged,
                            ),
                          ],
                        ],
                      ),
                    )),
          ),
        );
      },
    ),
  );
}
