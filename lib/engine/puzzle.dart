// A generated board: its full solution and which cells are given.

import 'difficulty.dart';
import 'grid.dart';
import 'list_equality.dart';
import 'techniques/technique.dart';

/// A generated puzzle.
final class Puzzle {
  /// Creates a puzzle, validating the lists against [shape].
  Puzzle({
    required this.shape,
    required this.seed,
    required List<int> solution,
    required List<bool> givens,
    required this.givenCount,
    this.difficulty,
    this.technique,
    this.attempts,
  }) : solution = List.unmodifiable(solution),
       givens = List.unmodifiable(givens) {
    checkValues(shape, this.solution, 'solution');
    if (this.solution.contains(0)) {
      throw ArgumentError('solution must be full');
    }
    if (this.givens.length != shape.cellCount) {
      throw ArgumentError.value(
        this.givens.length,
        'givens',
        'length must be ${shape.cellCount}',
      );
    }
    final counted = this.givens.where((g) => g).length;
    if (counted != givenCount) {
      throw ArgumentError.value(givenCount, 'givenCount', 'mask has $counted');
    }
  }

  /// The grid's shape.
  final GridShape shape;

  /// The seed the caller asked for, before masking.
  final int seed;

  /// The full solution, row-major, unmodifiable.
  final List<int> solution;

  /// Which cells are given, unmodifiable.
  final List<bool> givens;

  /// How many cells are given.
  final int givenCount;

  /// The band the board was generated and graded to; null for an ungraded
  /// carve.
  final Difficulty? difficulty;

  /// The hardest technique the board needs; null for an ungraded carve.
  final Technique? technique;

  /// Which attempt produced the board, 1-based; null for an ungraded carve.
  final int? attempts;

  /// The board the player starts from: givens filled, the rest 0. A fresh
  /// mutable list on every call.
  List<int> startingValues() => [
    for (var i = 0; i < solution.length; i++) givens[i] ? solution[i] : 0,
  ];

  @override
  bool operator ==(Object other) =>
      other is Puzzle &&
      other.shape == shape &&
      other.seed == seed &&
      other.givenCount == givenCount &&
      other.difficulty == difficulty &&
      other.technique == technique &&
      other.attempts == attempts &&
      listEquals(other.solution, solution) &&
      listEquals(other.givens, givens);

  @override
  int get hashCode => Object.hash(
    shape,
    seed,
    givenCount,
    difficulty,
    technique,
    attempts,
    Object.hashAll(solution),
    Object.hashAll(givens),
  );

  @override
  String toString() => 'Puzzle(${shape.label}, seed $seed, $givenCount givens)';
}
