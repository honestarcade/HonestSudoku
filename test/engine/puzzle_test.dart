import 'package:flutter_test/flutter_test.dart';
import 'package:honest_sudoku/engine/engine.dart';

import 'grid_strings.dart';

void main() {
  final solution = basePattern(GridShape.mini);
  final givens = [for (var i = 0; i < 16; i++) i.isEven];

  Puzzle make({int givenCount = 8, List<bool>? mask}) => Puzzle(
    shape: GridShape.mini,
    seed: 5,
    solution: solution,
    givens: mask ?? givens,
    givenCount: givenCount,
  );

  test('startingValues fills givens only, fresh and mutable each call', () {
    final p = make();
    final start = p.startingValues();
    expect(start.where((v) => v != 0).length, 8);
    expect(start[1], 0);
    expect(start[0], solution[0]);
    start[1] = 3;
    expect(p.startingValues()[1], 0);
  });

  test('lists are unmodifiable copies', () {
    final p = make();
    expect(() => p.solution[0] = 9, throwsUnsupportedError);
    expect(() => p.givens[0] = false, throwsUnsupportedError);
  });

  test('value equality', () {
    expect(make(), make());
    expect(make().hashCode, make().hashCode);
    expect(
      make(),
      isNot(make(mask: [false, ...givens.skip(1)], givenCount: 7)),
    );
  });

  test('the constructor validates the lists', () {
    expect(() => make(givenCount: 7), throwsArgumentError);
    expect(
      () => Puzzle(
        shape: GridShape.mini,
        seed: 0,
        solution: List.filled(16, 0),
        givens: givens,
        givenCount: 8,
      ),
      throwsArgumentError,
    );
  });
}
