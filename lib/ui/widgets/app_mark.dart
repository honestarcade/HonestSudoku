// The Honest Arcade mark: four rounded corners in teal, violet, blue and
// navy, drawn from the design's SVG paths (viewBox 64, stroke 6, round caps),
// with the brand sheet's small board inside where the design shows it.

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../theme/tokens.dart';
import 'app_mark_data.dart';

/// What the mark holds inside its corners.
enum MarkInterior {
  /// The outline alone: the studio's mark.
  none,

  /// The faint grid and the brand sheet's digits: the app's mark.
  board,
}

/// The mark at [size] logical points.
class AppMark extends StatelessWidget {
  /// Creates the mark. [boxed] sets it in the design's deep-navy tile.
  const AppMark({
    required this.size,
    this.boxed = false,
    this.interior = MarkInterior.none,
    super.key,
  });

  /// Width and height.
  final double size;

  /// What sits inside the corners.
  final MarkInterior interior;

  /// On a rounded deep-navy tile (About the App).
  final bool boxed;

  @override
  Widget build(BuildContext context) {
    // Decorative everywhere: the screens name the app in words.
    final mark = ExcludeSemantics(
      child: CustomPaint(
        size: Size.square(size),
        painter: AppMarkPainter(interior: interior),
      ),
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

/// Paints the four corners and, for [MarkInterior.board], the board.
class AppMarkPainter extends CustomPainter {
  /// Creates the painter.
  AppMarkPainter({
    this.interior = MarkInterior.none,
    this.cornerColors = const [
      HsColors.teal,
      HsColors.violet,
      HsColors.blue,
      HsColors.markNavy,
    ],
  });

  /// What sits inside the corners.
  final MarkInterior interior;

  /// The corners' colours, clockwise from the top left.
  final List<Color> cornerColors;

  /// How many digits the last [paint] drew.
  @visibleForTesting
  int paragraphsDrawn = 0;

  static const _thick = Color.fromRGBO(255, 255, 255, .72);
  static const _thin = Color.fromRGBO(255, 255, 255, .24);
  static const _given = HsColors.textBright;
  static const _entry = HsColors.teal;

  /// The grid's inner square, 11.5 to 52.5, and its cell pitch 41/9 (the SVG
  /// rounds it to 4.556).
  static const _origin = 11.5;
  static const _pitch = 41 / 9;

  /// Digit centres: half a cell in (the SVG's 13.78), and rows 0.15 lower
  /// (its 13.93).
  static const _colCentre = _origin + _pitch / 2;
  static const _rowCentre = _colCentre + .15;

  Size? _laidOutFor;
  List<(TextPainter, Offset)> _digits = const [];

  /// Each corner: start, the line's end, the arc's end, the last point and
  /// whether the arc turns clockwise — in the SVG's 64-unit box.
  static const _corners = [
    (Offset(3, 21), Offset(3, 10), Offset(10, 3), Offset(21, 3), true),
    (Offset(61, 21), Offset(61, 10), Offset(54, 3), Offset(43, 3), false),
    (Offset(61, 43), Offset(61, 54), Offset(54, 61), Offset(43, 61), true),
    (Offset(3, 43), Offset(3, 54), Offset(10, 61), Offset(21, 61), false),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final k = size.width / 64;
    if (interior == MarkInterior.board) _paintBoard(canvas, size, k);
    for (var i = 0; i < _corners.length; i++) {
      final (a, b, c, d, clockwise) = _corners[i];
      final color = cornerColors[i];
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

  void _paintBoard(Canvas canvas, Size size, double k) {
    paragraphsDrawn = 0;
    final thick = Paint()..color = _thick;
    final thin = Paint()..color = _thin;
    // Thin lines inside each box, then the four thick ones on each axis, as
    // filled rects at the SVG's edges.
    for (final at in const [16.06, 20.61, 29.72, 34.28, 43.39, 47.94]) {
      canvas
        ..drawRect(Rect.fromLTWH(at * k, _origin * k, .5 * k, 41 * k), thin)
        ..drawRect(Rect.fromLTWH(_origin * k, at * k, 41 * k, .5 * k), thin);
    }
    for (final at in const [10.95, 24.62, 38.28, 51.95]) {
      canvas
        ..drawRect(Rect.fromLTWH(at * k, 10.95 * k, 1.1 * k, 42.1 * k), thick)
        ..drawRect(Rect.fromLTWH(10.95 * k, at * k, 42.1 * k, 1.1 * k), thick);
    }
    if (_laidOutFor != size) _layOut(size, k);
    for (final (painter, at) in _digits) {
      painter.paint(canvas, at);
      paragraphsDrawn++;
    }
  }

  void _layOut(Size size, double k) {
    for (final (p, _) in _digits) {
      p.dispose();
    }
    TextStyle style(FontWeight weight, Color color) => TextStyle(
      fontFamily: kFontOutfit,
      fontFamilyFallback: kFontFallback,
      fontSize: 4.1 * k,
      fontWeight: weight,
      color: color,
      height: 1.0,
    );
    final given = style(FontWeight.w700, _given);
    final entry = style(FontWeight.w600, _entry);
    _digits = [
      for (final (digits, style) in [
        (kMarkGivens, given),
        (kMarkEntries, entry),
      ])
        for (final d in digits)
          () {
            final p = TextPainter(
              text: TextSpan(text: '${d.value}', style: style),
              textDirection: TextDirection.ltr,
              textScaler: TextScaler.noScaling,
            )..layout();
            final centre = Offset(
              (_colCentre + d.col * _pitch) * k,
              (_rowCentre + d.row * _pitch) * k,
            );
            return (p, centre - Offset(p.width / 2, p.height / 2));
          }(),
    ];
    _laidOutFor = size;
  }

  @override
  bool shouldRepaint(AppMarkPainter old) =>
      old.interior != interior || !listEquals(old.cornerColors, cornerColors);
}
