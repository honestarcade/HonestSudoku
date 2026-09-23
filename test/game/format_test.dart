import 'package:flutter_test/flutter_test.dart';
import 'package:honest_sudoku/game/game.dart';

import 'fixtures.dart';

void main() {
  test('fmt is m:ss with padded seconds, minutes past an hour', () {
    expect(fmt(0), '0:00');
    expect(fmt(9), '0:09');
    expect(fmt(61), '1:01');
    expect(fmt(3600), '60:00');
    expect(fmt(3725), '62:05');
  });

  test('pause lines in the design words', () {
    final s = GameState.start(classic)
        .copyWith(moves: 1, mistakes: 2, elapsedSeconds: 125);
    expect(s.pauseFill, '41 of 81 cells filled · 1 entries · 2 mistakes');
    expect(s.pauseMeta, '9×9 · MEDIUM · 2:05');
    final zen = s.withSettings(const GameSettings(strikeMode: StrikeMode.zen));
    expect(zen.pauseFill, endsWith('· zen mode'));
  });
}
