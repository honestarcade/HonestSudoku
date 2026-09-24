// Shared helpers for the subset techniques.

import '../candidate_grid.dart';
import '../units.dart';

/// Every ascending [k]-combination of [items].
Iterable<List<T>> combinations<T>(List<T> items, int k) sync* {
  final idx = List<int>.generate(k, (i) => i);
  if (k > items.length || k <= 0) return;
  while (true) {
    yield [for (final i in idx) items[i]];
    var i = k - 1;
    while (i >= 0 && idx[i] == items.length - k + i) {
      i--;
    }
    if (i < 0) return;
    idx[i]++;
    for (var j = i + 1; j < k; j++) {
      idx[j] = idx[j - 1] + 1;
    }
  }
}

/// Every unit that contains all of [cells].
Iterable<Unit> sharedUnits(CandidateGrid grid, List<int> cells) {
  final tables = grid.tables;
  return tables.unitsOfCell[cells.first]
      .where((u) => cells.every((c) => tables.unitsOfCell[c].contains(u)))
      .map((u) => tables.units[u]);
}

/// True when a subset of [size] is meaningful for [n]-cell units: a subset
/// covering all but one cell is just a single seen the long way round.
bool subsetApplies(int n, int size) => size < n - 1;
