import 'package:flutter/material.dart';
import 'package:pgme/core/utils/epub_reader_theme.dart';

/// Preferences shared by all three app entry points.
Future<void> showEpubAppearanceSheet(
  BuildContext context, {
  required int fontSize,
  required bool isTablet,
  required bool twoPageLayout,
  required bool isScrollMode,
  required bool portraitLock,
  required bool lineGuide,
  required double guideDimming,
  required EpubReadingTheme readingTheme,
  required EpubReadingFont readingFont,
  required Color accentColor,
  required ValueChanged<int> onFontSizeChanged,
  required ValueChanged<bool> onTwoPageLayoutChanged,
  required ValueChanged<bool> onReadingModeChanged,
  required ValueChanged<bool> onPortraitLockChanged,
  required ValueChanged<bool> onLineGuideChanged,
  required ValueChanged<double> onGuideDimmingChanged,
  required ValueChanged<EpubReadingTheme> onReadingThemeChanged,
  required ValueChanged<EpubReadingFont> onReadingFontChanged,
}) {
  var size = fontSize.toDouble();
  var twoPages = twoPageLayout;
  var scroll = isScrollMode;
  var lock = portraitLock;
  var guide = lineGuide;
  var dimming = guideDimming;
  var palette = readingTheme;
  var font = readingFont;

  return showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) => StatefulBuilder(
      builder: (context, updateSheet) => SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.72,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 28),
          children: [
            Text('Reading appearance',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 22),
            Text('Text size', style: Theme.of(context).textTheme.titleSmall),
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
                  onChanged: (value) => updateSheet(() => size = value),
                  onChangeEnd: (value) => onFontSizeChanged(value.round()),
                ),
              ),
              const Text('A', style: TextStyle(fontSize: 24)),
            ]),
            const SizedBox(height: 8),
            Text('Page color', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final (value, label, color) in [
                (EpubReadingTheme.followApp, 'App', accentColor),
                (EpubReadingTheme.light, 'White', Colors.white),
                (EpubReadingTheme.warm, 'Warm', const Color(0xFFF7F0E3)),
                (EpubReadingTheme.dark, 'Dark', const Color(0xFF121212)),
              ])
                ChoiceChip(
                  label: Text(label),
                  avatar: CircleAvatar(backgroundColor: color, radius: 8),
                  selected: palette == value,
                  selectedColor: accentColor.withValues(alpha: 0.15),
                  onSelected: (_) {
                    updateSheet(() => palette = value);
                    onReadingThemeChanged(value);
                  },
                ),
            ]),
            const SizedBox(height: 20),
            Text('Font', style: Theme.of(context).textTheme.titleSmall),
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
                  selectedColor: accentColor.withValues(alpha: 0.15),
                  onSelected: (_) {
                    updateSheet(() => font = value);
                    onReadingFontChanged(value);
                  },
                ),
            ]),
            const SizedBox(height: 20),
            Text('Navigation', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(
                    value: false,
                    icon: Icon(Icons.auto_stories),
                    label: Text('Pages')),
                ButtonSegment(
                    value: true,
                    icon: Icon(Icons.view_day),
                    label: Text('Scroll')),
              ],
              selected: {scroll},
              onSelectionChanged: (selection) {
                final value = selection.first;
                updateSheet(() => scroll = value);
                onReadingModeChanged(value);
              },
            ),
            if (isTablet)
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: const Text('Two-page layout'),
                subtitle: const Text('Show facing pages when space allows'),
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
              subtitle: const Text('Highlight one reading band'),
              activeTrackColor: accentColor,
              value: guide,
              onChanged: (value) {
                updateSheet(() => guide = value);
                onLineGuideChanged(value);
              },
            ),
            if (guide) ...[
              const Text('Background dimming'),
              Slider(
                value: dimming,
                min: 0,
                max: 0.7,
                divisions: 7,
                activeColor: accentColor,
                label: '${(dimming * 100).round()}%',
                onChanged: (value) => updateSheet(() => dimming = value),
                onChangeEnd: onGuideDimmingChanged,
              ),
            ],
          ],
        ),
      ),
    ),
  );
}
