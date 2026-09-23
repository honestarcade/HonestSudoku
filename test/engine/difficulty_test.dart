import 'package:flutter_test/flutter_test.dart';
import 'package:honest_sudoku/engine/engine.dart';

void main() {
  test('the five bands carry the design DIFFS keys, labels, descriptions '
      'and keep ratios', () {
    expect(
      [
        for (final d in Difficulty.values)
          [d.key, d.label, d.description, d.keep],
      ],
      [
        [
          'easy',
          'Easy',
          'Every step is a plain single. A calm ten minutes.',
          0.55,
        ],
        [
          'medium',
          'Medium',
          'Scanning rows and boxes carries you through.',
          0.46,
        ],
        ['hard', 'Hard', 'Pencil marks start earning their keep.', 0.38],
        ['expert', 'Expert', 'Pairs, triples and a lot of patience.', 0.31],
        ['evil', 'Evil', 'Chains and long deductions. Bring notes.', 0.25],
      ],
    );
    expect(Difficulty.byKey('hard'), Difficulty.hard);
    expect(() => Difficulty.byKey('nightmare'), throwsArgumentError);
  });

  test('9×9 target givens are 45, 37, 31, 25, 20', () {
    expect(
      [for (final d in Difficulty.values) targetGivens(GridShape.classic, d)],
      [45, 37, 31, 25, 20],
    );
  });

  test('targets never fall below the n + n/2 floor', () {
    // 4×4 Evil's ratio target would be 4; the floor is 6.
    expect(targetGivens(GridShape.mini, Difficulty.evil), 6);
    expect(targetGivens(GridShape.monster, Difficulty.easy), 141);
  });

  test('supported pairs: 4×4 Easy only, 6×6 up to Hard, 9×9 and 16×16 all', () {
    expect(supportedDifficulties(GridShape.mini), [Difficulty.easy]);
    expect(supportedDifficulties(GridShape.short), [
      Difficulty.easy,
      Difficulty.medium,
      Difficulty.hard,
    ]);
    expect(supportedDifficulties(GridShape.classic), Difficulty.values);
    expect(supportedDifficulties(GridShape.monster), Difficulty.values);
  });

  // The evidence for the narrower table. The design's breakdown shows 4×4
  // Medium and Hard and 6×6 Expert; the grader cannot prove any of them.

  test('evidence: every unique 4×4 board at or above the floor falls to '
      'naked singles', () {
    // One full grid, every subset of at least six givens. The decision log
    // (2026-09-23) records the same result over all 288 4×4 grids,
    // 13 269 792 unique boards, from a local probe too slow for the gate.
    const s = GridShape.mini;
    final solution = fullGrid(s, Rng(1));
    var unique = 0;
    for (var mask = 0; mask < 1 << 16; mask++) {
      var k = 0;
      for (var m = mask; m != 0; m >>= 1) {
        k += m & 1;
      }
      if (k < 6) continue;
      final values = [
        for (var i = 0; i < 16; i++) (mask >> i) & 1 == 1 ? solution[i] : 0,
      ];
      if (countSolutions(s, values) != 1) continue;
      unique++;
      expect(
        grade(s, values).technique.index,
        lessThanOrEqualTo(Technique.nakedSingle.index),
      );
    }
    expect(unique, greaterThan(40000));
  });

  test('evidence: no 6×6 board at the uniqueness limit needs Expert', () {
    const s = GridShape.short;
    for (var seed = 0; seed < 2000; seed++) {
      final rng = Rng(seed);
      final solution = fullGrid(s, rng);
      final order = rng.shuffle(List.generate(36, (i) => i));
      final values = Generator.carve(s, solution, order, floor: 9);
      expect(
        grade(s, values).band,
        isNot(Difficulty.expert),
        reason: 'seed $seed',
      );
    }
  });
}
