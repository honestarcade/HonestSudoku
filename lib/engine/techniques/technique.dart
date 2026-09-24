// The common interface every solving technique implements, and the record of
// one step it takes.

import '../candidate_grid.dart';
import '../difficulty.dart';

/// Every technique the grader knows, easiest first. `none` grades a board
/// that is already full; `beyond` means nothing on the ladder applied.
enum Technique {
  none,
  nakedSingle,
  hiddenSingle,
  pointing,
  claiming,
  nakedPair,
  hiddenPair,
  nakedTriple,
  hiddenTriple,
  xWing,
  beyond;

  /// The difficulty band a board needing this technique belongs to.
  Difficulty get band => switch (this) {
    none || nakedSingle || hiddenSingle => Difficulty.easy,
    pointing || claiming => Difficulty.medium,
    nakedPair || hiddenPair => Difficulty.hard,
    nakedTriple || hiddenTriple || xWing => Difficulty.expert,
    beyond => Difficulty.evil,
  };
}

/// One placement or one round of eliminations.
final class Step {
  /// Creates a step.
  const Step({
    required this.technique,
    required this.cells,
    this.value,
    this.eliminations = const [],
  });

  /// The technique that found it.
  final Technique technique;

  /// The cells the deduction rests on (the placed cell for a single).
  final List<int> cells;

  /// The value placed, for a single.
  final int? value;

  /// `(cell, value)` pairs removed from the candidates.
  final List<(int, int)> eliminations;

  @override
  String toString() =>
      'Step(${technique.name}, $cells'
      '${value == null ? '' : ' = $value'}, ${eliminations.length} removed)';
}

/// A solving technique: finds one deduction on [CandidateGrid] and applies
/// it, or returns null and leaves the grid untouched.
abstract interface class TechniqueRule {
  /// Which technique this is.
  Technique get technique;

  /// Applies one step, or returns null when this technique finds nothing.
  Step? apply(CandidateGrid grid);
}

/// Removes [mask] from each of [cells], collecting what was removed.
List<(int, int)> eliminateFrom(
  CandidateGrid grid,
  Iterable<int> cells,
  int mask,
) {
  final removed = <(int, int)>[];
  for (final c in cells) {
    final hit = grid.cands[c] & mask;
    if (hit == 0) continue;
    grid.cands[c] &= ~hit;
    for (final v in maskValues(hit)) {
      removed.add((c, v));
    }
  }
  return removed;
}
