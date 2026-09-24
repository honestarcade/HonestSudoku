// The project's tap-target guideline (#56): Flutter's Android 48×48 dp rule,
// except for grid cells.
//
// A 16×16 cell is 22 design points: a 48-dp cell would not fit a phone.
// Cells are reachable instead by their spoken labels and the grid's order
// (#51), and a player can select any cell by exploring the grid. Nodes that
// #51 tags `grid-cell` are the one exemption; everything else is held to 48.

import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:honest_sudoku/ui/a11y/labels.dart';

/// Tappable objects at least 48×48 dp, grid cells excepted.
class HonestTapTargetGuideline extends MinimumTapTargetGuideline {
  /// Creates the guideline.
  const HonestTapTargetGuideline()
    : super(
        size: const Size(48, 48),
        link: 'https://support.google.com/accessibility/android/answer/7101858?hl=en',
      );

  @override
  bool shouldSkipNode(SemanticsNode node) =>
      (node.tags?.contains(kGridCellTag) ?? false) ||
      super.shouldSkipNode(node);

  @override
  String get description =>
      'Tappable objects should be at least 48 by 48 dp, except grid cells';
}

/// The project guideline.
const AccessibilityGuideline honestTapTargetGuideline =
    HonestTapTargetGuideline();
