// Where the win card reads the current streak. An interface in the model so
// M4's statistics store implements it without touching the UI.

import 'package:honest_sudoku/engine/engine.dart';

/// Reads the player's statistics.
abstract interface class StatsSource {
  /// The current streak at [difficulty] as recorded, so a win recorded
  /// before the call is already in it; 0 for a [shape] it does not support.
  int currentStreak({required GridShape shape, required Difficulty difficulty});
}

/// No statistics yet: every streak is 0.
final class NoStats implements StatsSource {
  /// Creates the stub.
  const NoStats();

  @override
  int currentStreak({
    required GridShape shape,
    required Difficulty difficulty,
  }) => 0;
}
