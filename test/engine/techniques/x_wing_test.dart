import 'package:flutter_test/flutter_test.dart';
import 'package:honest_sudoku/engine/engine.dart';

import 'staging.dart';

void main() {
  test('rows 1 and 5 confine 1 to columns 1 and 5', () {
    final g = openGrid();
    for (final r in [0, 4]) {
      strip(
        g,
        [
          for (var c = 0; c < 9; c++)
            if (c != 0 && c != 4) rc(r, c),
        ],
        [1],
      );
    }
    expect(easierFindNothing(g, Technique.xWing), isTrue);
    final step = const XWing().apply(g)!;
    expect(step.technique, Technique.xWing);
    expect(step.cells, [rc(0, 0), rc(0, 4), rc(4, 0), rc(4, 4)]);
    for (final r in [1, 2, 3, 5, 6, 7, 8]) {
      expect(g.cands[rc(r, 0)] & bits([1]), 0, reason: 'R${r + 1}C1');
      expect(g.cands[rc(r, 4)] & bits([1]), 0, reason: 'R${r + 1}C5');
    }
  });

  test('needs at least 6×6 and finds nothing on an open grid', () {
    expect(const XWing().apply(openGrid(GridShape.mini)), isNull);
    expect(const XWing().apply(openGrid()), isNull);
  });
}
