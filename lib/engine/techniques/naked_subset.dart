// Naked pairs and triples: k cells of one unit whose candidates together
// span exactly k values. Those values then leave every other cell of every
// unit the k cells share. A triple's cells may hold two or three of the
// values each.

import '../candidate_grid.dart';
import 'subsets.dart';
import 'technique.dart';

/// Naked pair (k = 2) or naked triple (k = 3).
final class NakedSubset implements TechniqueRule {
  /// A naked pair.
  const NakedSubset.pair() : size = 2;

  /// A naked triple.
  const NakedSubset.triple() : size = 3;

  /// Cells in the subset.
  final int size;

  @override
  Technique get technique =>
      size == 2 ? Technique.nakedPair : Technique.nakedTriple;

  @override
  Step? apply(CandidateGrid grid) {
    if (!subsetApplies(grid.shape.n, size)) return null;
    for (final unit in grid.tables.units) {
      final pool = [
        for (final c in unit.cells)
          if (grid.values[c] == 0 &&
              maskSize(grid.cands[c]) >= 2 &&
              maskSize(grid.cands[c]) <= size)
            c,
      ];
      for (final cells in combinations(pool, size)) {
        var union = 0;
        for (final c in cells) {
          union |= grid.cands[c];
        }
        if (maskSize(union) != size) continue;
        final removed = <(int, int)>[];
        for (final shared in sharedUnits(grid, cells)) {
          removed.addAll(
            eliminateFrom(
              grid,
              shared.cells.where((c) => !cells.contains(c)),
              union,
            ),
          );
        }
        if (removed.isNotEmpty) {
          return Step(
            technique: technique,
            cells: cells,
            eliminations: removed,
          );
        }
      }
    }
    return null;
  }
}
