// A cell with one candidate left takes it. Cells are scanned in index order.

import '../candidate_grid.dart';
import 'technique.dart';

/// Naked single.
final class NakedSingle implements TechniqueRule {
  /// Creates the rule.
  const NakedSingle();

  @override
  Technique get technique => Technique.nakedSingle;

  @override
  Step? apply(CandidateGrid grid) {
    for (var i = 0; i < grid.cands.length; i++) {
      if (grid.values[i] == 0 && maskSize(grid.cands[i]) == 1) {
        final v = grid.cands[i].bitLength;
        grid.place(i, v);
        return Step(technique: technique, cells: [i], value: v);
      }
    }
    return null;
  }
}
