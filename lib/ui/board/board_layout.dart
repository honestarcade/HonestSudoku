// The board screen's arithmetic, in the design's 390×844 points.
//
// Every number is the design's (`renderVals` and the board template). The
// screen multiplies them by one scale factor; thin lines stay one logical
// pixel, and the grid's cell size is snapped to whole pixels once so every
// line lands on the pixel grid.

import 'dart:math' as math;
import 'dart:ui';

import 'package:honest_sudoku/engine/engine.dart';

/// Width of the design frame.
const double kFrameWidth = 390;

/// Height of the design frame.
const double kFrameHeight = 844;

/// The top bar's y.
const double kTopBarY = 44;

/// The top bar's height.
const double kTopBarHeight = 44;

/// The grid's y.
const double kGridY = 100;

/// How far the pad drops while a notice shows.
const double kNoticeShift = 76;

/// The pad's and the notice's width.
const double kPadWidth = 362;

/// The pad's and the notice's left edge.
const double kSideInset = 14;

/// The tool row's height.
const double kToolBarHeight = 56;

/// The tool row's y: 22 above the frame's bottom.
const double kToolBarY = kFrameHeight - 22 - kToolBarHeight;

/// Gap between pad keys.
const double kPadGap = 7;

/// The layout for one grid shape, in design points.
final class BoardLayout {
  const BoardLayout._(this.shape);

  /// The layout for [shape].
  factory BoardLayout.of(GridShape shape) => BoardLayout._(shape);

  /// The grid's shape.
  final GridShape shape;

  int get _n => shape.n;

  /// Largest cell for this size: 66 up to 4×4, 54 up to 6×6, 39 up to 9×9,
  /// 22 for 16×16.
  double get cellCap => _n <= 4
      ? 66
      : _n <= 6
      ? 54
      : _n <= 9
      ? 39
      : 22;

  /// `floor(min(358 / n, cap))`.
  double get cell => math.min(358 / _n, cellCap).floorToDouble();

  /// `cell × n`.
  double get gridPx => cell * _n;

  /// The grid centred in the frame.
  double get gridX => ((kFrameWidth - gridPx) / 2).roundToDouble();

  /// The grid's y.
  double get gridY => kGridY;

  /// Digit size: `round(cell × (n > 9 ? .56 : .52))`, plus one with large
  /// digits.
  double digitSize({required bool bigDigits}) =>
      (cell * (_n > 9 ? .56 : .52)).roundToDouble() + (bigDigits ? 1 : 0);

  /// Pencil-mark columns: 2 up to 4×4, 3 up to 9×9, 4 on 16×16.
  int get noteCols => _n <= 4
      ? 2
      : _n <= 9
      ? 3
      : 4;

  /// Pencil-mark rows: every value has a fixed slot.
  int get noteRows => (_n / noteCols).ceil();

  /// Note size: `max(6, round(cell / (cols + 1.6)))`, less one with large
  /// digits.
  double noteSize({required bool bigDigits}) =>
      math.max(6, (cell / (noteCols + 1.6)).round()) - (bigDigits ? 1.0 : 0.0);

  /// Where the notice goes: 12 under the grid.
  double get noticeY => kGridY + gridPx + 12;

  /// Where the pad goes: under the notice while one shows.
  double padY({required bool hasNotice}) =>
      noticeY + (hasNotice ? kNoticeShift : 0);

  /// Pad columns: 4, 6, 5 and 4 for the four sizes.
  int get padCols => switch (_n) {
    4 => 4,
    6 => 6,
    9 => 5,
    _ => 4,
  };

  /// Key height: 52, or 40 on 16×16.
  double get padKeyHeight => _n == 16 ? 40 : 52;

  /// Key font size: 19, or 15 on 16×16.
  double get padFontSize => _n == 16 ? 15 : 19;

  /// Keys: one per value, and an erase key on 9×9.
  int get padKeyCount => _n + (_n == 9 ? 1 : 0);

  /// Rows of keys.
  int get padRows => (padKeyCount / padCols).ceil();

  /// The pad's height.
  double get padHeight => padRows * padKeyHeight + (padRows - 1) * kPadGap;

  /// Width of one key.
  double get padKeyWidth => (kPadWidth - (padCols - 1) * kPadGap) / padCols;
}

/// The grid at a scale: cell size snapped to whole pixels, re-centred.
final class ScaledGrid {
  /// Scales [layout] by [scale].
  ScaledGrid(this.layout, this.scale)
    : cellPx = (layout.cell * scale).floorToDouble();

  /// The design-point layout.
  final BoardLayout layout;

  /// Design points to logical pixels.
  final double scale;

  /// One cell, in whole logical pixels.
  final double cellPx;

  /// The grid's side.
  double get gridPx => cellPx * layout.shape.n;

  /// Left edge, centred in the scaled frame.
  double get gridX => ((kFrameWidth * scale - gridPx) / 2).roundToDouble();

  /// Thick lines and the selection ring: `max(2, round(2 × scale))`.
  double get thickPx => math.max(2, (2 * scale).roundToDouble());

  /// Thin lines stay one logical pixel.
  double get thinPx => 1;

  /// The top-left of cell [index].
  Offset cellOffset(int index) => Offset(
    layout.shape.colOf(index) * cellPx,
    layout.shape.rowOf(index) * cellPx,
  );
}

/// One grid line, relative to the grid's top-left.
typedef GridLine = ({Rect rect, bool thick});

/// Every line of [grid]: n + 1 vertical then n + 1 horizontal, thick at box
/// edges and the frame, each at `min(i × cell, gridPx − width)` as the design
/// draws them.
List<GridLine> gridLines(ScaledGrid grid) {
  final shape = grid.layout.shape;
  final n = shape.n;
  final lines = <GridLine>[];
  for (var i = 0; i <= n; i++) {
    final thick = i % shape.boxW == 0 || i == n;
    final w = thick ? grid.thickPx : grid.thinPx;
    final x = math.min(i * grid.cellPx, grid.gridPx - w);
    lines.add((rect: Rect.fromLTWH(x, 0, w, grid.gridPx), thick: thick));
  }
  for (var i = 0; i <= n; i++) {
    final thick = i % shape.boxH == 0 || i == n;
    final h = thick ? grid.thickPx : grid.thinPx;
    final y = math.min(i * grid.cellPx, grid.gridPx - h);
    lines.add((rect: Rect.fromLTWH(0, y, grid.gridPx, h), thick: thick));
  }
  return lines;
}
