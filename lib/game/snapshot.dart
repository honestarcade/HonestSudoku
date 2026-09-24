// One step of undo history: what a verb is about to change.

import 'package:honest_sudoku/engine/engine.dart';

import 'lists.dart';

/// The values, notes and counters before a change.
final class Snapshot {
  /// Creates a snapshot. The lists are the state's own immutable lists.
  const Snapshot(this.values, this.notes, this.mistakes, this.moves);

  /// Entries.
  final List<int> values;

  /// Pencil marks.
  final List<List<int>> notes;

  /// Mistakes counted.
  final int mistakes;

  /// Values placed.
  final int moves;

  @override
  bool operator ==(Object other) =>
      other is Snapshot &&
      other.mistakes == mistakes &&
      other.moves == moves &&
      listEquals(other.values, values) &&
      deepListEquals(other.notes, notes);

  @override
  int get hashCode =>
      Object.hash(mistakes, moves, Object.hashAll(values), deepListHash(notes));
}
