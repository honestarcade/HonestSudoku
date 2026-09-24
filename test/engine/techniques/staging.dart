// Staged candidate states for the technique tests: an empty 9×9 grid where
// every cell starts with every candidate, then has values removed so that
// exactly the deduction under test is available.

import 'package:honest_sudoku/engine/engine.dart';

/// Bit mask of [values].
int bits(Iterable<int> values) => values.fold(0, (m, v) => m | (1 << (v - 1)));

/// An empty [shape] grid with every candidate everywhere.
CandidateGrid openGrid([GridShape shape = GridShape.classic]) =>
    CandidateGrid.seeded(
      shape,
      List.filled(shape.cellCount, 0),
      List.filled(shape.cellCount, (1 << shape.n) - 1),
    );

/// Removes [values] from each of [cells].
void strip(CandidateGrid g, Iterable<int> cells, Iterable<int> values) {
  for (final c in cells) {
    g.cands[c] &= ~bits(values);
  }
}

/// Cell index on a 9×9 grid from 0-based row and column.
int rc(int r, int c) => r * 9 + c;

/// The rules easier than [t] on the ladder.
List<TechniqueRule> easierThan(Technique t) =>
    kLadder.takeWhile((rule) => rule.technique != t).toList();

/// True when no rule easier than [t] finds anything on a copy of [g].
bool easierFindNothing(CandidateGrid g, Technique t) => easierThan(t).every(
  (rule) =>
      rule.apply(CandidateGrid.seeded(g.shape, g.values, g.cands)) == null,
);
