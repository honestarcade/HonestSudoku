import 'package:flutter_test/flutter_test.dart';
import 'package:honest_sudoku/engine/engine.dart';

void main() {
  for (final shape in [GridShape.mini, GridShape.classic]) {
    test('progress on ${shape.label}: 0, 0.45, one tick per cell to 0.85, '
        'then 1', () {
      final seen = <double>[];
      const Generator().carveToUniqueness(shape, 1, onProgress: seen.add);
      expect(seen.length, shape.cellCount + 3);
      expect(seen.first, 0.0);
      expect(seen[1], kProgressCarving);
      expect(seen[seen.length - 2], kProgressGrading);
      expect(seen.last, 1.0);
      for (var i = 1; i < seen.length; i++) {
        expect(seen[i], greaterThanOrEqualTo(seen[i - 1]), reason: 'tick $i');
      }
    });
  }

  test('the thresholds are the loading labels', () {
    expect(kProgressCarving, 0.45);
    expect(kProgressGrading, 0.85);
  });

  test('onProgress may be null', () {
    expect(
      const Generator().carveToUniqueness(GridShape.mini, 1).givenCount,
      greaterThanOrEqualTo(givensFloor(GridShape.mini)),
    );
  });
}
