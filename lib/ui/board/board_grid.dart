// The grid: cells with their values or pencil marks, the lines, and the
// selection ring, coloured by a board theme. It reads the model's derived
// flags and applies the display toggles; it holds no rule logic and no state.

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:honest_sudoku/game/game.dart';

import '../a11y/labels.dart';
import '../theme/board_theme.dart';
import '../theme/tokens.dart';
import 'board_layout.dart';

/// The cells tinted and underlined as wrong: wrong entries while the model
/// shows them. The tint and the underline read this one predicate (#52).
Set<int> wrongShownCells(GameState s) => {
  if (s.showWrong)
    for (var i = 0; i < s.values.length; i++)
      if (s.isWrong(i)) i,
};

/// The peers tinted and dotted as conflicting (empty with conflicts off).
Set<int> conflictMarkCells(GameState s) => s.conflictCells;

/// A cell's background, in the design's precedence: cell → peer → same
/// number → conflict or wrong → selected.
Color cellBackground(GameState s, BoardTheme t, int i) {
  final set = s.settings;
  var bg = t.cellBg;
  if (set.hlUnit && s.peersOfSelected.contains(i)) bg = t.peerBg;
  if (set.hlSame && s.sameValueCells.contains(i)) bg = t.sameBg;
  if (conflictMarkCells(s).contains(i)) bg = t.wrongBg;
  if (wrongShownCells(s).contains(i)) bg = t.wrongBg;
  if (s.selected == i) bg = t.selBg;
  return bg;
}

/// A cell's digit colour: wrong (when shown), given, or the player's.
Color cellForeground(GameState s, BoardTheme t, int i) {
  if (s.showWrong && s.isWrong(i)) return t.wrongFg;
  return s.isGiven(i) ? t.givenFg : t.userFg;
}

/// The selection ring's colour: yellow on the hinted cell.
Color ringColor(GameState s, BoardTheme t) =>
    s.selected != null && s.selected == s.hintedCell
    ? HsColors.hintYellow
    : t.ring;

/// The board grid.
class BoardGrid extends StatelessWidget {
  /// Creates the grid for [state] in [theme] at [scale].
  const BoardGrid({
    required this.state,
    required this.theme,
    required this.scale,
    required this.onTapCell,
    super.key,
  });

  /// The game to draw.
  final GameState state;

  /// Colours.
  final BoardTheme theme;

  /// Design points to logical pixels.
  final double scale;

  /// Called with a tapped cell's index; the model's `select` toggles.
  final ValueChanged<int> onTapCell;

