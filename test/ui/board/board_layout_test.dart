import 'package:flutter_test/flutter_test.dart';
import 'package:honest_sudoku/engine/engine.dart';
import 'package:honest_sudoku/ui/board/board_layout.dart';

void main() {
  // (cell, gridPx, gridX, digit, digit big, note cols, note rows, note size,
  // note big) per size, from the design's renderVals.
  const expected = {
    4: (66.0, 264.0, 63.0, 34.0, 35.0, 2, 2, 18.0, 17.0),
    6: (54.0, 324.0, 33.0, 28.0, 29.0, 3, 2, 12.0, 11.0),
    9: (39.0, 351.0, 20.0, 20.0, 21.0, 3, 3, 8.0, 7.0),
    16: (22.0, 352.0, 19.0, 12.0, 13.0, 4, 4, 6.0, 5.0),
  };

  for (final shape in GridShape.all) {
    test('${shape.label}: the design arithmetic', () {
      final l = BoardLayout.of(shape);
      final e = expected[shape.n]!;
      expect((
        l.cell,
        l.gridPx,
        l.gridX,
        l.digitSize(bigDigits: false),
        l.digitSize(bigDigits: true),
        l.noteCols,
        l.noteRows,
        l.noteSize(bigDigits: false),
        l.noteSize(bigDigits: true),
      ), e);
    });

    test(
      '${shape.label}: notice at grid + 12, pad 76 lower while it shows',
      () {
        final l = BoardLayout.of(shape);
        expect(l.noticeY, 100 + l.gridPx + 12);
        expect(l.padY(), l.noticeY);
        // The design's 64-pt banner: the pad 12 below it, as #31 had it.
        expect(l.padY(noticeHeight: 64), l.noticeY + 76);
      },
    );

    test('${shape.label}: n + 1 lines each way, thick at box edges', () {
      final grid = ScaledGrid(BoardLayout.of(shape), 1);
      final lines = gridLines(grid);
      expect(lines, hasLength((shape.n + 1) * 2));
      final vertical = lines.take(shape.n + 1).toList();
      final horizontal = lines.skip(shape.n + 1).toList();
      for (var i = 0; i <= shape.n; i++) {
        expect(vertical[i].thick, i % shape.boxW == 0 || i == shape.n);
        expect(horizontal[i].thick, i % shape.boxH == 0 || i == shape.n);
      }
      // The last line sits inside the grid, not past it.
      expect(vertical.last.rect.right, grid.gridPx);
      expect(vertical[1].rect.width, 1, reason: 'thin lines stay one pixel');
    });
  }

  test('top bar and tool row positions', () {
    expect([kTopBarY, kTopBarHeight, kToolBarY], [44, 44, 766]);
  });

  test('a scaled grid snaps its cell to whole pixels and re-centres', () {
    final g = ScaledGrid(BoardLayout.of(GridShape.classic), 0.9231);
    expect(g.cellPx, (39 * 0.9231).floorToDouble());
    expect(g.gridPx, g.cellPx * 9);
    expect(g.thickPx, 2);
    expect(ScaledGrid(BoardLayout.of(GridShape.classic), 1.6).thickPx, 3);
  });
}
