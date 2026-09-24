// The Honest Arcade mark: four rounded corners in teal, violet, blue and
// navy, drawn from the design's SVG paths (viewBox 64, stroke 6, round caps).
// M5 draws the board interior inside it.

import 'package:flutter/widgets.dart';

import '../theme/tokens.dart';

/// The mark at [size] logical points.
class AppMark extends StatelessWidget {
  /// Creates the mark. [boxed] sets it in the design's deep-navy tile.
  const AppMark({required this.size, this.boxed = false, super.key});

  /// Width and height.
  final double size;

  /// On a rounded deep-navy tile (About the App).
  final bool boxed;

  @override
  Widget build(BuildContext context) {
    final mark = CustomPaint(
      size: Size.square(size),
      painter: const AppMarkPainter(),
    );
    if (!boxed) return mark;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: HsColors.deepNavy,
        borderRadius: BorderRadius.circular(size * 12 / 62),
      ),
      child: mark,
    );
  }
}

/// Paints the four corners.
class AppMarkPainter extends CustomPainter {
  /// Creates the painter.
  const AppMarkPainter();

  /// Each corner: start, the line's end, the arc's end, the last point, its
  /// colour and whether the arc turns clockwise — in the SVG's 64-unit box.
  static const _corners = [
    (
      Offset(3, 21),
      Offset(3, 10),
      Offset(10, 3),
      Offset(21, 3),
      HsColors.teal,
      true,
    ),
    (
      Offset(61, 21),
      Offset(61, 10),
      Offset(54, 3),
      Offset(43, 3),
      HsColors.violet,
      false,
    ),
    (
      Offset(61, 43),
      Offset(61, 54),
      Offset(54, 61),
      Offset(43, 61),
      HsColors.blue,
      true,
    ),
    (
      Offset(3, 43),
      Offset(3, 54),
      Offset(10, 61),
      Offset(21, 61),
      HsColors.markNavy,
      false,
    ),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final k = size.width / 64;
    for (final (a, b, c, d, color, clockwise) in _corners) {
      final path = Path()
        ..moveTo(a.dx * k, a.dy * k)
        ..lineTo(b.dx * k, b.dy * k)
        ..arcToPoint(
          Offset(c.dx * k, c.dy * k),
          radius: Radius.circular(7 * k),
          clockwise: clockwise,
        )
        ..lineTo(d.dx * k, d.dy * k);
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 6 * k
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..color = color,
      );
    }
  }

  @override
  bool shouldRepaint(AppMarkPainter old) => false;
}