  @override
  Widget build(BuildContext context) {
    final layout = BoardLayout.of(state.shape);
    final grid = ScaledGrid(layout, scale);
    final radius = BorderRadius.circular(8 * scale);
    final selected = state.selected;
    // The grid names itself without being a stop of its own; its cells are
    // the nodes, tagged for #56's tap-target exemption.
    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: '${sizeWords(state.shape.label)} board',
      tagForChildren: kGridCellTag,
      child: Container(
        width: grid.gridPx,
        height: grid.gridPx,
        decoration: BoxDecoration(
          color: theme.gridBg,
          borderRadius: radius,
          boxShadow: [theme.ringShadow],
        ),
        child: ClipRRect(
          borderRadius: radius,
          child: Stack(
            children: [
              for (var i = 0; i < state.shape.cellCount; i++)
                Positioned(
                  left: grid.cellOffset(i).dx,
                  top: grid.cellOffset(i).dy,
                  width: grid.cellPx,
                  height: grid.cellPx,
                  child: RepaintBoundary(
                    child: _Cell(
                      index: i,
                      state: state,
                      theme: theme,
                      layout: layout,
                      scale: scale,
                      onTap: onTapCell,
                    ),
                  ),
                ),
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(
                    painter: GridLinesPainter(
                      lines: gridLines(grid),
                      thin: theme.thin,
                      thick: theme.thick,
                    ),
                  ),
                ),
              ),
              // Wrong and conflict marks that do not depend on colour, above the
              // lines and below the ring.
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(
                    painter: BoardMarksPainter(
                      grid: grid,
                      underlineCells: wrongShownCells(state),
                      dotCells: conflictMarkCells(state),
                      color: theme.wrongFg,
                    ),
                  ),
                ),
              ),
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(
                    painter: RingPainter(
                      ringRect: selected == null
                          ? null
                          : grid.cellOffset(selected) &
                                Size(grid.cellPx, grid.cellPx),
                      ringColor: ringColor(state, theme),
                      ringWidth: grid.thickPx,
                      ringRadius: 3 * scale,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// What a screen reader says for cell [i] of [s].
String cellLabelFor(GameState s, int i) {
  final n = s.n;
  final value = s.values[i];
  return cellLabel(
    row: i ~/ n + 1,
    col: i % n + 1,
    value: value == 0 ? null : s.shape.symbolFor(value),
    given: s.isGiven(i),
    notes: [for (final v in s.notes[i]) s.shape.symbolFor(v)],
    candidates: s.settings.autoNotes,
    wrong: s.showWrong && s.isWrong(i),
    conflict: s.conflictCells.contains(i),
    hint: s.hintedCell == i,
  );
}

class _Cell extends StatelessWidget {
  const _Cell({
    required this.index,
    required this.state,
    required this.theme,
    required this.layout,
    required this.scale,
    required this.onTap,
  });

  final int index;
  final GameState state;
  final BoardTheme theme;
  final BoardLayout layout;
  final double scale;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    final value = state.values[index];
    final big = state.settings.bigDigits;
    final notes = value == 0 ? state.notes[index] : const <int>[];
    Widget? content;
    if (value != 0) {
      content = Center(
        child: Text(
          state.shape.symbolFor(value),
          softWrap: false,
          textScaler: TextScaler.noScaling,
          style: outfit(
            layout.digitSize(bigDigits: big),
            scale: scale,
            weight: state.isGiven(index) || big
                ? FontWeight.w600
                : FontWeight.w500,
            color: cellForeground(state, theme, index),
            letterSpacingEm: -.01,
          ),
        ),
      );
    } else if (notes.isNotEmpty) {
      content = Padding(
        padding: EdgeInsets.all(1 * scale),
        child: _Notes(
          notes: notes,
          layout: layout,
          scale: scale,
          color: state.hintedCell == index ? theme.hintNoteFg : theme.noteFg,
          bigDigits: big,
        ),
      );
    }
    return Semantics(
      container: true,
      selected: state.selected == index,
      label: cellLabelFor(state, index),
      onTap: () => onTap(index),
      onTapHint: 'select',
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => onTap(index),
        child: DecoratedBox(
          key: ValueKey('cell-$index'),
          decoration: BoxDecoration(color: cellBackground(state, theme, index)),
          child: content ?? const SizedBox.expand(),
        ),
      ),
    );
  }
}

/// Pencil marks in fixed slots: value v always sits in slot v − 1 of a grid
/// `noteCols` wide, so a mark never moves when another is added.
class _Notes extends StatelessWidget {
  const _Notes({
    required this.notes,
    required this.layout,
    required this.scale,
    required this.color,
    required this.bigDigits,
  });

  final List<int> notes;
  final BoardLayout layout;
  final double scale;
  final Color color;
  final bool bigDigits;

  @override
  Widget build(BuildContext context) {
    final cols = layout.noteCols;
    final style = plexMono(
      layout.noteSize(bigDigits: bigDigits),
      scale: scale,
      color: color,
    );
    return Column(
      children: [
        for (var r = 0; r < layout.noteRows; r++)
          Expanded(
            child: Row(
              children: [
                for (var c = 0; c < cols; c++)
                  Expanded(
                    child: notes.contains(r * cols + c + 1)
                        ? Center(
                            child: Text(
                              layout.shape.symbolFor(r * cols + c + 1),
                              softWrap: false,
                              textScaler: TextScaler.noScaling,
                              style: style,
                            ),
                          )
                        : const SizedBox.shrink(),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Draws the grid lines over the cells.
class GridLinesPainter extends CustomPainter {
  /// Creates the painter.
  const GridLinesPainter({
    required this.lines,
    required this.thin,
    required this.thick,
  });

  /// Every line, from [gridLines].
  final List<GridLine> lines;

  /// Thin line colour.
  final Color thin;

  /// Thick line colour.
  final Color thick;

  @override
  void paint(Canvas canvas, Size size) {
    final thinPaint = Paint()..color = thin;
    final thickPaint = Paint()..color = thick;
    for (final line in lines) {
      canvas.drawRect(line.rect, line.thick ? thickPaint : thinPaint);
    }
  }

  @override
  bool shouldRepaint(GridLinesPainter old) =>
      old.thin != thin ||
      old.thick != thick ||
      old.lines.length != lines.length;
}

/// Marks that carry what the wrong and conflict tints carry, for a player
/// who cannot tell the colours apart (#52): a line under each wrong entry
/// shown as wrong, and a dot in the top-right corner of each conflicting
/// peer. Both scale with the board.
class BoardMarksPainter extends CustomPainter {
  /// Creates the painter.
  BoardMarksPainter({
    required this.grid,
    required this.underlineCells,
    required this.dotCells,
    required this.color,
  });

  /// The grid's geometry.
  final ScaledGrid grid;

  /// Cells to underline.
  final Set<int> underlineCells;

  /// Cells to dot.
  final Set<int> dotCells;

  /// The marks' colour: the theme's wrong digit colour.
  final Color color;

  /// The cells the last [paint] underlined.
  @visibleForTesting
  final Set<int> underlinedCells = {};

  /// The cells the last [paint] dotted.
  @visibleForTesting
  final Set<int> dottedCells = {};

  @override
  void paint(Canvas canvas, Size size) {
    underlinedCells.clear();
    dottedCells.clear();
    final cell = grid.cellPx;
    final line = Paint()
      ..color = color
      ..strokeWidth = grid.thinPx
      ..strokeCap = StrokeCap.butt;
    for (final i in underlineCells) {
      final at = grid.cellOffset(i);
      // 60 % of the cell, centred, 22 % of the cell's height above its
      // bottom: about 2 pt under the digit's baseline at every size.
      final width = (cell * .6).floorToDouble();
      final y = (at.dy + cell * .78).floorToDouble() + .5;
      final x = at.dx + (cell - width) / 2;
      canvas.drawLine(Offset(x, y), Offset(x + width, y), line);
      underlinedCells.add(i);
    }
    final dot = Paint()..color = color;
    final d = (3 * grid.scale).roundToDouble();
    final inset = (3 * grid.scale).roundToDouble();
    for (final i in dotCells) {
      final at = grid.cellOffset(i);
      canvas.drawOval(
        Rect.fromLTWH(
          (at.dx + cell - inset - d).roundToDouble(),
          (at.dy + inset).roundToDouble(),
          d,
          d,
        ),
        dot,
      );
      dottedCells.add(i);
    }
  }

  @override
  bool shouldRepaint(BoardMarksPainter old) =>
      old.color != color ||
      old.grid.cellPx != grid.cellPx ||
      !setEquals(old.underlineCells, underlineCells) ||
      !setEquals(old.dotCells, dotCells);
}

/// Draws the selection ring, above everything else in the grid.
class RingPainter extends CustomPainter {
  /// Creates the painter.
  const RingPainter({
    required this.ringRect,
    required this.ringColor,
    required this.ringWidth,
    required this.ringRadius,
  });

  /// The selected cell's rect, or null for no ring.
  final Rect? ringRect;

  /// The ring's colour.
  final Color ringColor;

  /// The ring's stroke.
  final double ringWidth;

  /// The ring's corner radius.
  final double ringRadius;

  @override
  void paint(Canvas canvas, Size size) {
    final ring = ringRect;
    if (ring == null) return;
    // The design's `box-shadow: 0 0 0 2px inset`: the stroke sits inside the
    // cell, so the rect is inset by half the stroke.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        ring.deflate(ringWidth / 2),
        Radius.circular(ringRadius),
      ),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = ringWidth
        ..color = ringColor,
    );
  }

  @override
  bool shouldRepaint(RingPainter old) =>
      old.ringRect != ringRect ||
      old.ringColor != ringColor ||
      old.ringWidth != ringWidth ||
      old.ringRadius != ringRadius;
}
