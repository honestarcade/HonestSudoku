// Grading: solve a board the way a person would, easiest technique first,
// and rate it by the hardest technique it needed.
//
// After every successful step the ladder restarts from the naked single, so
// the recorded hardest technique is the least the board requires. When
// nothing on the ladder applies the board is `beyond` (Evil): the solver
// records that and confirms by backtracking that a solution exists.

import 'candidate_grid.dart';
import 'difficulty.dart';
import 'grid.dart';
import 'solver.dart';
import 'techniques/hidden_single.dart';
import 'techniques/hidden_subset.dart';
import 'techniques/locked_candidates.dart';
import 'techniques/naked_single.dart';
import 'techniques/naked_subset.dart';
import 'techniques/technique.dart';
import 'techniques/x_wing.dart';

/// The ladder, easiest first.
const List<TechniqueRule> kLadder = [
  NakedSingle(),
  HiddenSingle(),
  Pointing(),
  Claiming(),
  NakedSubset.pair(),
  HiddenSubset.pair(),
  NakedSubset.triple(),
  HiddenSubset.triple(),
  XWing(),
];

/// A board's rating.
final class Grade {
  /// Creates a grade.
  const Grade(this.technique, this.steps);

  /// The hardest technique used. When grading stopped at a ceiling, the first
  /// technique above it that would have been tried: a lower bound.
  final Technique technique;

  /// Every step taken, in order.
  final List<Step> steps;

  /// The band [technique] belongs to.
  Difficulty get band => technique.band;

  @override
  String toString() => 'Grade(${technique.name}, ${band.label})';
}

/// A board a person could not solve: a clash, a dead cell, or no solution.
final class InvalidBoard implements Exception {
  /// Creates the exception.
  const InvalidBoard(this.shape, this.cell, this.reason);

  /// The board's shape.
  final GridShape shape;

  /// The cell at fault, or -1 when no single cell is.
  final int cell;

  /// What is wrong.
  final String reason;

  @override
  String toString() => 'InvalidBoard(${shape.label}, cell $cell): $reason';
}

/// Rates boards. [HumanSolver] is the real one; tests may substitute.
abstract interface class Grader {
  /// Grades [values]. With [ceiling], stops as soon as the board is known to
  /// need a harder band. [onStep] receives the share of cells filled after
  /// each step.
  Grade grade(
    GridShape shape,
    List<int> values, {
    Difficulty? ceiling,
    void Function(double filled)? onStep,
  });
}

/// The technique-ladder solver.
final class HumanSolver implements Grader {
  /// Creates the solver.
  const HumanSolver();

  @override
  Grade grade(
    GridShape shape,
    List<int> values, {
    Difficulty? ceiling,
    void Function(double filled)? onStep,
  }) {
    checkValues(shape, values);
    if (!isConsistent(shape, values)) {
      throw InvalidBoard(shape, -1, 'a unit holds the same value twice');
    }
    final grid = CandidateGrid(shape, values);
    final steps = <Step>[];
    var hardest = Technique.none;
    final total = shape.cellCount;
    var filled = values.where((v) => v != 0).length;

    while (!grid.isSolved) {
      for (var i = 0; i < total; i++) {
        if (grid.values[i] == 0 && grid.cands[i] == 0) {
          throw InvalidBoard(shape, i, 'no candidate is left');
        }
      }
      Step? step;
      for (final rule in kLadder) {
        if (ceiling != null && rule.technique.band.index > ceiling.index) {
          return Grade(rule.technique, steps);
        }
        step = rule.apply(grid);
        if (step != null) break;
      }
      if (step == null) {
        if (ceiling != null && Technique.beyond.band.index > ceiling.index) {
          return Grade(Technique.beyond, steps);
        }
        // Existence, not uniqueness: stopping at the first solution is what
        // keeps a sparse 16×16 cheap to grade, and the generator has already
        // proved uniqueness before it grades.
        if (countSolutions(shape, grid.values, limit: 1) == 0) {
          throw InvalidBoard(shape, -1, 'no solution');
        }
        hardest = Technique.beyond;
        onStep?.call(1.0);
        return Grade(hardest, steps);
      }
      steps.add(step);
      if (step.technique.index > hardest.index) hardest = step.technique;
      if (step.value != null) {
        filled++;
        onStep?.call(filled / total);
      }
    }
    return Grade(hardest, steps);
  }
}

/// Grades [values] with the real ladder.
Grade grade(GridShape shape, List<int> values) =>
    const HumanSolver().grade(shape, values);
