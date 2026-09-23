@Timeout(Duration(minutes: 5))
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:honest_sudoku/engine/engine.dart';

final class _EvilGrader implements Grader {
  @override
  Grade grade(
    GridShape shape,
    List<int> values, {
    Difficulty? ceiling,
    void Function(double filled)? onStep,
  }) => const Grade(Technique.beyond, []);
}

void main() {
  test('an unsupported pair is refused before any solving', () {
    var calls = 0;
    final generator = Generator(
      solutionCounter: (s, v) {
        calls++;
        return countSolutions(s, v);
      },
    );
    expect(
      () => generator.generate(GridShape.mini, 1, Difficulty.hard),
      throwsA(isA<UnsupportedDifficulty>()),
    );
    expect(
      () => generator.generate(GridShape.short, 1, Difficulty.evil),
      throwsA(isA<UnsupportedDifficulty>()),
    );
    expect(calls, 0);
  });

  for (final shape in [GridShape.mini, GridShape.short, GridShape.classic]) {
    for (final d in supportedDifficulties(shape)) {
      test('${shape.label} ${d.label}: graded to the band, unique, within '
          'the count rules', () {
        final p = const Generator().generate(shape, 1, d);
        expect(p.difficulty, d);
        expect(grade(shape, p.startingValues()).band, d);
        expect(p.technique!.band, d);
        expect(countSolutions(shape, p.startingValues()), 1);
        expect(p.givenCount, greaterThanOrEqualTo(givensFloor(shape)));
        if (d != Difficulty.evil) {
          final target = targetGivens(shape, d);
          expect(p.givenCount, lessThanOrEqualTo((target * 1.1).ceil()));
        }
        expect(p.attempts, greaterThanOrEqualTo(1));
      });
    }
  }

  test('same shape, seed and band: the same board', () {
    final a = const Generator().generate(GridShape.classic, 7, Difficulty.hard);
    final b = const Generator().generate(GridShape.classic, 7, Difficulty.hard);
    expect(a, b);
  });

  test('changing only the band changes the board but not the solution', () {
    final hard = const Generator().generate(
      GridShape.classic,
      7,
      Difficulty.hard,
    );
    final easy = const Generator().generate(
      GridShape.classic,
      7,
      Difficulty.easy,
    );
    expect(easy.solution, hard.solution);
    expect(easy.givens, isNot(hard.givens));
  });

  test('Evil on its first attempt is the uniqueness-limit carve', () {
    final evil = const Generator().generate(
      GridShape.classic,
      4,
      Difficulty.evil,
    );
    if (evil.attempts == 1) {
      final carve = const Generator().carveToUniqueness(GridShape.classic, 4);
      expect(evil.givens, carve.givens);
    } else {
      markTestSkipped('seed 4 needed ${evil.attempts} attempts');
    }
  });

  test('attempts run out as GenerationFailed with the seed', () {
    final generator = Generator(grader: _EvilGrader(), maxAttempts: 3);
    expect(
      () => generator.generate(GridShape.classic, 9, Difficulty.medium),
      throwsA(
        const GenerationFailed(GridShape.classic, Difficulty.medium, 9, 3),
      ),
    );
  });

  test('progress: 0, 0.45, rising, 0.85 and 1, never falling', () {
    final seen = <double>[];
    const Generator().generate(
      GridShape.classic,
      3,
      Difficulty.expert,
      onProgress: seen.add,
    );
    expect(seen.first, 0.0);
    expect(seen, contains(kProgressCarving));
    expect(seen, contains(kProgressGrading));
    expect(seen.last, 1.0);
    for (var i = 1; i < seen.length; i++) {
      expect(seen[i], greaterThan(seen[i - 1]));
    }
    expect(seen.where((f) => f < kProgressGrading).last, lessThan(0.85));
  });

  test('the attempt limits', () {
    expect(
      [for (final s in GridShape.all) defaultMaxAttempts(s)],
      [50, 10000, 2000, 200],
    );
  });
}
