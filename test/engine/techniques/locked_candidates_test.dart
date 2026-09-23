import 'package:flutter_test/flutter_test.dart';
import 'package:honest_sudoku/engine/engine.dart';

import 'staging.dart';

void main() {
  test('pointing: a box value confined to one row leaves the rest of it', () {
    final g = openGrid();
    // In box 1, 1 fits only row 1.
    strip(g, [rc(1, 0), rc(1, 1), rc(1, 2), rc(2, 0), rc(2, 1), rc(2, 2)], [1]);
    expect(easierFindNothing(g, Technique.pointing), isTrue);
    final step = const Pointing().apply(g)!;
    expect(step.technique, Technique.pointing);
    expect(step.cells, [0, 1, 2]);
    expect(step.eliminations, [for (var c = 3; c < 9; c++) (rc(0, c), 1)]);
  });

  test('claiming: a row value confined to one box leaves the rest of it', () {
    final g = openGrid();
    // In row 1, 1 fits only box 1.
    strip(g, [for (var c = 3; c < 9; c++) rc(0, c)], [1]);
    expect(easierFindNothing(g, Technique.claiming), isTrue);
    final step = const Claiming().apply(g)!;
    expect(step.technique, Technique.claiming);
    expect(step.eliminations.map((e) => e.$1), [
      rc(1, 0),
      rc(1, 1),
      rc(1, 2),
      rc(2, 0),
      rc(2, 1),
      rc(2, 2),
    ]);
  });

  test('both find nothing on an open grid', () {
    expect(const Pointing().apply(openGrid()), isNull);
    expect(const Claiming().apply(openGrid()), isNull);
  });
}
