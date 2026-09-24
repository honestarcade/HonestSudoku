// The human solver's working state: the values placed so far and, for every
// empty cell, a bitmask of the values it can still take (bit v-1 for v).

import 'grid.dart';
import 'solver.dart' show popcount16;
import 'units.dart';

/// Values and candidate masks, mutated as techniques place and eliminate.
final class CandidateGrid {
  /// Seeds the candidates from [values]: every value its peers do not hold.
  CandidateGrid(this.shape, List<int> values)
    : values = List<int>.of(values),
      cands = List<int>.filled(values.length, 0) {
    checkValues(shape, this.values);
    final tables = UnitTables.of(shape);
    final full = (1 << shape.n) - 1;
    for (var i = 0; i < this.values.length; i++) {
      if (this.values[i] != 0) continue;
      var used = 0;
      for (final p in tables.peers[i]) {
        final v = this.values[p];
        if (v != 0) used |= 1 << (v - 1);
      }
      cands[i] = full & ~used;
    }
  }

  /// A grid with candidates given explicitly, for tests that stage a state
  /// no board reaches by placement alone.
  CandidateGrid.seeded(this.shape, List<int> values, List<int> cands)
    : values = List<int>.of(values),
      cands = List<int>.of(cands) {
    checkValues(shape, this.values);
    if (this.cands.length != shape.cellCount) {
      throw ArgumentError.value(this.cands.length, 'cands', 'wrong length');
    }
  }

  /// The grid's shape.
  final GridShape shape;

  /// Placed values, 0 for empty.
  final List<int> values;

  /// Candidate mask per cell; 0 for a filled cell.
  final List<int> cands;

  /// Unit tables for [shape].
  UnitTables get tables => UnitTables.of(shape);

  /// True when every cell holds a value.
  bool get isSolved => !values.contains(0);

  /// The candidate values of [cell], ascending.
  List<int> candidatesOf(int cell) => maskValues(cands[cell]);

  /// Places [value] at [cell] and removes it from every peer's candidates.
  void place(int cell, int value) {
    final bit = 1 << (value - 1);
    values[cell] = value;
    cands[cell] = 0;
    for (final p in tables.peers[cell]) {
      cands[p] &= ~bit;
    }
  }

  /// Removes [mask]'s values from [cell]; true when anything was removed.
  bool eliminate(int cell, int mask) {
    final before = cands[cell];
    cands[cell] = before & ~mask;
    return cands[cell] != before;
  }
}

/// The values set in [mask], ascending.
List<int> maskValues(int mask) => [
  for (var v = 1; mask >> (v - 1) != 0; v++)
    if (mask & (1 << (v - 1)) != 0) v,
];

/// The number of values in [mask].
int maskSize(int mask) => popcount16(mask);
