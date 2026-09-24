// Candidate values for a cell, as the prototype's `candidates()` computes
// them: every value 1..n not already present among the cell's peers. Current
// entries count as placed whether given or entered, right or wrong.

import 'grid.dart';
import 'units.dart';

/// The ascending values `1..n` absent from [index]'s peers in [values].
///
/// The cell's own entry is ignored, as in the prototype.
List<int> candidates(GridShape shape, List<int> values, int index) {
  checkValues(shape, values);
  checkIndex(shape, index);
  final used = List<bool>.filled(shape.n + 1, false);
  for (final peer in UnitTables.of(shape).peers[index]) {
    used[values[peer]] = true;
  }
  return [
    for (var v = 1; v <= shape.n; v++)
      if (!used[v]) v,
  ];
}
