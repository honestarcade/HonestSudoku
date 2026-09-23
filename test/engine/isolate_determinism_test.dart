import 'dart:isolate';

import 'package:flutter_test/flutter_test.dart';
import 'package:honest_sudoku/engine/engine.dart';

void main() {
  for (final shape in GridShape.all) {
    test('${shape.label}: twice in one process and once in an isolate, the '
        'same board', () async {
      final a = const Generator().carveToUniqueness(shape, 20260824);
      final b = const Generator().carveToUniqueness(shape, 20260824);
      final c = await Isolate.run(
        () => const Generator().carveToUniqueness(shape, 20260824),
      );
      expect(b.solution, a.solution);
      expect(b.givens, a.givens);
      expect(c.solution, a.solution);
      expect(c.givens, a.givens);
      expect(c, a);
    }, timeout: const Timeout(Duration(minutes: 5)));
  }
}
