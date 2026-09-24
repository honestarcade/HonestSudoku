// The Check tool: which entries are wrong and how many cells remain, as the
// design's `check()` counts them. Wrong means non-empty and different from
// the solution.

import 'grid.dart';
import 'list_equality.dart';
import 'strings.dart';

/// Checks [values] against [solution].
CheckResult check(GridShape shape, List<int> values, List<int> solution) {
  checkValues(shape, values);
  checkValues(shape, solution, 'solution');
  final wrong = <int>[];
  var remaining = 0;
  for (var i = 0; i < values.length; i++) {
    if (values[i] == 0) {
      remaining++;
    } else if (values[i] != solution[i]) {
      wrong.add(i);
    }
  }
  return CheckResult(
    wrongCells: wrong,
    remaining: remaining,
    isFull: remaining == 0,
  );
}

/// What the Check tool reports.
final class CheckResult {
  /// Creates a result.
  CheckResult({
    required List<int> wrongCells,
    required this.remaining,
    required this.isFull,
  }) : wrongCells = List.unmodifiable(wrongCells);

  /// Non-empty cells whose value differs from the solution, ascending.
  final List<int> wrongCells;

  /// Empty cells.
  final int remaining;

  /// True when no cell is empty.
  final bool isFull;

  /// True when nothing on the board is wrong.
  bool get isClean => wrongCells.isEmpty;

  /// The design's tag.
  String get tag => kTagCheck;

  /// `ok` when clean, else `error`.
  BannerKind get banner => isClean ? BannerKind.ok : BannerKind.error;

  /// The sentence to show.
  String get body =>
      isClean ? checkCleanBody(remaining) : checkWrongBody(wrongCells.length);

  @override
  bool operator ==(Object other) =>
      other is CheckResult &&
      other.remaining == remaining &&
      other.isFull == isFull &&
      listEquals(other.wrongCells, wrongCells);

  @override
  int get hashCode =>
      Object.hash(remaining, isFull, Object.hashAll(wrongCells));

  @override
  String toString() =>
      'CheckResult(${wrongCells.length} wrong, $remaining to go)';
}
