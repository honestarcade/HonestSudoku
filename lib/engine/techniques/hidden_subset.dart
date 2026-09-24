// Hidden pairs and triples: k values that, within one unit, fit only the same
// k cells. Those cells then lose every other candidate. A triple's values may
// each fit two or three of the cells.

import '../candidate_grid.dart';
import 'subsets.dart';
import 'technique.dart';

/// Hidden pair (k = 2) or hidden triple (k = 3).
final class HiddenSubset implements TechniqueRule {
  /// A hidden pair.
  const HiddenSubset.pair() : size = 2;

  /// A hidden triple.
  const HiddenSubset.triple() : size = 3;

  /// Values in the subset.
  final int size;

  @override
  Technique get technique =>
      size == 2 ? Technique.hiddenPair : Technique.hiddenTriple;

  @override
  Step? apply(CandidateGrid grid) {
    final n = grid.shape.n;
    if (!subsetApplies(n, size)) return null;
    for (final unit in grid.tables.units) {
      // Where each missing value fits, as a bitmask over the unit's cells.
      final spots = <int, int>{};
      for (var v = 1; v <= n; v++) {
        final bit = 1 << (v - 1);
        if (unit.cells.any((c) => grid.values[c] == v)) continue;
        var where = 0;
        for (var k = 0; k < unit.cells.length; k++) {
          if (grid.cands[unit.cells[k]] & bit != 0) where |= 1 << k;
        }
        final count = maskSize(where);
        if (count >= 2 && count <= size) spots[v] = where;
      }
      for (final values in combinations(spots.keys.toList(), size)) {
        var where = 0;
        var keep = 0;
        for (final v in values) {
          where |= spots[v]!;
          keep |= 1 << (v - 1);
        }
        if (maskSize(where) != size) continue;
        final cells = [
          for (var k = 0; k < unit.cells.length; k++)
            if (where & (1 << k) != 0) unit.cells[k],
        ];
        final removed = eliminateFrom(grid, cells, ~keep & ((1 << n) - 1));
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
