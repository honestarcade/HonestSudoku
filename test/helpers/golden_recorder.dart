// The one writer of test/fixtures/golden_boards.json.
//
// Run with `flutter test --dart-define=RECORD_GOLDENS=true
// test/engine/golden_boards_test.dart` to rewrite the whole file from the
// current engine. Record mode then FAILS the test, so a run that rewrote the
// fixture can never be mistaken for a run that checked it.

import 'dart:convert';
import 'dart:io';

import 'package:honest_sudoku/engine/engine.dart';

import 'board_hash.dart';

/// True when this run should rewrite the fixture instead of checking it.
const bool recordGoldens = bool.fromEnvironment('RECORD_GOLDENS');

/// Repository-relative path of the fixture.
const String goldenPath = 'test/fixtures/golden_boards.json';

/// The seeds each shape is pinned at: 1, 2 and the design's 20260824.
const List<int> goldenSeeds = [1, 2, 20260824];

const String _comment =
    'Determinism anchors for invariant 4. Written by '
    'test/helpers/golden_recorder.dart, never by hand. Any change to rng, '
    'full_grid, the carving order or the grading ladder MUST fail a test that '
    'reads this file; if a change is intended, re-record and say why in the '
    'commit. `boards` are ungraded carves (test/engine/golden_boards_test.dart); '
    '`graded` pins seed 20260824 for every supported size and band '
    '(test/guards/engine_guard_*_test.dart).';

/// The seed every graded golden is pinned at: the design's.
const int gradedGoldenSeed = 20260824;

/// One `boards` entry: the ungraded carve for (shape, seed).
Map<String, Object> boardEntry(GridShape shape, int seed) {
  final p = const Generator().carveToUniqueness(shape, seed);
  return {
    'shape': shape.label.replaceAll('×', 'x'),
    'seed': seed,
    'hash': boardHash(p),
    'givenCount': p.givenCount,
  };
}

/// One `graded` entry: the generated board for (shape, band) at
/// [gradedGoldenSeed].
Map<String, Object> gradedEntry(GridShape shape, Difficulty difficulty) {
  final p = const Generator().generate(shape, gradedGoldenSeed, difficulty);
  return {
    'shape': shape.label.replaceAll('×', 'x'),
    'difficulty': difficulty.key,
    'seed': gradedGoldenSeed,
    'hash': boardHash(p),
    'technique': p.technique!.name,
    'givenCount': p.givenCount,
    'attempts': p.attempts!,
  };
}

/// Every entry the fixture holds, computed from the current engine.
Map<String, Object> computeGoldens() => {
  '_comment': _comment,
  'boards': [
    for (final shape in GridShape.all)
      for (final seed in goldenSeeds) boardEntry(shape, seed),
  ],
  'graded': [
    for (final shape in GridShape.all)
      for (final d in supportedDifficulties(shape)) gradedEntry(shape, d),
  ],
};

/// The committed `graded` entry for (shape, band).
Map<String, dynamic> committedGraded(GridShape shape, Difficulty difficulty) {
  final label = shape.label.replaceAll('×', 'x');
  return (readGoldens()['graded'] as List)
      .cast<Map<String, dynamic>>()
      .firstWhere(
        (e) => e['shape'] == label && e['difficulty'] == difficulty.key,
        orElse: () =>
            throw StateError('no graded golden for $label ${difficulty.key}'),
      );
}

/// Rewrites the fixture from [goldens].
void writeGoldens(Map<String, Object> goldens) {
  File(goldenPath).writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(goldens)}\n',
  );
}

/// The fixture as committed.
Map<String, dynamic> readGoldens() =>
    jsonDecode(File(goldenPath).readAsStringSync()) as Map<String, dynamic>;
