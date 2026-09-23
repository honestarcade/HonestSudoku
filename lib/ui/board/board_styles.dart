// Style specs for the board's buttons: plain values, computed by pure
// functions, so a widget test can assert a colour without finding a widget.

import 'dart:ui';

/// How one design button looks.
final class ButtonStyleSpec {
  /// Creates a spec.
  const ButtonStyleSpec({
    required this.edge,
    required this.bg,
    required this.fg,
    this.opacity = 1,
  });

  /// The 1-pt border; transparent for none.
  final Color edge;

  /// The fill.
  final Color bg;

  /// The text.
  final Color fg;

  /// The whole button's opacity.
  final double opacity;

  @override
  bool operator ==(Object other) =>
      other is ButtonStyleSpec &&
      other.edge == edge &&
      other.bg == bg &&
      other.fg == fg &&
      other.opacity == opacity;

  @override
  int get hashCode => Object.hash(edge, bg, fg, opacity);

  @override
  String toString() => 'ButtonStyleSpec(edge $edge, bg $bg, fg $fg)';
}
