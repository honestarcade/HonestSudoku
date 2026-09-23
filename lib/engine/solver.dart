// A backtracking solver that counts solutions.
//
// Each unit keeps a bitmask of the values placed in it, built from the unit
// tables in units.dart, so a cell's candidates are the complement of the
// union of its three units' masks. The search picks the most-constrained empty
// cell (lowest index on a tie), tries values in ascending order, and stops as
// soon as `limit` solutions are found.

import 'dart:typed_data';

import 'grid.dart';
import 'units.dart';

/// Bit counts for every 16-bit mask.
final Uint8List _popcount = () {
  final t = Uint8List(1 << 16);
  for (var i = 1; i < t.length; i++) {
    t[i] = t[i >> 1] + (i & 1);
  }
  return t;
}();

/// The number of set bits in a 16-bit [mask].
int popcount16(int mask) => _popcount[mask];

/// True when no unit of [values] holds the same non-zero value twice.
bool isConsistent(GridShape shape, List<int> values) {
  checkValues(shape, values);
  return _Search.tryCreate(shape, values) != null;
}

/// Counts the solutions of [values], stopping at [limit].
///
/// `limit: null` counts every solution. A grid whose givens already clash
/// counts 0. The input is not modified.
int countSolutions(GridShape shape, List<int> values, {int? limit = 2}) {
  if (limit != null && limit <= 0) {
    throw ArgumentError.value(limit, 'limit', 'must be positive or null');
  }
  checkValues(shape, values);
  final search = _Search.tryCreate(shape, values);
  if (search == null) return 0;
  return search.count(limit);
}

/// The unique solution of [values] as a new list, or null when it has none or
/// more than one.
List<int>? solve(GridShape shape, List<int> values) {
  checkValues(shape, values);
  final search = _Search.tryCreate(shape, values);
  if (search == null) return null;
  final found = search.count(2, capture: true);
  return found == 1 ? search.captured : null;
}

final class _Search {
  _Search._(this.shape, this.grid, this.masks, this.cellUnits);

  final GridShape shape;
  final List<int> grid;
  final List<int> masks;
  final List<List<int>> cellUnits;
  List<int>? captured;

  static _Search? tryCreate(GridShape shape, List<int> values) {
    final tables = UnitTables.of(shape);
    final masks = List<int>.filled(tables.units.length, 0);
    final grid = List<int>.of(values);
    for (var i = 0; i < grid.length; i++) {
      final v = grid[i];
      if (v == 0) continue;
      final bit = 1 << (v - 1);
      for (final u in tables.unitsOfCell[i]) {
        if (masks[u] & bit != 0) return null;
        masks[u] |= bit;
      }
    }
    return _Search._(shape, grid, masks, tables.unitsOfCell);
  }

  int get _full => (1 << shape.n) - 1;

  int _free(int i) {
    final u = cellUnits[i];
    return _full & ~(masks[u[0]] | masks[u[1]] | masks[u[2]]);
  }

  int count(int? limit, {bool capture = false}) {
    var found = 0;

    bool recurse() {
      var best = -1;
      var bestFree = 0;
      var bestCount = 1 << 30;
      for (var i = 0; i < grid.length; i++) {
        if (grid[i] != 0) continue;
        final free = _free(i);
        final c = _popcount[free];
        if (c == 0) return false;
        if (c < bestCount) {
          best = i;
          bestFree = free;
          bestCount = c;
          if (c == 1) break;
        }
      }
      if (best < 0) {
        found++;
        if (capture && found == 1) captured = List<int>.of(grid);
        return limit != null && found >= limit;
      }
      final units = cellUnits[best];
      var free = bestFree;
      while (free != 0) {
        final bit = free & -free;
        free ^= bit;
        grid[best] = bit.bitLength;
        masks[units[0]] |= bit;
        masks[units[1]] |= bit;
        masks[units[2]] |= bit;
        final stop = recurse();
        masks[units[0]] ^= bit;
        masks[units[1]] ^= bit;
        masks[units[2]] ^= bit;
        grid[best] = 0;
        if (stop) return true;
      }
      return false;
    }

    recurse();
    return found;
  }
}
