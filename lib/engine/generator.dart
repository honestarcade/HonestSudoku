// Board generation: a seeded full grid, then givens carved away while the
// solution stays unique.
//
// Progress runs 0.0 → 0.45 while the full grid is built, 0.45 → 0.85 while
// carving and 0.85 → 1.0 while grading. Those are the loading screen's label
// thresholds: GENERATING below 45 %, CARVING GIVENS below 85 %, READY above.

import 'full_grid.dart';
import 'grid.dart';
import 'puzzle.dart';
import 'rng.dart';
import 'solver.dart';

/// Where carving starts on the progress scale.
const double kProgressCarving = 0.45;

/// Where grading starts on the progress scale.
const double kProgressGrading = 0.85;

/// Receives progress in `[0, 1]`, non-decreasing.
typedef ProgressCallback = void Function(double fraction);

/// The design's givens floor, `n + floor(n / 2)`.
int givensFloor(GridShape shape) => shape.n + shape.n ~/ 2;

/// Generates boards.
final class Generator {
  /// Creates a generator.
  const Generator();

  /// A unique board for [shape] from [seed], with as many givens removed as
  /// uniqueness and the floor allow.
  ///
  /// Cells are visited in one seeded shuffled order; each is emptied only if
  /// the board still has exactly one solution. [onProgress] gets `0.0`,
  /// `0.45`, one tick per visited cell up to `0.85`, then `1.0`.
  Puzzle carveToUniqueness(
    GridShape shape,
    int seed, {
    ProgressCallback? onProgress,
  }) {
    onProgress?.call(0.0);
    final rng = Rng(seed);
    final solution = fullGrid(shape, rng);
    onProgress?.call(kProgressCarving);
    final order = rng.shuffle(List<int>.generate(shape.cellCount, (i) => i));
    final values = carve(
      shape,
      solution,
      order,
      floor: givensFloor(shape),
      onTick: onProgress == null
          ? null
          : (visited) => onProgress(_carvingProgress(visited, order.length)),
    );
    final puzzle = _toPuzzle(shape, seed, solution, values);
    onProgress?.call(1.0);
    return puzzle;
  }

  /// Empties the cells of [order] one by one from a copy of [solution],
  /// keeping each removal only while the board stays unique and more than
  /// [floor] givens remain. [accept], when given, can refuse a removal the
  /// board otherwise allows. [onTick] gets the count of cells visited after
  /// each one.
  static List<int> carve(
    GridShape shape,
    List<int> solution,
    List<int> order, {
    required int floor,
    bool Function(List<int> values)? accept,
    void Function(int visited)? onTick,
  }) {
    final values = List<int>.of(solution);
    var given = values.length;
    for (var k = 0; k < order.length; k++) {
      final cell = order[k];
      if (given > floor) {
        values[cell] = 0;
        if (countSolutions(shape, values) == 1 &&
            (accept == null || accept(values))) {
          given--;
        } else {
          values[cell] = solution[cell];
        }
      }
      onTick?.call(k + 1);
    }
    return values;
  }

  static double _carvingProgress(int visited, int total) => visited == total
      ? kProgressGrading
      : kProgressCarving +
            (kProgressGrading - kProgressCarving) * visited / total;

  static Puzzle _toPuzzle(
    GridShape shape,
    int seed,
    List<int> solution,
    List<int> values,
  ) {
    if (countSolutions(shape, values) != 1) {
      throw StateError('carving produced a board without a unique solution');
    }
    final givens = [for (final v in values) v != 0];
    return Puzzle(
      shape: shape,
      seed: seed,
      solution: solution,
      givens: givens,
      givenCount: givens.where((g) => g).length,
    );
  }
}
