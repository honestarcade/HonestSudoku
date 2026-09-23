@Timeout(Duration(minutes: 5))
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:honest_sudoku/engine/engine.dart';

void main() {
  for (final shape in GridShape.all) {
    final count = shape.n == 16 ? 5 : 20;
    test('${shape.label}: $count boards from seeds 1.. are each unique and '
        'at or above the floor', () {
      for (var seed = 1; seed <= count; seed++) {
        final p = const Generator().carveToUniqueness(shape, seed);
        expect(
          countSolutions(shape, p.startingValues()),
          1,
          reason: '${shape.label} seed $seed',
        );
        expect(p.givenCount, greaterThanOrEqualTo(givensFloor(shape)));
        expect(p.startingValues(), [
          for (var i = 0; i < p.solution.length; i++)
            p.givens[i] ? p.solution[i] : 0,
        ]);
      }
    });

    test('${shape.label}: carving stops at the uniqueness boundary, not the '
        'floor', () {
      final p = const Generator().carveToUniqueness(shape, 1);
      if (p.givenCount == givensFloor(shape)) {
        markTestSkipped('${shape.label} seed 1 sits exactly at the floor');
        return;
      }
      final values = p.startingValues();
      var breaks = false;
      for (var i = 0; i < values.length && !breaks; i++) {
        if (values[i] == 0) continue;
        final v = values[i];
        values[i] = 0;
        breaks = countSolutions(shape, values) != 1;
        values[i] = v;
      }
      expect(
        breaks,
        isTrue,
        reason:
            'no given could be removed without '
            'breaking uniqueness, so carving stopped early',
      );
    });
  }
}
