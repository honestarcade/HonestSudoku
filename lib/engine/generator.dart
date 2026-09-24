// Board generation: a seeded full grid, then givens carved away while the
// solution stays unique — to the uniqueness limit, or toward a requested
// difficulty band.
//
// Progress runs 0.0 → 0.45 while the full grid is built, 0.45 → 0.85 while
// carving and 0.85 → 1.0 while grading. Those are the loading screen's label
// thresholds: GENERATING below 45 %, CARVING GIVENS below 85 %, READY above.

import 'difficulty.dart';
import 'full_grid.dart';
import 'grid.dart';
import 'human_solver.dart';
import 'puzzle.dart';
import 'rng.dart';
import 'solver.dart';

/// Where carving starts on the progress scale.
const double kProgressCarving = 0.45;

/// Where grading starts on the progress scale.
const double kProgressGrading = 0.85;

/// Receives progress in `[0, 1]`, non-decreasing.
typedef ProgressCallback = void Function(double fraction);

/// Counts solutions up to two; [countSolutions] is the real one.
typedef SolutionCounter = int Function(GridShape shape, List<int> values);

int _countTwo(GridShape shape, List<int> values) =>
    countSolutions(shape, values);

/// The design's givens floor, `n + floor(n / 2)`.
int givensFloor(GridShape shape) => shape.n + shape.n ~/ 2;

/// Attempts a difficulty-targeted generation may make.
///
/// Sized to the rarest band each shape offers so that running out is
/// vanishingly unlikely. The success rates and per-attempt costs behind the
/// numbers are in the decision log (local probe, 2026-09-23). On 16×16 the
/// off-thread wrapper's time ceiling ends a slow request long before 200.
int defaultMaxAttempts(GridShape shape) => switch (shape.n) {
  4 => 50,
  6 => 10000,
  9 => 2000,
  _ => 200,
};

/// Whether a generated board may end at most `ceil(target × 1.1)` givens.
///
/// Not for Evil, which takes whatever count uniqueness allows, and not for
/// 16×16 Expert: the design's target there lies below where uniqueness and
/// the ladder let a 16×16 carve stop (87–96 givens over 60 attempts, local
/// probe, 2026-09-23, in the decision log), so the ceiling would discard
/// nearly every Expert board the carve finds.
bool countCeilingApplies(GridShape shape, Difficulty difficulty) =>
    difficulty != Difficulty.evil &&
    !(shape.n == 16 && difficulty == Difficulty.expert);

/// Generates boards.
final class Generator {
  /// Creates a generator. The parameters replace the real grader, solution
  /// counter and attempt limit, for tests.
  const Generator({this.grader, this.solutionCounter, this.maxAttempts});

  /// Replaces [HumanSolver].
  final Grader? grader;

  /// Replaces [countSolutions].
  final SolutionCounter? solutionCounter;

  /// Replaces [defaultMaxAttempts] for every shape.
  final int? maxAttempts;

