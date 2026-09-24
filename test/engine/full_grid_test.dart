import 'package:flutter_test/flutter_test.dart';
import 'package:honest_sudoku/engine/engine.dart';

import 'grid_strings.dart';

void main() {
  test('seed 20260824 on 9×9 gives the design board', () {
    // Computed once by running the design file's own `fullGrid` (lines
    // 965–979 of Honest Sudoku.dc.html) in node v24.15.0 on 2026-09-23.
    final expected = parseGrid(GridShape.classic, '''
      618527349
      752394168
      439186572
      973418625
      265739481
      841652793
      586273914
      327941856
      194865237
    ''');
    expect(fullGrid(GridShape.classic, Rng(20260824)), expected);
  });

  for (final shape in GridShape.all) {
    test('every unit of a ${shape.label} full grid is a permutation', () {
      for (final seed in [0, 1, 2, 20260824]) {
        final grid = fullGrid(shape, Rng(seed));
        for (final unit in unitList(shape)) {
          expect(unit.cells.map((i) => grid[i]).toSet(), {
            for (var v = 1; v <= shape.n; v++) v,
          }, reason: '$shape seed $seed $unit');
        }
      }
    });
  }
}
