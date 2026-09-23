import 'package:flutter_test/flutter_test.dart';
import 'package:honest_sudoku/engine/engine.dart';

import 'staging.dart';

void main() {
  test('places the only candidate of the first such cell', () {
    final g = openGrid();
    g.cands[rc(4, 4)] = bits([7]);
    final step = const NakedSingle().apply(g)!;
    expect(step.technique, Technique.nakedSingle);
    expect(
      [step.cells, step.value],
      [
        [rc(4, 4)],
        7,
      ],
    );
    expect(g.values[rc(4, 4)], 7);
    expect(g.cands[rc(4, 3)] & bits([7]), 0, reason: 'removed from peers');
  });

  test('finds nothing when every cell has several candidates', () {
    expect(const NakedSingle().apply(openGrid()), isNull);
  });
}
