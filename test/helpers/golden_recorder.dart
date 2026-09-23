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
    'full_grid or the carving order MUST fail the test that reads this file; '
    'if a change is intended, re-record and say why in the commit.';

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

/// Every entry the fixture holds, computed from the current engine.
Map<String, Object> computeGoldens() => {
  '_comment': _comment,
  'boards': [
    for (final shape in GridShape.all)
      for (final seed in goldenSeeds) boardEntry(shape, seed),
  ],
};

/// Rewrites the fixture from [goldens].
void writeGoldens(Map<String, Object> goldens) {
  File(goldenPath).writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(goldens)}\n',
  );
}

/// The fixture as committed.
Map<String, dynamic> readGoldens() =>
    jsonDecode(File(goldenPath).readAsStringSync()) as Map<String, dynamic>;
