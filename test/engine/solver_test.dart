import 'package:flutter_test/flutter_test.dart';
import 'package:honest_sudoku/engine/engine.dart';

import 'grid_strings.dart';

// Project Euler problem 96, grid 01 (public), and its solution.
const _euler01 = '''
  ..3.2.6..
  9..3.5..1
  ..18.64..
  ..81.29..
  7.......8
  ..67.82..
  ..26.95..
  8..2.3..9
  ..5.1.3..
''';
const _euler01Solution = '''
  483921657
  967345821
  251876493
  548132976
  729564138
  136798245
  372689514
  814253769
  695417382
''';

void main() {
  const classic = GridShape.classic;

  test('a known 9×9 puzzle has exactly one solution, and solve finds it', () {
    final puzzle = parseGrid(classic, _euler01);
    expect(countSolutions(classic, puzzle), 1);
    expect(solve(classic, puzzle), parseGrid(classic, _euler01Solution));
  });

  test('a 4×4 with two solutions counts 2, not 1', () {
    // A full grid with the {2,4} rectangle in columns 1 and 3 blanked: the
    // two values swap freely, so there are exactly two solutions.
    final two = parseGrid(GridShape.mini, '''
      1234
      3412
      .1.3
      .3.1
    ''');
    expect(countSolutions(GridShape.mini, two), 2);
    expect(countSolutions(GridShape.mini, two, limit: null), 2);
    expect(countSolutions(GridShape.mini, two, limit: 1), 1);
    expect(solve(GridShape.mini, two), isNull);
  });

  test('an unsolvable grid counts 0', () {
    final dup = parseGrid(classic, _euler01);
    dup[0] = 3; // row 1 already holds a 3
    expect(isConsistent(classic, dup), isFalse);
    expect(countSolutions(classic, dup), 0);
    expect(solve(classic, dup), isNull);
  });

  test('a grid with no clash but no solution counts 0', () {
    // R1C1 sees 1 and 2 in its row and 3 and 4 in its column.
    final stuck = parseGrid(GridShape.mini, '''
      .12.
      3...
      4...
      ....
    ''');
    expect(isConsistent(GridShape.mini, stuck), isTrue);
    expect(countSolutions(GridShape.mini, stuck), 0);
  });

  test('a 16×16 full grid counts 1', () {
    final full = basePattern(GridShape.monster);
    expect(isConsistent(GridShape.monster, full), isTrue);
    expect(countSolutions(GridShape.monster, full), 1);
  });

  test('every shape: an empty grid has many solutions', () {
    for (final s in GridShape.all) {
      expect(countSolutions(s, List.filled(s.cellCount, 0)), 2, reason: '$s');
    }
  });

  test('the input is not modified and limit must be positive', () {
    final puzzle = parseGrid(classic, _euler01);
    final copy = List.of(puzzle);
    countSolutions(classic, puzzle);
    solve(classic, puzzle);
    expect(puzzle, copy);
    expect(
      () => countSolutions(classic, puzzle, limit: 0),
      throwsArgumentError,
    );
    expect(
      () => countSolutions(classic, puzzle.sublist(1)),
      throwsArgumentError,
    );
  });
}
