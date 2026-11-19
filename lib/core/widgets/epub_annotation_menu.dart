import 'package:flutter/material.dart';

/// Highlight colours offered in the reader (names match the backend's
/// allowed values).
const epubHighlightColors = <String, Color>{
  'yellow': Color(0xFFFFD84D),
  'green': Color(0xFF7ED58C),
  'blue': Color(0xFF7DB8FF),
  'pink': Color(0xFFFF93BE),
};

/// Floating menu shown over a text selection or a tapped highlight, in the
/// style of Apple Books: colour dots, then underline, note and remove.
///
/// [anchor] is the selection/annotation rectangle and [area] the size of the
/// book view, both in the same local coordinates as the enclosing Stack.
class EpubAnnotationMenu extends StatelessWidget {
  const EpubAnnotationMenu({
    super.key,
    required this.anchor,
    required this.area,
    required this.dark,
    required this.accentColor,
    required this.onColor,
    this.selectedColor,
    this.underlined = false,
    this.onUnderline,
    this.onNote,
    this.hasNote = false,
    this.onRemove,
  });

  final Rect anchor;
  final Size area;
  final bool dark;
  final Color accentColor;
  final String? selectedColor;
  final ValueChanged<String> onColor;
  final bool underlined;
  final VoidCallback? onUnderline;
  final VoidCallback? onNote;
  final bool hasNote;
  final VoidCallback? onRemove;

  static const double _height = 52;

  @override
  Widget build(BuildContext context) {
    final actions = <Widget>[
      for (final entry in epubHighlightColors.entries)
        _ColorDot(
          color: entry.value,
          name: entry.key,
          selected: selectedColor == entry.key,
          ringColor: dark ? Colors.white : const Color(0xFF1C1C1E),
          onTap: () => onColor(entry.key),
        ),
      if (onUnderline != null || onNote != null || onRemove != null)
        Container(
            width: 1,
            height: 26,
            margin: const EdgeInsets.symmetric(horizontal: 4),
            color: dark ? Colors.white24 : Colors.black12),
      if (onUnderline != null)
        _MenuIcon(
          icon: Icons.format_underlined,
          tooltip: underlined ? 'Remove underline' : 'Underline',
          color: underlined
              ? accentColor
              : (dark ? Colors.white : const Color(0xFF1C1C1E)),
          onTap: onUnderline!,
        ),
      if (onNote != null)
        _MenuIcon(
          icon: hasNote ? Icons.sticky_note_2 : Icons.sticky_note_2_outlined,
          tooltip: hasNote ? 'Edit note' : 'Add note',
          color: dark ? Colors.white : const Color(0xFF1C1C1E),
          onTap: onNote!,
        ),
      if (onRemove != null)
        _MenuIcon(
          icon: Icons.delete_outline,
          tooltip: 'Remove',
          color: const Color(0xFFE5484D),
          onTap: onRemove!,
        ),
    ];
    final width = 16.0 +
        epubHighlightColors.length * 40 +
        (actions.length - epubHighlightColors.length) * 44;
    final menuWidth = width.clamp(0.0, area.width - 16).toDouble();
    final left = (anchor.center.dx - menuWidth / 2)
        .clamp(8.0, (area.width - menuWidth - 8).clamp(8.0, double.infinity))
        .toDouble();
    // Above the text when there is room (selection handles sit below it).
    final above = anchor.top - _height - 14;
    final below = anchor.bottom + 18;
    final top = (above >= 8 ? above : below)
        .clamp(8.0, (area.height - _height - 8).clamp(8.0, double.infinity))
        .toDouble();

    return Positioned(
      left: left,
      top: top,
      width: menuWidth,
      height: _height,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0.85, end: 1),
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOutCubic,
        builder: (context, value, child) => Opacity(
          opacity: ((value - 0.85) / 0.15).clamp(0.0, 1.0),
          child: Transform.scale(scale: value, child: child),
        ),
        child: Material(
          color: dark ? const Color(0xFF2C2C2E) : Colors.white,
          elevation: 10,
          shadowColor: Colors.black54,
          borderRadius: BorderRadius.circular(26),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(children: actions),
          ),
        ),
      ),
    );
  }
}

class _ColorDot extends StatelessWidget {
  const _ColorDot({
    required this.color,
    required this.name,
    required this.selected,
    required this.ringColor,
    required this.onTap,
  });

  final Color color;
  final String name;
  final bool selected;
  final Color ringColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: 'Highlight $name',
      child: InkResponse(
        onTap: onTap,
        radius: 22,
        child: SizedBox(
          width: 40,
          height: 52,
          child: Center(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                border: Border.all(
                    color: selected ? ringColor : Colors.black12,
                    width: selected ? 2.5 : 1),
              ),
              child: selected
                  ? Icon(Icons.check, size: 15, color: ringColor)
                  : null,
            ),
          ),
        ),
      ),
    );
  }
}

class _MenuIcon extends StatelessWidget {
  const _MenuIcon({
    required this.icon,
    required this.tooltip,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkResponse(
        onTap: onTap,
        radius: 22,
        child: SizedBox(
            width: 44, height: 52, child: Icon(icon, size: 22, color: color)),
      ),
    );
  }
}
