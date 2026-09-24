import 'package:flutter_test/flutter_test.dart';
import 'package:honest_sudoku/engine/engine.dart';

void main() {
  test('the four shapes are the design SIZES table', () {
    expect(
      [
        for (final s in GridShape.all) [s.n, s.boxH, s.boxW, s.label, s.sub],
      ],
      [
        [4, 2, 2, '4×4', 'MINI'],
        [6, 2, 3, '6×6', 'SHORT'],
        [9, 3, 3, '9×9', 'CLASSIC'],
        [16, 4, 4, '16×16', 'MONSTER'],
      ],
    );
  });

  test('symbols run 1–9 then A–G', () {
    expect(kSymbols, '123456789ABCDEFG');
    expect(GridShape.monster.symbolFor(10), 'A');
    expect(GridShape.monster.symbolFor(16), 'G');
    expect(GridShape.classic.symbolFor(9), '9');
    expect(GridShape.classic.symbolFor(0), '');
    expect(() => GridShape.classic.symbolFor(10), throwsArgumentError);
    expect(() => GridShape.mini.symbolFor(-1), throwsArgumentError);
  });

  test('cells are named R<r>C<c>, 1-based, from row * n + col', () {
    expect(cellName(GridShape.classic, 0), 'R1C1');
    expect(cellName(GridShape.classic, 10), 'R2C2');
    expect(cellName(GridShape.classic, 80), 'R9C9');
    expect(cellName(GridShape.monster, 17), 'R2C2');
    expect(() => cellName(GridShape.mini, 16), throwsRangeError);
  });

  test('row, column and box of an index', () {
    const s = GridShape.short;
    // Index 11 is row 1, column 5: the second box of the first band.
    expect([s.rowOf(11), s.colOf(11), s.boxOf(11)], [1, 5, 1]);
    // Index 12 is row 2, column 0: the first box of the second band.
    expect([s.rowOf(12), s.colOf(12), s.boxOf(12)], [2, 0, 2]);
    expect(GridShape.classic.boxOf(80), 8);
  });

  test('byLabel accepts × and x and refuses anything else', () {
    expect(GridShape.byLabel('9×9'), same(GridShape.classic));
    expect(GridShape.byLabel('16x16'), same(GridShape.monster));
    expect(() => GridShape.byLabel('8×8'), throwsArgumentError);
    expect(GridShape.classic.toString(), 'GridShape(9×9)');
  });

  test('value lists are validated', () {
    expect(
      () => checkValues(GridShape.mini, List.filled(15, 0)),
      throwsArgumentError,
    );
    expect(
      () => checkValues(GridShape.mini, List.filled(16, 5)),
      throwsArgumentError,
    );
    checkValues(GridShape.mini, List.filled(16, 4));
  });

  test('listEquals compares elements in order', () {
    expect(listEquals([1, 2], [1, 2]), isTrue);
    expect(listEquals([1, 2], [2, 1]), isFalse);
    expect(listEquals([1], [1, 1]), isFalse);
    expect(listEquals<int>(null, null), isTrue);
    expect(listEquals<int>([], null), isFalse);
  });
}
