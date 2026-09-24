import 'package:flutter_test/flutter_test.dart';
import 'package:honest_sudoku/engine/engine.dart';

void main() {
  test('peers of a 9×9 cell: its row, column and box, minus itself', () {
    final peers = unitsOf(GridShape.classic, 40); // R5C5, centre box
    expect(peers.length, 20);
    expect(peers, isNot(contains(40)));
    expect(peers, containsAll([36, 44, 4, 76, 30, 50]));
    expect(peers, orderedEquals([...peers]..sort()));
  });

  test('every cell has 2(n - 1) + (boxH - 1)(boxW - 1) peers', () {
    for (final s in GridShape.all) {
      final expected = 2 * (s.n - 1) + (s.boxH - 1) * (s.boxW - 1);
      for (var i = 0; i < s.cellCount; i++) {
        expect(unitsOf(s, i).length, expected, reason: '$s cell $i');
      }
    }
  });

  test('peers are unmodifiable', () {
    expect(() => unitsOf(GridShape.mini, 0).add(1), throwsUnsupportedError);
  });

  test('unitList: rows, then columns, then boxes row-major, design names', () {
    const s = GridShape.short;
    final units = unitList(s);
    expect(units.length, 18);
    expect(units.take(6).map((u) => u.name), [
      for (var k = 1; k <= 6; k++) 'row $k',
    ]);
    expect(units.skip(6).take(6).map((u) => u.name), [
      for (var k = 1; k <= 6; k++) 'column $k',
    ]);
    expect(units.skip(12).map((u) => u.name).toSet(), {'this box'});
    expect(units[0].cells, [0, 1, 2, 3, 4, 5]);
    expect(units[6].cells, [0, 6, 12, 18, 24, 30]);
    // Boxes are two rows by three columns, the second one to the right.
    expect(units[12].cells, [0, 1, 2, 6, 7, 8]);
    expect(units[13].cells, [3, 4, 5, 9, 10, 11]);
    expect(units[14].cells, [12, 13, 14, 18, 19, 20]);
    expect(units[12].kind, UnitKind.box);
    expect(units[13].ordinal, 2);
    expect(units[2].toString(), 'Unit(row 3)');
  });

  test('every unit of every shape is n distinct cells', () {
    for (final s in GridShape.all) {
      final units = unitList(s);
      expect(units.length, 3 * s.n);
      for (final u in units) {
        expect(u.cells.toSet().length, s.n, reason: '$s $u');
      }
    }
  });
}
