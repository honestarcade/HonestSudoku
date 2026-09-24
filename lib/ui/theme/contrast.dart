// WCAG contrast arithmetic, and the rule that nudges a failing design colour
// to the nearest passing shade (#52; #56 reuses it for the other screens).

import 'dart:math' as math;

import 'package:flutter/painting.dart';

/// The WCAG AA ratio for text under 18 pt, applied here to every size.
const double kTextContrast = 4.5;

double _linear(double channel) => channel <= 0.04045
    ? channel / 12.92
    : math.pow((channel + 0.055) / 1.055, 2.4).toDouble();

/// WCAG relative luminance of an opaque [c].
double luminance(Color c) =>
    0.2126 * _linear(c.r) + 0.7152 * _linear(c.g) + 0.0722 * _linear(c.b);

/// The contrast ratio of two opaque colours, 1 to 21.
double contrastRatio(Color a, Color b) {
  final la = luminance(a);
  final lb = luminance(b);
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

/// [fg] drawn over the opaque [bg], alpha-blended to an opaque colour.
Color composite(Color fg, Color bg) {
  final a = fg.a;
  double mix(double f, double b) => f * a + b * (1 - a);
  return Color.from(
    alpha: 1,
    red: mix(fg.r, bg.r),
    green: mix(fg.g, bg.g),
    blue: mix(fg.b, bg.b),
  );
}

/// The result of nudging a design colour.
typedef Nudge = ({Color color, int steps, double lightFrom, double lightTo});

/// [design] with its HSL lightness moved in 1 % steps away from the
/// background (lighter on a dark surface, darker on a light one), hue and
/// saturation kept, until it reaches [target] against every one of
/// [surfaces]; rounded to 8-bit channels at the end. Zero steps when it
/// already passes.
Nudge nudge(
  Color design,
  List<Color> surfaces, {
  double target = kTextContrast,
}) {
  final hsl = HSLColor.fromColor(design);
  final darkSurface =
      surfaces.map(luminance).reduce(math.max) < luminance(design);
  bool passes(Color c) => surfaces.every((s) => contrastRatio(c, s) >= target);
  var lightness = hsl.lightness;
  var steps = 0;
  var color = _rounded(hsl.toColor());
  while (!passes(color)) {
    steps++;
    lightness = (darkSurface ? lightness + 0.01 : lightness - 0.01).clamp(
      0.0,
      1.0,
    );
    color = _rounded(hsl.withLightness(lightness).toColor());
    if (steps > 100) {
      throw StateError('no shade of $design reaches $target on $surfaces');
    }
  }
  return (
    color: color,
    steps: steps,
    lightFrom: hsl.lightness,
    lightTo: lightness,
  );
}

Color _rounded(Color c) => Color.fromARGB(
  255,
  (c.r * 255).round(),
  (c.g * 255).round(),
  (c.b * 255).round(),
);
