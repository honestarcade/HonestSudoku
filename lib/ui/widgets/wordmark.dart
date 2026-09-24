// "HonestSudoku", with Sudoku in teal, as the splash and the menu set it.

import 'package:flutter/widgets.dart';

import '../theme/tokens.dart';

/// The wordmark at [size] points.
class Wordmark extends StatelessWidget {
  /// Creates the wordmark.
  const Wordmark({required this.size, this.textScaler, super.key});

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
    return Text.rich(
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
    );
  }
}
