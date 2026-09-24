// Where the win card reads the current streak. An interface in the model so
// M4's statistics store implements it without touching the UI.

import 'package:honest_sudoku/engine/engine.dart';

/// Reads the player's statistics.
abstract interface class StatsSource {
  /// Solves in a row at [shape] and [difficulty], before the one just won.
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
