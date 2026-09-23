// The win card's streak, read from the statistics the controller keeps.

import 'package:honest_sudoku/engine/engine.dart';

import 'stats_book.dart';
import 'stats_source.dart';

/// Reads streaks from the current [StatsBook].
final class RealStatsSource implements StatsSource {
  /// Creates the source; [book] is read on every call.
  const RealStatsSource(this.book);

  /// The current book.
  final StatsBook Function() book;

  @override
  int currentStreak({
    required GridShape shape,
    required Difficulty difficulty,
  }) => supportedDifficulties(shape).contains(difficulty)
      ? book().streak(difficulty)
      : 0;
}
