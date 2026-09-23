// A backtracking solver that counts solutions.
//
// Each unit keeps a bitmask of the values placed in it, built from the unit
// tables in units.dart, so a cell's candidates are the complement of the
// union of its three units' masks. The search branches on the most
// constrained choice — the empty cell with the fewest candidates (lowest index
// on a tie, values ascending), or a unit's missing value with even fewer
// places to go — and stops as soon as `limit` solutions are found.

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
    final cells = grid.length;
    final n = shape.n;
    final units = UnitTables.of(shape).units;
    final free = List<int>.filled(cells, 0);
    final places = List<int>.filled(n, 0);
    var found = 0;

    void place(int cell, int bit) {
      final u = cellUnits[cell];
      grid[cell] = bit.bitLength;
      masks[u[0]] |= bit;
      masks[u[1]] |= bit;
      masks[u[2]] |= bit;
    }

    void unplace(int cell, int bit) {
      final u = cellUnits[cell];
      grid[cell] = 0;
      masks[u[0]] ^= bit;
      masks[u[1]] ^= bit;
      masks[u[2]] ^= bit;
    }

    bool recurse() {
      // The most-constrained cell.
      var bestCell = -1;
      var bestCount = 1 << 30;
      for (var i = 0; i < cells; i++) {
        if (grid[i] != 0) continue;
        final f = _free(i);
        free[i] = f;
        final c = _popcount[f];
        if (c == 0) return false;
        if (c < bestCount) {
          bestCell = i;
          bestCount = c;
        }
      }
      if (bestCell < 0) {
        found++;
        if (capture && found == 1) captured = List<int>.of(grid);
        return limit != null && found >= limit;
      }

      // The most-constrained (unit, value): a value missing from a unit must
      // go in one of the unit's cells that can take it. Branching on the
      // fewer of the two choices is what keeps sparse 16×16 boards tractable;
      // a missing value with no place left is a dead end.
      var bestUnit = -1;
      var bestBit = 0;
      if (bestCount > 1) {
        for (var u = 0; u < units.length; u++) {
          final missing = _full & ~masks[u];
          if (missing == 0) continue;
          for (var v = 0; v < n; v++) {
            places[v] = 0;
          }
          for (final c in units[u].cells) {
            if (grid[c] != 0) continue;
            var f = free[c];
            while (f != 0) {
              final bit = f & -f;
              f ^= bit;
              places[bit.bitLength - 1]++;
            }
          }
          var m = missing;
          while (m != 0) {
            final bit = m & -m;
            m ^= bit;
            final c = places[bit.bitLength - 1];
            if (c == 0) return false;
            if (c < bestCount) {
              bestCount = c;
              bestUnit = u;
              bestBit = bit;
            }
          }
          if (bestCount == 1) break;
        }
      }

      if (bestUnit >= 0) {
        final spots = [
          for (final c in units[bestUnit].cells)
            if (grid[c] == 0 && free[c] & bestBit != 0) c,
        ];
        for (final c in spots) {
          place(c, bestBit);
          final stop = recurse();
          unplace(c, bestBit);
          if (stop) return true;
        }
        return false;
      }

      var f = free[bestCell];
      while (f != 0) {
        final bit = f & -f;
        f ^= bit;
        place(bestCell, bit);
        final stop = recurse();
        unplace(bestCell, bit);
        if (stop) return true;
      }
      return false;
    }

    recurse();
    return found;
  }
}
