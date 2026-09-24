// The design's colours and type, named once.
//
// Everything is transcribed from Honest Sudoku.dc.html: the brand palette
// from its brand sheet, the rest from the board template's inline styles.
// rgba values are stored 8-bit through Color.fromRGBO, as the CSS gives them.

import 'package:flutter/painting.dart';

/// The design's colours.
abstract final class HsColors {
  // The brand palette.

  /// Teal, the brand accent.
  static const teal = Color(0xFF00D6B4);

  /// Blue.
  static const blue = Color(0xFF0076F1);

  /// Violet.
  static const violet = Color(0xFF8448FC);

  /// Navy, the app's ground.
  static const navy = Color(0xFF05285F);

  /// Red.
  static const red = Color(0xFFC6483D);

  /// Paper.
  static const paper = Color(0xFFF7F5EF);

  // Recurring colours on the board screen.

  /// Hinted cell, note-mode keys and the active notes tool.
  static const hintYellow = Color(0xFFFFC94A);

  /// Wrong entries on navy and the strike chip once counting.
  static const wrongRed = Color(0xFFFF8C7E);

  /// Chip and soft-button text.
  static const chipFg = Color(0xFF9FC3EE);

  /// Muted labels.
  static const muted = Color(0xFF7FA6D8);

  /// Pad digits.
  static const textBright = Color(0xFFEAF2FC);

  /// Tool labels.
  static const toolFg = Color(0xFFDCE9F8);

  /// Notice body.
  static const bodyBlue = Color(0xFFD3E6FF);

  /// Card body text.
  static const bodySoft = Color(0xFFBBD2EC);

  /// Pause-card and panel kicker.
  static const kicker = Color(0xFF6E93C4);

  /// Card surface.
  static const cardNavy = Color(0xFF0B3670);

  /// Text on teal.
  static const deepNavy = Color(0xFF04213F);

  /// White.
  static const white = Color(0xFFFFFFFF);

  // Translucent fills and edges.

  /// `rgba(255,255,255,.18)`
  static const edge18 = Color.fromRGBO(255, 255, 255, .18);

  /// `rgba(255,255,255,.16)`
  static const edge16 = Color.fromRGBO(255, 255, 255, .16);

  /// `rgba(255,255,255,.14)`
  static const edge14 = Color.fromRGBO(255, 255, 255, .14);

  /// `rgba(255,255,255,.10)`
  static const edge10 = Color.fromRGBO(255, 255, 255, .10);

  /// `rgba(255,255,255,.07)`
  static const fill07 = Color.fromRGBO(255, 255, 255, .07);

  /// `rgba(255,255,255,.06)`
  static const fill06 = Color.fromRGBO(255, 255, 255, .06);

  /// `rgba(255,255,255,.05)`
  static const fill05 = Color.fromRGBO(255, 255, 255, .05);

  /// `rgba(255,255,255,.04)`
  static const fill04 = Color.fromRGBO(255, 255, 255, .04);

  /// Note-mode key edge, `rgba(255,201,74,.4)`.
  static const noteKeyEdge = Color.fromRGBO(255, 201, 74, .4);

  /// Note-mode key fill, `rgba(255,201,74,.1)`.
  static const noteKeyBg = Color.fromRGBO(255, 201, 74, .1);

  /// Active tool edge, `rgba(255,201,74,.45)`.
  static const toolActiveEdge = Color.fromRGBO(255, 201, 74, .45);

  /// Active tool fill, `rgba(255,201,74,.14)`.
  static const toolActiveBg = Color.fromRGBO(255, 201, 74, .14);

  /// Strike chip once counting, `rgba(224,90,78,.2)`.
  static const strikeBg = Color.fromRGBO(224, 90, 78, .2);

  /// Zen chip, `rgba(0,214,180,.16)`.
  static const zenBg = Color.fromRGBO(0, 214, 180, .16);

  /// Error notice fill, `rgba(224,90,78,.14)`.
  static const noticeErrorBg = Color.fromRGBO(224, 90, 78, .14);

  /// Error notice ring, `rgba(224,90,78,.4)`.
  static const noticeErrorRing = Color.fromRGBO(224, 90, 78, .4);

  /// Ok notice fill, `rgba(0,214,180,.12)`.
  static const noticeOkBg = Color.fromRGBO(0, 214, 180, .12);

  /// Ok notice ring, `rgba(0,214,180,.34)`.
  static const noticeOkRing = Color.fromRGBO(0, 214, 180, .34);

  /// Hint notice fill, `rgba(255,201,74,.12)`.
  static const noticeHintBg = Color.fromRGBO(255, 201, 74, .12);

  /// Hint notice ring, `rgba(255,201,74,.36)`.
  static const noticeHintRing = Color.fromRGBO(255, 201, 74, .36);

  /// Pause scrim, `rgba(3,14,32,.86)`.
  static const pauseScrim = Color.fromRGBO(3, 14, 32, .86);

  /// Game-over scrim, `rgba(3,14,32,.88)`.
  static const overScrim = Color.fromRGBO(3, 14, 32, .88);

  /// Won card ring, `rgba(0,214,180,.3)`.
  static const wonRing = Color.fromRGBO(0, 214, 180, .3);

  /// Lost card ring, `rgba(224,90,78,.35)`.
  static const lostRing = Color.fromRGBO(224, 90, 78, .35);
}

/// The design's sans-serif (bundled in M5; until then the system font).
const String kFontOutfit = 'Outfit';

/// The design's monospace.
const String kFontMono = 'IBM Plex Mono';

/// Where a glyph the families lack comes from.
const List<String> kFontFallback = ['Roboto', 'sans-serif'];

/// A text style in the design's sans-serif at [size] design points times
/// [scale]. [letterSpacingEm] and [lineHeight] are the CSS values.
TextStyle outfit(
  double size, {
  required double scale,
  FontWeight weight = FontWeight.w400,
  Color color = HsColors.white,
  double letterSpacingEm = 0,
  double lineHeight = 1.0,
}) => TextStyle(
  fontFamily: kFontOutfit,
  fontFamilyFallback: kFontFallback,
  fontSize: size * scale,
  fontWeight: weight,
  color: color,
  letterSpacing: letterSpacingEm * size * scale,
  height: lineHeight,
  leadingDistribution: TextLeadingDistribution.even,
);

/// The design's monospace, as [outfit].
TextStyle plexMono(
  double size, {
  required double scale,
  FontWeight weight = FontWeight.w500,
  Color color = HsColors.white,
  double letterSpacingEm = 0,
  double lineHeight = 1.0,
}) => TextStyle(
  fontFamily: kFontMono,
  fontFamilyFallback: const ['monospace', ...kFontFallback],
  fontSize: size * scale,
  fontWeight: weight,
  color: color,
  letterSpacing: letterSpacingEm * size * scale,
  height: lineHeight,
  leadingDistribution: TextLeadingDistribution.even,
);
