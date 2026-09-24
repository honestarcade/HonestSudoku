import 'package:flutter_test/flutter_test.dart';
import 'package:honest_sudoku/engine/engine.dart';

import 'staging.dart';

void main() {
  test('hidden pair: two values that fit only the same two cells', () {
    final g = openGrid();
    // In row 1, 1 and 2 fit only R1C1 and R1C4 (different boxes, so no
    // locked candidate forms).
    strip(
      g,
      [
        for (var c = 0; c < 9; c++)
          if (c != 0 && c != 3) rc(0, c),
      ],
      [1, 2],
    );
    expect(easierFindNothing(g, Technique.hiddenPair), isTrue);
    final step = const HiddenSubset.pair().apply(g)!;
    expect(step.technique, Technique.hiddenPair);
    expect(step.cells, [0, 3]);
    expect(g.cands[0], bits([1, 2]));
    expect(g.cands[3], bits([1, 2]));
  });

  test('hidden triple: three values that fit only the same three cells', () {
    final g = openGrid();
    strip(
      g,
      [
        for (final c in [1, 2, 4, 5, 7, 8]) rc(0, c),
      ],
      [1, 2, 3],
    );
    expect(easierFindNothing(g, Technique.hiddenTriple), isTrue);
    final step = const HiddenSubset.triple().apply(g)!;
    expect(step.technique, Technique.hiddenTriple);
    expect(step.cells, [0, 3, 6]);
    for (final c in [0, 3, 6]) {
      expect(g.cands[c], bits([1, 2, 3]));
    }
  });

  test('find nothing on an open grid', () {
    expect(const HiddenSubset.pair().apply(openGrid()), isNull);
    expect(const HiddenSubset.triple().apply(openGrid()), isNull);
  });
}
