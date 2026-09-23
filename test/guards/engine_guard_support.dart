// The property guard for invariants 2 and 4, shared by the per-shape files.
//
// The real generator, grader and solution counter, over seeds 1..k for every
// supported size and band. Coverage is statistical by nature: a defect that
// only shows on a seed outside the range passes here. The weekly tier
// (engine_guard_weekly_test.dart, `.github/workflows/engine-nightly.yml`)
// widens every pair to 200 seeds and adds 16×16 Evil.
//
// Each rule is its own test so a failure names the rule, and every offending
// seed is listed at once.

import 'package:flutter_test/flutter_test.dart';
import 'package:honest_sudoku/engine/engine.dart';

import '../helpers/board_hash.dart';
import '../helpers/golden_recorder.dart';
import 'repo_files.dart';

/// Seeds per band in the pull-request tier.
int prSeeds(GridShape shape) => switch (shape.n) {
  4 || 6 => 200,
  9 => 40,
  _ => 5,
};

/// The design's floor, written out here rather than read from the engine so
/// that a change to the engine's own floor is something this can catch.
int _floor(GridShape shape) => shape.n + shape.n ~/ 2;

/// Registers the property tests for [shape], seeds `1..seeds`, for every
/// supported band except those in [skip].
void engineGuard(
  GridShape shape, {
  required int seeds,
  Set<Difficulty> skip = const {},
}) {
  for (final d in supportedDifficulties(shape)) {
    if (skip.contains(d)) continue;
    group('${shape.label} ${d.label}, seeds 1..$seeds', () {
      final boards = <int, Puzzle>{};
      final failures = <int, Object>{};

      setUpAll(() {
        for (var seed = 1; seed <= seeds; seed++) {
          try {
            boards[seed] = const Generator().generate(shape, seed, d);
          } on Object catch (e) {
            failures[seed] = e;
          }
        }
      });

      test('every seed generates a board', () {
        expect(
          failures,
          isEmpty,
          reason: describeOffenders('engine-generation', [
            for (final e in failures.entries) 'seed ${e.key}: ${e.value}',
          ]),
        );
      });

      test('every board has exactly one solution', () {
        final offenders = [
          for (final e in boards.entries)
            if (countSolutions(shape, e.value.startingValues()) != 1)
              'seed ${e.key}',
        ];
        expect(
          offenders,
          isEmpty,
          reason: describeOffenders('engine-unique', offenders),
        );
      });

      test('every board grades to its band', () {
        final offenders = <String>[];
        for (final e in boards.entries) {
          final g = grade(shape, e.value.startingValues());
          if (g.band != d || e.value.difficulty != d) {
            offenders.add(
              'seed ${e.key}: labelled ${e.value.difficulty?.label}, grades '
              '${g.band.label} (${g.technique.name})',
            );
          } else if (e.value.technique != g.technique) {
            offenders.add(
              'seed ${e.key}: records ${e.value.technique?.name}, grades '
              '${g.technique.name}',
            );
          }
        }
        expect(
          offenders,
          isEmpty,
          reason: describeOffenders('engine-band', offenders),
        );
      });

      test('every board keeps the n + n/2 givens floor', () {
        final offenders = [
          for (final e in boards.entries)
            if (e.value.givenCount < _floor(shape) ||
                e.value.givens.where((g) => g).length < _floor(shape))
              'seed ${e.key}: ${e.value.givenCount} givens',
        ];
        expect(
          offenders,
          isEmpty,
          reason: describeOffenders('engine-floor', offenders),
        );
      });

      test('seed 1 regenerates identically in a fresh generator', () {
        final again = const Generator().generate(shape, 1, d);
        expect(
          [again.solution, again.givens, again.difficulty, again.technique],
          [
            boards[1]?.solution,
            boards[1]?.givens,
            boards[1]?.difficulty,
            boards[1]?.technique,
          ],
          reason:
              'engine-determinism: ${shape.label} ${d.label} seed 1 gave a '
              'different board the second time',
        );
      });
    });
  }
}

/// Registers the graded-golden check for [shape]'s bands, except [skip].
void gradedGoldens(GridShape shape, {Set<Difficulty> skip = const {}}) {
  for (final d in supportedDifficulties(shape)) {
    if (skip.contains(d)) continue;
    test('${shape.label} ${d.label}: the graded golden regenerates', () {
      final committed = committedGraded(shape, d);
      final p = const Generator().generate(shape, gradedGoldenSeed, d);
      expect(
        {
          'hash': boardHash(p),
          'technique': p.technique!.name,
          'givenCount': p.givenCount,
          'attempts': p.attempts,
        },
        {
          'hash': committed['hash'],
          'technique': committed['technique'],
          'givenCount': committed['givenCount'],
          'attempts': committed['attempts'],
        },
        reason:
            'engine-golden: ${shape.label} ${d.label} at seed '
            '$gradedGoldenSeed is not the pinned board — the PRNG, the full '
            'grid, the carving order or the grading ladder changed',
      );
    });
  }
}
