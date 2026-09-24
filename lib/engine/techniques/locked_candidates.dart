// Locked candidates. Pointing: when a value's places in a box all lie on one
// row or column, the value leaves the rest of that line. Claiming: when a
// value's places in a row or column all lie in one box, the value leaves the
// rest of that box.

import '../candidate_grid.dart';
import '../units.dart';
import 'technique.dart';

List<int> _placesOf(CandidateGrid grid, Unit unit, int bit) => [
  for (final c in unit.cells)
    if (grid.cands[c] & bit != 0) c,
];

/// Pointing.
final class Pointing implements TechniqueRule {
  /// Creates the rule.
  const Pointing();

  @override
  Technique get technique => Technique.pointing;

  @override
  Step? apply(CandidateGrid grid) {
    final shape = grid.shape;
    final units = grid.tables.units;
    for (final box in units.where((u) => u.kind == UnitKind.box)) {
      for (var v = 1; v <= shape.n; v++) {
        final bit = 1 << (v - 1);
        final places = _placesOf(grid, box, bit);
        if (places.length < 2) continue;
        for (final kind in [UnitKind.row, UnitKind.column]) {
          final lineOf = kind == UnitKind.row ? shape.rowOf : shape.colOf;
          final line = lineOf(places.first);
          if (places.any((c) => lineOf(c) != line)) continue;
          final lineUnit = units[(kind == UnitKind.row ? 0 : shape.n) + line];
          final removed = eliminateFrom(
            grid,
            lineUnit.cells.where((c) => !box.cells.contains(c)),
            bit,
          );
          if (removed.isNotEmpty) {
            return Step(
              technique: technique,
              cells: places,
              eliminations: removed,
            );
          }
        }
      }
    }
    return null;
  }
}

/// Claiming (box/line reduction).
final class Claiming implements TechniqueRule {
  /// Creates the rule.
  const Claiming();

  @override
  Technique get technique => Technique.claiming;

  @override
  Step? apply(CandidateGrid grid) {
    final shape = grid.shape;
    final units = grid.tables.units;
    final boxBase = 2 * shape.n;
    for (final line in units.where((u) => u.kind != UnitKind.box)) {
      for (var v = 1; v <= shape.n; v++) {
        final bit = 1 << (v - 1);
        final places = _placesOf(grid, line, bit);
        if (places.length < 2) continue;
        final box = shape.boxOf(places.first);
        if (places.any((c) => shape.boxOf(c) != box)) continue;
        final removed = eliminateFrom(
          grid,
          units[boxBase + box].cells.where((c) => !line.cells.contains(c)),
          bit,
        );
        if (removed.isNotEmpty) {
          return Step(
            technique: technique,
            cells: places,
            eliminations: removed,
          );
        }
      }
    }
    return null;
  }
}
