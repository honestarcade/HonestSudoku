// The easiest next step, as the design's `hint()` finds it: the first naked
// single in cell order, else the first hidden single walking the units in the
// design's order (values ascending in each), else the first empty cell with
// its solution value. Current entries count as placed, right or wrong.

import 'candidates.dart';
import 'grid.dart';
import 'strings.dart';
import 'units.dart';

/// A hint: the cell, its value and the sentence to show.
final class Hint {
  /// Creates a hint.
  const Hint({
    required this.kind,
    required this.cellIndex,
    required this.value,
    required this.unitName,
    required this.body,
  });

  /// Which rule found the cell.
  final HintKind kind;

  /// The cell the hint points at.
  final int cellIndex;

  /// The value the rule gives the cell (the solution's for a harder step).
  final int value;

  /// The unit a hidden single was found in, else null.
  final String? unitName;

  /// The sentence to show.
  final String body;

  /// The design's tag for [kind].
  String get tag => tagFor(kind);

  /// Hints always use the hint banner.
  BannerKind get banner => BannerKind.hint;

  @override
  bool operator ==(Object other) =>
      other is Hint &&
      other.kind == kind &&
      other.cellIndex == cellIndex &&
      other.value == value &&
      other.unitName == unitName &&
      other.body == body;

  @override
  int get hashCode => Object.hash(kind, cellIndex, value, unitName, body);

  @override
  String toString() => 'Hint($tag, $cellIndex = $value)';
}

/// The easiest next step on [values], or null when no cell is empty.
///
/// [explain] is the design's "Explain hints" setting: off, the singles say
/// only `Try R<r>C<c>.`; a harder step always explains.
Hint? nextHint(
  GridShape shape,
  List<int> values,
  List<int> solution, {
  bool explain = true,
}) {
  checkValues(shape, values);
  checkValues(shape, solution, 'solution');
  final cells = shape.cellCount;
  final table = List<List<int>?>.generate(
    cells,
    (i) => values[i] == 0 ? candidates(shape, values, i) : null,
  );

  for (var i = 0; i < cells; i++) {
    final c = table[i];
    if (c != null && c.length == 1) {
      final name = cellName(shape, i);
      return Hint(
        kind: HintKind.nakedSingle,
        cellIndex: i,
        value: c.single,
        unitName: null,
        body: explain
            ? nakedSingleBody(name, shape.symbolFor(c.single))
            : tryCellBody(name),
      );
    }
  }

  for (final unit in unitList(shape)) {
    for (var v = 1; v <= shape.n; v++) {
      if (unit.cells.any((i) => values[i] == v)) continue;
      final spots = [
        for (final i in unit.cells)
          if (table[i]?.contains(v) ?? false) i,
      ];
      if (spots.length == 1) {
        final i = spots.single;
        final name = cellName(shape, i);
        return Hint(
          kind: HintKind.hiddenSingle,
          cellIndex: i,
          value: v,
          unitName: unit.name,
          body: explain
              ? hiddenSingleBody(name, shape.symbolFor(v), unit.name)
              : tryCellBody(name),
        );
      }
    }
  }

  final empty = values.indexOf(0);
  if (empty < 0) return null;
  return Hint(
    kind: HintKind.harderStep,
    cellIndex: empty,
    value: solution[empty],
    unitName: null,
    body: harderStepBody(
      cellName(shape, empty),
      shape.symbolFor(solution[empty]),
    ),
  );
}
