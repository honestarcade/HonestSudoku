// X-wing: when a value fits exactly two cells in each of two rows, and those
// cells share their two columns, the value leaves the rest of both columns
// (and the same with rows and columns swapped). Needs n >= 6: on 4×4 the
// pattern is always a pair of boxes seen by simpler techniques.

import '../candidate_grid.dart';
import 'technique.dart';

/// X-wing.
final class XWing implements TechniqueRule {
  /// Creates the rule.
  const XWing();

  @override
  Technique get technique => Technique.xWing;

  @override
  Step? apply(CandidateGrid grid) {
    final n = grid.shape.n;
    if (n < 6) return null;
    for (var v = 1; v <= n; v++) {
      final bit = 1 << (v - 1);
      for (final byRow in [true, false]) {
        int cell(int line, int pos) => byRow ? line * n + pos : pos * n + line;
        final lines = <int, int>{}; // line -> mask of positions
        for (var line = 0; line < n; line++) {
          var where = 0;
          for (var pos = 0; pos < n; pos++) {
            if (grid.cands[cell(line, pos)] & bit != 0) where |= 1 << pos;
          }
          if (maskSize(where) == 2) lines[line] = where;
        }
        final keys = lines.keys.toList();
        for (var a = 0; a < keys.length; a++) {
          for (var b = a + 1; b < keys.length; b++) {
            if (lines[keys[a]] != lines[keys[b]]) continue;
            final positions = maskValues(lines[keys[a]]!).map((p) => p - 1);
            final removed = eliminateFrom(grid, [
              for (final pos in positions)
                for (var line = 0; line < n; line++)
                  if (line != keys[a] && line != keys[b]) cell(line, pos),
            ], bit);
            if (removed.isNotEmpty) {
              return Step(
                technique: technique,
                cells: [
                  for (final line in [keys[a], keys[b]])
                    for (final pos in positions) cell(line, pos),
                ],
                eliminations: removed,
              );
            }
          }
        }
      }
    }
    return null;
  }
}
