import 'package:flutter_test/flutter_test.dart';
import 'package:honest_sudoku/engine/engine.dart';

import 'design_strings.dart';
import 'grid_strings.dart';

void main() {
  final sol4 = basePattern(GridShape.mini);
  List<int> board(Map<int, int> cells) {
    final out = List.of(sol4);
    cells.forEach((i, v) => out[i] = v);
    return out;
  }

  test('one wrong entry', () {
    final r = check(GridShape.mini, board({0: 0, 5: 1}), sol4);
    expect(r.wrongCells, [5]);
    expect(r.tag, 'CHECK');
    expect(r.body, checkOneWrong);
    expect(r.banner, BannerKind.error);
    expect(r.isClean, isFalse);
    expect(r.remaining, 1);
  });

  test('two wrong entries, sorted', () {
    final r = check(GridShape.mini, board({9: 1, 2: 1}), sol4);
    expect(r.wrongCells, [2, 9]);
    expect(r.body, checkTwoWrong);
    expect(r.isFull, isTrue, reason: 'a full grid with wrong cells is full');
  });

  test('nothing wrong counts the cells to go, in the design grammar', () {
    expect(
      check(GridShape.mini, board({0: 0, 1: 0, 2: 0}), sol4).body,
      checkClean3,
    );
    final one = check(GridShape.mini, board({0: 0}), sol4);
    expect(one.body, checkClean1);
    expect(one.banner, BannerKind.ok);
    final done = check(GridShape.mini, sol4, sol4);
    expect(done.body, checkClean0);
    expect([done.isFull, done.isClean], [true, true]);
  });

  test('9×9: remaining counts empty cells only', () {
    final sol9 = basePattern(GridShape.classic);
    final values = List.of(sol9)
      ..[0] = 0
      ..[40] = 0
      ..[80] = (sol9[80] % 9) + 1;
    final r = check(GridShape.classic, values, sol9);
    expect(
      [r.remaining, r.wrongCells],
      [
        2,
        [80],
      ],
    );
  });

  test('value equality', () {
    expect(
      check(GridShape.mini, sol4, sol4),
      check(GridShape.mini, sol4, sol4),
    );
  });

  test('MISTAKE and GRID FULL templates', () {
    expect(mistakeBody(2, 3), mistakeStrike2of3);
    expect(mistakeBody(4, null), mistakeNoLimit4);
    expect(kGridFullBody, gridFull);
    expect([kTagMistake, kTagGridFull], ['MISTAKE', 'GRID FULL']);
  });
}
