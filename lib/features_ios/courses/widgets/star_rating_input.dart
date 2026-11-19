import 'package:flutter/material.dart';

/// Interactive star rating widget. Renders 5 tappable stars.
/// [current] is 0 (no selection) to 5.
/// [onChanged] is called with the new rating when a star is tapped.
class StarRatingInput extends StatelessWidget {
  final int current;
  final ValueChanged<int> onChanged;
  final double size;

  const StarRatingInput({
    super.key,
    required this.current,
    required this.onChanged,
    this.size = 32,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (index) {
        final isFilled = index < current;
        return GestureDetector(
          onTap: () => onChanged(index + 1),
          child: Padding(
            padding: EdgeInsets.only(right: index < 4 ? 6.0 : 0),
            child: Icon(
              isFilled ? Icons.star : Icons.star_border,
              color: isFilled ? const Color(0xFFFFC107) : Colors.white38,
              size: size,
            ),
          ),
        );
      }),
    );
  }
}

/// Read-only star display. Shows [rating] filled stars out of 5.
class StarRatingDisplay extends StatelessWidget {
  final int rating;
  final double size;

  const StarRatingDisplay({
    super.key,
    required this.rating,
    this.size = 24,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (index) {
        final isFilled = index < rating;
        return Padding(
          padding: EdgeInsets.only(right: index < 4 ? 4.0 : 0),
          child: Icon(
            isFilled ? Icons.star : Icons.star_border,
            color: isFilled ? const Color(0xFFFFC107) : Colors.white38,
            size: size,
          ),
        );
      }),
    );
  }
}