  SolutionCounter get _counter => solutionCounter ?? _countTwo;

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
      counter: _counter,
      onTick: onProgress == null
          ? null
          : (visited) => onProgress(
              visited == order.length
                  ? kProgressGrading
                  : kProgressCarving +
                        (kProgressGrading - kProgressCarving) *
                            visited /
                            order.length,
            ),
    );
    if (_counter(shape, values) != 1) {
      throw StateError('carving produced a board without a unique solution');
    }
    final puzzle = _puzzle(shape, seed, solution, values);
    onProgress?.call(1.0);
    return puzzle;
  }

  /// A unique board for [shape] from [seed] whose grade is [difficulty].
  ///
  /// Carves toward [targetGivens], never below the floor. A removal is
  /// reverted if it breaks uniqueness or raises the band above the request.
  /// Carving stops once the count is at the target and the band is the
  /// request; below the target it goes on until the band is reached. An
  /// attempt that cannot reach the band, or (Easy–Expert) ends above
  /// `ceil(target × 1.1)`, is discarded and a new carve order is drawn from
  /// the same stream, so the result stays deterministic. Evil carves to the
  /// uniqueness limit and keeps the board only if it grades Evil.
  ///
  /// Throws [UnsupportedDifficulty] before any work for a pair the design
  /// does not offer, and [GenerationFailed] when every attempt is spent.
  Puzzle generate(
    GridShape shape,
    int seed,
    Difficulty difficulty, {
    ProgressCallback? onProgress,
  }) {
    if (!supportedDifficulties(shape).contains(difficulty)) {
      throw UnsupportedDifficulty(shape, difficulty, seed);
    }
    final grader = this.grader ?? const HumanSolver();
    var reported = -1.0;
    void report(double f) {
      if (f > reported) {
        reported = f;
        onProgress?.call(f);
      }
    }

    report(0.0);
    final rng = Rng(seed);
    final solution = fullGrid(shape, rng);
    report(kProgressCarving);

    final total = shape.cellCount;
    final attempts = maxAttempts ?? defaultMaxAttempts(shape);
    final target = targetGivens(shape, difficulty);
    final ceilingCount = countCeilingApplies(shape, difficulty)
        ? ((target * 1.1).ceil() > target ? (target * 1.1).ceil() : target + 1)
        : total;
    final floor = givensFloor(shape);
    const span = kProgressGrading - kProgressCarving;

    for (var attempt = 1; attempt <= attempts; attempt++) {
      final order = rng.shuffle(List<int>.generate(total, (i) => i));
      // Each attempt takes half of the carving span still unused, so the bar
      // keeps moving however many attempts a rare band needs.
      final used = 1 - 1 / (1 << (attempt - 1 > 50 ? 50 : attempt - 1));
      final start = kProgressCarving + span * used;
      final width = span * (1 - used) / 2;
      void tick(int visited) => report(start + width * visited / total);

      List<int>? values;
      if (difficulty == Difficulty.evil) {
        values = carve(
          shape,
          solution,
          order,
          floor: floor,
          counter: _counter,
          onTick: tick,
        );
        if (grader.grade(shape, values).band != Difficulty.evil) {
          values = null;
        }
      } else {
        values = _carveToBand(
          shape,
          solution,
          order,
          difficulty: difficulty,
          grader: grader,
          target: target,
          ceilingCount: ceilingCount,
          floor: floor,
          onTick: tick,
        );
      }
      if (values == null) continue;
      if (_counter(shape, values) != 1) {
        throw StateError('carving produced a board without a unique solution');
      }

      report(kProgressGrading);
      final g = grader.grade(
        shape,
        values,
        onStep: (filled) =>
            report(kProgressGrading + (1.0 - kProgressGrading) * filled),
      );
      if (g.band != difficulty) continue;
      final puzzle = _puzzle(
        shape,
        seed,
        solution,
        values,
        difficulty: difficulty,
        grade: g,
        attempt: attempt,
      );
      report(1.0);
      return puzzle;
    }
    throw GenerationFailed(shape, difficulty, seed, attempts);
  }

  List<int>? _carveToBand(
    GridShape shape,
    List<int> solution,
    List<int> order, {
    required Difficulty difficulty,
    required Grader grader,
    required int target,
    required int ceilingCount,
    required int floor,
    required void Function(int) onTick,
  }) {
    final ladderProvesUniqueness = this.grader == null;
    final values = List<int>.of(solution);
    var given = values.length;
    var band = Difficulty.easy;
    for (var k = 0; k < order.length; k++) {
      if (given <= target && band == difficulty) break;
      final cell = order[k];
      if (given > floor) {
        values[cell] = 0;
        // Grade instead of counting. The ladder only makes forced
        // deductions, so a board it finishes within the band has exactly one
        // solution, and a board with two leaves it stuck, which reads as
        // "too hard" and is reverted anyway: the decisions are the ones a
        // uniqueness count would make, and counting was the expensive half on
        // a sparse 16×16 (decision log, 2026-09-23). A substituted grader
        // proves nothing, so then the count still runs; and every finished
        // board is counted once in `generate`.
        final g = grader.grade(shape, values, ceiling: difficulty);
        if (g.band.index > difficulty.index ||
            (!ladderProvesUniqueness && _counter(shape, values) != 1)) {
          values[cell] = solution[cell];
        } else {
          given--;
          band = g.band;
        }
      }
      onTick(k + 1);
    }
    onTick(order.length);
    if (band != difficulty || given > ceilingCount) return null;
    return values;
  }

  /// Empties the cells of [order] one by one from a copy of [solution],
  /// keeping each removal only while the board stays unique and more than
  /// [floor] givens remain. [onTick] gets the count of cells visited after
  /// each one.
  static List<int> carve(
    GridShape shape,
    List<int> solution,
    List<int> order, {
    required int floor,
    SolutionCounter counter = _countTwo,
    void Function(int visited)? onTick,
  }) {
    final values = List<int>.of(solution);
    var given = values.length;
    for (var k = 0; k < order.length; k++) {
      final cell = order[k];
      if (given > floor) {
        values[cell] = 0;
        if (counter(shape, values) == 1) {
          given--;
        } else {
          values[cell] = solution[cell];
        }
      }
      onTick?.call(k + 1);
    }
    return values;
  }

  static Puzzle _puzzle(
    GridShape shape,
    int seed,
    List<int> solution,
    List<int> values, {
    Difficulty? difficulty,
    Grade? grade,
    int? attempt,
  }) {
    final givens = [for (final v in values) v != 0];
    return Puzzle(
      shape: shape,
      seed: seed,
      solution: solution,
      givens: givens,
      givenCount: givens.where((g) => g).length,
      difficulty: difficulty,
      technique: grade?.technique,
      attempts: attempt,
    );
  }
}
