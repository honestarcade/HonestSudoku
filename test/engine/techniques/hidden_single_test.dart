import 'package:flutter_test/flutter_test.dart';
import 'package:honest_sudoku/engine/engine.dart';

import 'staging.dart';

void main() {
  test('places a value that fits one cell of a unit', () {
    final g = openGrid();
    // 1 fits only R1C1 in row 1.
    strip(g, [for (var c = 1; c < 9; c++) rc(0, c)], [1]);
    expect(easierFindNothing(g, Technique.hiddenSingle), isTrue);
    final step = const HiddenSingle().apply(g)!;
    expect(
      [step.cells, step.value],
      [
        [0],
        1,
      ],
    );
  });

  test('finds nothing on an open grid', () {
    expect(const HiddenSingle().apply(openGrid()), isNull);
  });
}
