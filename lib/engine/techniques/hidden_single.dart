// A value that fits only one cell of a unit goes there. Units are walked in
// the design's order, values ascending within each.

import '../candidate_grid.dart';
import 'technique.dart';

/// Hidden single.
final class HiddenSingle implements TechniqueRule {
  /// Creates the rule.
  const HiddenSingle();

  @override
  Technique get technique => Technique.hiddenSingle;

  @override
  Step? apply(CandidateGrid grid) {
    final n = grid.shape.n;
    for (final unit in grid.tables.units) {
      for (var v = 1; v <= n; v++) {
        final bit = 1 << (v - 1);
        var spot = -1;
        var count = 0;
        var placed = false;
        for (final c in unit.cells) {
          if (grid.values[c] == v) {
            placed = true;
            break;
          }
          if (grid.cands[c] & bit != 0) {
            count++;
            spot = c;
          }
        }
        if (!placed && count == 1) {
          grid.place(spot, v);
          return Step(technique: technique, cells: [spot], value: v);
        }
      }
    }
    return null;
  }
}
