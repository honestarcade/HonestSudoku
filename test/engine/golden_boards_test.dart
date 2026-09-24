import 'package:flutter_test/flutter_test.dart';
import 'package:honest_sudoku/engine/engine.dart';

import '../helpers/board_hash.dart';
import '../helpers/golden_recorder.dart';

void main() {
  test('the golden boards regenerate identically', () {
    if (recordGoldens) {
      writeGoldens(computeGoldens());
      fail('RECORD_GOLDENS: $goldenPath rewritten; re-run without it');
    }
    final boards = (readGoldens()['boards'] as List)
        .cast<Map<String, dynamic>>();
    expect(boards, hasLength(GridShape.all.length * goldenSeeds.length));
    for (final entry in boards) {
      final shape = GridShape.byLabel(entry['shape'] as String);
      final seed = entry['seed'] as int;
      expect(
        boardEntry(shape, seed),
        entry,
        reason:
            'golden: ${entry['shape']} seed $seed no longer carves the '
            'pinned board — rng, full_grid or the carving order changed',
      );
    }
  });

  test('the hash is FNV-1a 64 over the canonical string', () {
    // The published FNV-1a 64 test vectors.
    expect(fnv1a64(''), 'cbf29ce484222325');
    expect(fnv1a64('a'), 'af63dc4c8601ec8c');
    final p = const Generator().carveToUniqueness(GridShape.mini, 1);
    expect(canonicalBoard(p), startsWith('4;'));
    expect(canonicalBoard(p).split(';').last, hasLength(16));
  });

  test('changing the seed by one changes the board', () {
    for (final shape in [GridShape.mini, GridShape.classic]) {
      expect(
        boardHash(const Generator().carveToUniqueness(shape, 1)),
        isNot(boardHash(const Generator().carveToUniqueness(shape, 2))),
      );
    }
  });
}
