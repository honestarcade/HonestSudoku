// The two board themes, every value from the design's THEMES table.
//
// A theme restyles the grid and nothing else: the top bar, pad, tools,
// notice and overlays draw with fixed colours in the design, and the screen
// gradient is the same in both themes.

import 'package:flutter/rendering.dart';

/// A board colour scheme.
final class BoardTheme {
  const BoardTheme._({
    required this.key,
    required this.label,
    required this.gridBg,
    required this.gridRing,
    required this.cellBg,
    required this.thin,
    required this.thick,
    required this.givenFg,
    required this.userFg,
    required this.wrongFg,
    required this.wrongBg,
    required this.selBg,
    required this.peerBg,
    required this.sameBg,
    required this.noteFg,
    required this.ring,
  });

  /// NAVY FELT.
  static const navy = BoardTheme._(
    key: 'navy',
    label: 'NAVY FELT',
    gridBg: Color(0xFF04213F),
    gridRing: Color.fromRGBO(255, 255, 255, .14),
    cellBg: Color.fromRGBO(255, 255, 255, .045),
    thin: Color.fromRGBO(255, 255, 255, .13),
    thick: Color.fromRGBO(255, 255, 255, .42),
    givenFg: Color(0xFFEAF2FC),
    userFg: Color(0xFF00D6B4),
    wrongFg: Color(0xFFFF8C7E),
    wrongBg: Color.fromRGBO(224, 90, 78, .22),
    selBg: Color.fromRGBO(0, 214, 180, .24),
    peerBg: Color.fromRGBO(255, 255, 255, .09),
    sameBg: Color.fromRGBO(0, 118, 241, .28),
    noteFg: Color(0xFF7FA6D8),
    ring: Color(0xFF00D6B4),
  );

  /// PAPER.
  static const paper = BoardTheme._(
    key: 'paper',
    label: 'PAPER',
    gridBg: Color(0xFFF7F5EF),
    gridRing: Color.fromRGBO(0, 0, 0, .35),
    cellBg: Color(0xFFFFFFFF),
    thin: Color.fromRGBO(5, 40, 95, .22),
    thick: Color(0xFF05285F),
    givenFg: Color(0xFF16202B),
    userFg: Color(0xFF0076F1),
    wrongFg: Color(0xFFC6483D),
    wrongBg: Color.fromRGBO(198, 72, 61, .16),
    selBg: Color.fromRGBO(0, 118, 241, .18),
    peerBg: Color.fromRGBO(5, 40, 95, .07),
    sameBg: Color.fromRGBO(0, 214, 180, .3),
    noteFg: Color(0xFF6E93C4),
    ring: Color(0xFF0076F1),
  );

  /// Both themes, in the design's order.
  static const all = [navy, paper];

  /// The theme a new install uses.
  static const defaultTheme = navy;

  /// Looks a theme up by [key], falling back to [defaultTheme].
  static BoardTheme byKey(String key) =>
      all.firstWhere((t) => t.key == key, orElse: () => defaultTheme);

  /// Stored key: `navy` or `paper`.
  final String key;

  /// The settings label.
  final String label;

  /// Behind the cells.
  final Color gridBg;

  /// The 1-pt ring around the grid (`box-shadow: 0 0 0 1px`).
  final Color gridRing;

  /// An ordinary cell.
  final Color cellBg;

  /// Lines between cells.
  final Color thin;

  /// Lines between boxes and around the grid.
  final Color thick;

  /// Given numbers.
  final Color givenFg;

  /// The player's numbers.
  final Color userFg;

  /// Wrong numbers, when shown.
  final Color wrongFg;

  /// Wrong and conflicting cells.
  final Color wrongBg;

  /// The selected cell.
  final Color selBg;

  /// The selected cell's row, column and box.
  final Color peerBg;

  /// Cells holding the selected number.
  final Color sameBg;

  /// Pencil marks.
  final Color noteFg;

  /// The selection ring.
  final Color ring;

  /// The grid's outer ring as a shadow.
  BoxShadow get ringShadow => BoxShadow(color: gridRing, spreadRadius: 1);

  @override
  String toString() => 'BoardTheme($key)';
}

/// The screen background both themes share: the design's
/// `radial-gradient(120% 80% at 50% 0%, #0a3a80 0%, #05285F 52%, #031634 100%)`.
const RadialGradient kScreenGradient = RadialGradient(
  center: Alignment.topCenter,
  radius: 1,
  colors: [Color(0xFF0A3A80), Color(0xFF05285F), Color(0xFF031634)],
  stops: [0, .52, 1],
  transform: EllipseGradientTransform(1.2, .8, Offset(.5, 0)),
);

/// Stretches a circular [RadialGradient] of radius 1 (the box's shortest
/// side) into the CSS ellipse `rx% ry% at cx cy`: [rx] and [ry] are fractions
/// of the box's width and height, [center] a fractional point in the box.
final class EllipseGradientTransform extends GradientTransform {
  /// Creates the transform.
  const EllipseGradientTransform(this.rx, this.ry, this.center);

  /// Horizontal radius as a fraction of the width.
  final double rx;

  /// Vertical radius as a fraction of the height.
  final double ry;

  /// Centre as fractions of width and height.
  final Offset center;

  @override
  Matrix4 transform(Rect bounds, {TextDirection? textDirection}) {
    final side = bounds.shortestSide;
    final cx = bounds.left + bounds.width * center.dx;
    final cy = bounds.top + bounds.height * center.dy;
    return Matrix4.identity()
      ..translateByDouble(cx, cy, 0, 1)
      ..scaleByDouble(bounds.width * rx / side, bounds.height * ry / side, 1, 1)
      ..translateByDouble(-cx, -cy, 0, 1);
  }
}
