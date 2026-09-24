// "HonestSudoku", with Sudoku in teal, as the splash and the menu set it.

import 'package:flutter/widgets.dart';

import '../theme/tokens.dart';

/// The wordmark at [size] points.
class Wordmark extends StatelessWidget {
  /// Creates the wordmark.
  const Wordmark({
    required this.size,
    this.textScaler,
    this.header = false,
    super.key,
  });

  /// Whether it is the screen's heading (the menu's).
  final bool header;

  /// Font size.
  final double size;

  /// Overrides the system text scale (the splash pins its text).
  final TextScaler? textScaler;

  @override
  Widget build(BuildContext context) {
    final style = outfit(
      size,
      scale: 1,
      weight: FontWeight.w700,
      letterSpacingEm: -.03,
    );
    // Spoken as two words; its two colours are decoration (#56).
    return Semantics(
      label: 'Honest Sudoku',
      header: header,
      excludeSemantics: true,
      child: Text.rich(
        TextSpan(
          style: style,
          children: [
            const TextSpan(text: 'Honest'),
            TextSpan(
              text: 'Sudoku',
              style: style.copyWith(color: HsColors.teal),
            ),
          ],
        ),
        textScaler: textScaler,
        softWrap: false,
      ),
    );
  }
}
