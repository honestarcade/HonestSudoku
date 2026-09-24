// Hand-built puzzles for the game-model tests: the design's base pattern as
// the solution, givens on even indices, seed 1, Medium. Not generated, so a
// change to the generator cannot move them.

import 'package:honest_sudoku/engine/engine.dart';
import 'package:honest_sudoku/game/game.dart';

import '../engine/grid_strings.dart';

/// A puzzle on [shape] with givens on even indices.
Puzzle fixturePuzzle(
  GridShape shape, {
  Difficulty difficulty = Difficulty.medium,
  bool Function(int index)? given,
  int seed = 1,
}) {
  final isGiven = given ?? (int i) => i.isEven;
  final givens = [for (var i = 0; i < shape.cellCount; i++) isGiven(i)];
  return Puzzle(
    shape: shape,
    seed: seed,
    solution: basePattern(shape),
    givens: givens,
    givenCount: givens.where((g) => g).length,
    difficulty: difficulty,
    technique: Technique.nakedSingle,
    attempts: 1,
  );
}

/// 4×4 fixture.
final Puzzle mini = fixturePuzzle(GridShape.mini);

/// 9×9 fixture.
final Puzzle classic = fixturePuzzle(GridShape.classic);

/// 16×16 fixture, for the renderer.
final Puzzle monster = fixturePuzzle(GridShape.monster);

/// A value for [cell] of [p] that is not its solution.
int wrongValue(Puzzle p, int cell) => p.solution[cell] % p.shape.n + 1;

/// The design's Easy statistics (STATS.easy): 66 started, 64 solved, best
/// 2:14, average 4:38, streak 12, 5h 06m played — all on 9×9, the other
/// difficulties empty.
final StatsBook sampleStatsBook = StatsBook(
  shapes: {
    (Difficulty.easy, GridShape.classic): ShapeStats(
      started: 66,
      solved: 64,
      bestSeconds: 134,
      solvedSecondsTotal: 17792,
      timePlayedSeconds: 18360,
    ),
  },
  streaks: {Difficulty.easy: 12},
);
