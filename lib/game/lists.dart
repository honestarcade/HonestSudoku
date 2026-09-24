// Equality and hashing for the model's nested lists.

import 'package:honest_sudoku/engine/engine.dart';

/// True when [a] and [b] hold equal lists in the same order.
bool deepListEquals<T>(List<List<T>> a, List<List<T>> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (!listEquals(a[i], b[i])) return false;
  }
  return true;
}

/// A hash over [lists] and their contents.
int deepListHash<T>(List<List<T>> lists) =>
    Object.hashAll(lists.map(Object.hashAll));
