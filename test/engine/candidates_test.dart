import 'package:flutter_test/flutter_test.dart';
import 'package:honest_sudoku/engine/engine.dart';

import 'grid_strings.dart';

void main() {
  test('a cell whose peers hold every value but one has one candidate', () {
    final values = parseGrid(GridShape.classic, '''
      .23......
      4........
      5........
      .........
      6........
      7........
      8........
      9........
      .........
    ''');
    expect(candidates(GridShape.classic, values, 0), [1]);
  });

  test('an empty grid offers every value, ascending', () {
    expect(candidates(GridShape.short, List.filled(36, 0), 7), [
      1,
      2,
      3,
      4,
      5,
      6,
    ]);
  });

  test('entries count as placed, right or wrong, and the cell itself is '
      'ignored', () {
    final values = List.filled(16, 0);
    values[1] = 3; // a peer in the same row
    values[0] = 2; // the cell's own entry does not remove itself
    expect(candidates(GridShape.mini, values, 0), [1, 2, 4]);
  });

  test('16×16 candidates reach G', () {
    expect(candidates(GridShape.monster, List.filled(256, 0), 0).last, 16);
  });

  test('a fresh growable list each call', () {
    final a = candidates(GridShape.mini, List.filled(16, 0), 0);
    a.add(9);
    expect(candidates(GridShape.mini, List.filled(16, 0), 0), [1, 2, 3, 4]);
  });
}
