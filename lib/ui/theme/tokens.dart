// The design's colours and type, named once.
//
// Everything is transcribed from Honest Sudoku.dc.html: the brand palette
// from its brand sheet, the rest from the board template's inline styles.
// rgba values are stored 8-bit through Color.fromRGBO, as the CSS gives them.
//
// ## Contrast nudges
//
// Every text colour on the board screen and its cards reaches 4.5:1 against
// each surface it is drawn on (#52). Where a design colour fell short, it
// was replaced by the nearest passing shade: hue and saturation kept, HSL
// lightness moved in 1 % steps away from the surface (contrast.dart's
// `nudge`). Surfaces are the translucent fills composited over the grid,
// the card's two gradient stops or the screen gradient's two stops. The six
// brand swatches are untouched; a nudged shade of one is its own token.
// test/ui/theme/token_contrast_test.dart re-derives each new value from its
// design value and asserts it equal, so the arithmetic below is executed.
//
// | token          | design  | new     | ratio before → after | L (steps)          | where |
// |----------------|---------|---------|----------------------|--------------------|-------|
// | paperUserFg    | #0076F1 | #005DBE | 3.13 → 4.61 | 47.3 → 37.3 % (10) | Paper digits; worst on the selected tint |
// | paperWrongFg   | #C6483D | #A93B32 | 3.47 → 4.54 | 50.8 → 42.8 % (8)  | Paper wrong digits on the wrong tint |
// | paperNoteFg    | #6E93C4 | #3C6295 | 2.30 → 4.52 | 60.0 → 41.0 % (19) | Paper pencil marks |
// | paperHintNote  | #FFC94A | #7D5800 | 1.11 → 4.66 | 64.5 → 24.5 % (40) | Paper hinted cell's pencil marks |
// | navyNoteFg     | #7FA6D8 | #96B6DF | 3.79 → 4.57 | 67.3 → 73.3 % (6)  | Navy pencil marks on the selected tint |
// | navyWrongFg    | #FF8C7E | #FF9588 | 4.23 → 4.50 | 74.7 → 76.7 % (2)  | Navy wrong digits on the selected tint |
// | wrongRed       | #FF8C7E | #FF9588 | 4.32 → 4.60 | 74.7 → 76.7 % (2)  | strike chip, error kicker, lost kicker |
// | zenChipFg      | #00D6B4 | #00DBB8 | 4.33 → 4.54 | 42.0 → 43.0 % (1)  | the ZEN chip (teal stays the brand's) |
// | labelDim       | #5C7FB0 | #93AACB | 2.65 → 4.59 | 52.5 → 68.5 % (16) | loading phase, setup meta: gradient and card |
// | cardKicker     | #6E93C4 | #96B1D4 | 3.16 → 4.55 | 60.0 → 71.0 % (11) | card and panel kickers, on the card's tile fill |
// | muted          | #7FA6D8 | #8FB1DD | 3.98 → 4.53 | 67.3 → 71.3 % (4)  | tile labels, pause meta, ghost buttons |
// | versionText    | #4E739F | #A1B7D1 | 1.94 → 4.63 | 46.5 → 72.5 % (26) | version line, link separators (#56): gradient and panel fill |
//
// Ratios computed on 2026-09-24 with contrast.dart; the table is a record,
// the test is the check.

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

  /// The strike chip once counting, error kickers (nudged; see the header).
  static const wrongRed = Color(0xFFFF9588);

  /// Chip and soft-button text.
  static const chipFg = Color(0xFF9FC3EE);

  /// Muted labels (nudged; see the header).
  static const muted = Color(0xFF8FB1DD);

  /// Pad digits.
  static const textBright = Color(0xFFEAF2FC);

  /// Tool labels.
  static const toolFg = Color(0xFFDCE9F8);

  /// Notice body.
  static const bodyBlue = Color(0xFFD3E6FF);

  /// Card body text.
  static const bodySoft = Color(0xFFBBD2EC);

  /// Card and panel kickers (the design's #6E93C4, nudged).
  static const cardKicker = Color(0xFF96B1D4);

  // Nudged shades for text on the board (see the header).

  /// Paper: the player's digits.
  static const paperUserFg = Color(0xFF005DBE);

  /// Paper: wrong digits.
  static const paperWrongFg = Color(0xFFA93B32);

  /// Paper: pencil marks.
  static const paperNoteFg = Color(0xFF3C6295);

  /// Paper: the hinted cell's pencil marks.
  static const paperHintNote = Color(0xFF7D5800);

  /// Navy: pencil marks.
  static const navyNoteFg = Color(0xFF96B6DF);

  /// Navy: wrong digits.
  static const navyWrongFg = Color(0xFFFF9588);

  /// The ZEN chip's text.
  static const zenChipFg = Color(0xFF00DBB8);

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

  // The other screens (M4).

  /// Dim mono labels: the loading phase, the unselected difficulty meta.
  static const labelDim = Color(0xFF93AACB);

  /// Descriptions under a card's title.
  static const desc = Color(0xFF87A9D0);

  /// The version line and the MADE BY row.
  static const versionText = Color(0xFFA1B7D1);

  /// The studio screen's body text.
  static const studioText = Color(0xFFC6DAF0);

  /// Promise tick: blue.
  static const promiseBlue = Color(0xFF6FB4FF);

  /// Promise tick: violet.
  static const promiseViolet = Color(0xFFB48CFF);

  /// The reset button's confirm fill.
  static const danger = Color(0xFFE05A4E);

  /// The app mark's lower-left corner.
  static const markNavy = Color(0xFF0F3E86);

  /// The loading bar's and statistics bars' track, `rgba(255,255,255,.12)`.
  static const track = Color.fromRGBO(255, 255, 255, .12);

  /// A statistics bar's track, `rgba(255,255,255,.09)`.
  static const barTrack = Color.fromRGBO(255, 255, 255, .09);

  /// `rgba(255,255,255,.2)`
  static const edge20 = Color.fromRGBO(255, 255, 255, .2);

  /// Selected choice fill, `rgba(0,214,180,.14)`.
  static const tealFill14 = Color.fromRGBO(0, 214, 180, .14);

  /// Teal panel fill, `rgba(0,214,180,.1)`.
  static const tealFill10 = Color.fromRGBO(0, 214, 180, .1);

  /// Teal panel edge, `rgba(0,214,180,.35)`.
  static const tealEdge35 = Color.fromRGBO(0, 214, 180, .35);

  /// Teal ring, `rgba(0,214,180,.32)`.
  static const tealEdge32 = Color.fromRGBO(0, 214, 180, .32);

  /// Teal outline, `rgba(0,214,180,.4)`.
  static const tealEdge40 = Color.fromRGBO(0, 214, 180, .4);

  /// The first rule card, `rgba(0,214,180,.11)`.
  static const tealFill11 = Color.fromRGBO(0, 214, 180, .11);

  /// The first rule card's ring, `rgba(0,214,180,.34)`.
  static const tealEdge34 = Color.fromRGBO(0, 214, 180, .34);

  /// Reset button edge, `rgba(224,90,78,.5)`.
  static const dangerEdge = Color.fromRGBO(224, 90, 78, .5);

  /// Reset button fill, `rgba(224,90,78,.12)`.
  static const dangerFill = Color.fromRGBO(224, 90, 78, .12);

  /// Reset confirmation scrim, `rgba(3,14,32,.82)`.
  static const confirmScrim = Color.fromRGBO(3, 14, 32, .82);

  /// NO TRACKING chip, `rgba(0,118,241,.16)`.
  static const blueChip = Color.fromRGBO(0, 118, 241, .16);

  /// OPEN SOURCE chip, `rgba(132,72,252,.16)`.
  static const violetChip = Color.fromRGBO(132, 72, 252, .16);

  /// Link underline, `rgba(127,166,216,.4)`.
  static const linkUnderline = Color.fromRGBO(127, 166, 216, .4);

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
