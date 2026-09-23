// Style specs for the board's buttons: plain values, computed by pure
// functions, so a widget test can assert a colour without finding a widget.

import 'dart:ui';

import 'package:honest_sudoku/engine/engine.dart' show BannerKind;

import '../theme/tokens.dart';

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

/// A pad key: yellow in note mode, faded once all n of its value are placed.
ButtonStyleSpec padKeyStyle({required bool noteMode, required bool done}) =>
    ButtonStyleSpec(
      edge: noteMode ? HsColors.noteKeyEdge : HsColors.edge14,
      bg: noteMode ? HsColors.noteKeyBg : HsColors.fill07,
      fg: noteMode ? HsColors.hintYellow : HsColors.textBright,
      opacity: done ? .32 : 1,
    );

/// The pad's erase key on 9×9.
const ButtonStyleSpec eraseKeyStyle = ButtonStyleSpec(
  edge: HsColors.edge14,
  bg: HsColors.fill04,
  fg: HsColors.chipFg,
);

/// A tool: yellow while active (notes in note mode).
ButtonStyleSpec toolStyle({required bool active}) => ButtonStyleSpec(
  edge: active ? HsColors.toolActiveEdge : HsColors.edge14,
  bg: active ? HsColors.toolActiveBg : HsColors.fill06,
  fg: active ? HsColors.hintYellow : HsColors.toolFg,
);

/// A notice banner's colours.
typedef NoticeStyle = ({Color bg, Color ring, Color kicker});

/// The banner's colours by kind.
NoticeStyle noticeStyle(BannerKind kind) => switch (kind) {
  BannerKind.error => (
    bg: HsColors.noticeErrorBg,
    ring: HsColors.noticeErrorRing,
    kicker: HsColors.wrongRed,
  ),
  BannerKind.ok => (
    bg: HsColors.noticeOkBg,
    ring: HsColors.noticeOkRing,
    kicker: HsColors.teal,
  ),
  BannerKind.hint => (
    bg: HsColors.noticeHintBg,
    ring: HsColors.noticeHintRing,
    kicker: HsColors.hintYellow,
  ),
};

/// A readout chip's colours.
typedef ChipStyle = ({Color bg, Color fg});

/// The ordinary chip: timer, and the strike chip before any mistake.
const ChipStyle plainChipStyle = (bg: HsColors.fill07, fg: HsColors.chipFg);

/// The strike chip: red once a mistake is counted.
ChipStyle strikeChipStyle(int mistakes) => mistakes > 0
    ? (bg: HsColors.strikeBg, fg: HsColors.wrongRed)
    : plainChipStyle;

/// The Zen chip.
const ChipStyle zenChipStyle = (bg: HsColors.zenBg, fg: HsColors.teal);
