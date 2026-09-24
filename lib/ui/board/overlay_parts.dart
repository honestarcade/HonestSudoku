// Pieces the pause and game-over cards share: the scrim-and-card frame, the
// card's buttons, and a stat tile.

import 'package:flutter/widgets.dart';

import '../theme/tokens.dart';
import '../widgets/design_button.dart';
import 'board_styles.dart';

/// A full-screen scrim that swallows taps, with [card] centred on it at the
/// design's 338-point width.
class OverlayFrame extends StatelessWidget {
  /// Creates the frame.
  const OverlayFrame({
    required this.scrim,
    required this.card,
    required this.scale,
    super.key,
  });

  /// The scrim colour.
  final Color scrim;

  /// The card.
  final Widget card;

  /// Design points to logical pixels.
  final double scale;

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: () {},
    child: ColoredBox(
      color: scrim,
      child: Center(
        child: SingleChildScrollView(
          child: SizedBox(width: 338 * scale, child: card),
        ),
      ),
    ),
  );
}

/// A card button: one of the design's looks, at its padding and type size.
Widget cardButton({
  required String label,
  required String name,
  required VoidCallback onPressed,
  required ButtonStyleSpec spec,
  required double scale,
  required double padding,
  required double fontSize,
  FontWeight weight = FontWeight.w500,
}) => DesignButton(
  key: ValueKey('btn-$name'),
  spec: spec,
  scale: scale,
  radius: 13,
  padding: EdgeInsets.all(padding),
  onPressed: onPressed,
  child: Text(
    label,
    textScaler: TextScaler.noScaling,
    style: outfit(fontSize, scale: scale, weight: weight, color: spec.fg),
  ),
);

/// A stat tile: a mono key over a value.
class StatTile extends StatelessWidget {
  /// Creates a tile.
  const StatTile({
    required this.name,
    required this.label,
    required this.value,
    required this.scale,
    super.key,
  });

  /// Key suffix.
  final String name;

  /// The mono key, e.g. `TIME`.
  final String label;

  /// The value.
  final String value;

  /// Design points to logical pixels.
  final double scale;

  @override
  Widget build(BuildContext context) => Container(
    key: ValueKey('tile-$name'),
    padding: EdgeInsets.symmetric(vertical: 12 * scale, horizontal: 13 * scale),
    decoration: BoxDecoration(
      color: HsColors.fill06,
      borderRadius: BorderRadius.circular(12 * scale),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          textScaler: TextScaler.noScaling,
          style: plexMono(
            9,
            scale: scale,
            color: HsColors.muted,
            letterSpacingEm: .14,
          ),
        ),
        SizedBox(height: 7 * scale),
        Text(
          value,
          textScaler: TextScaler.noScaling,
          style: outfit(18, scale: scale, weight: FontWeight.w600),
        ),
      ],
    ),
  );
}

/// The design's primary button colours.
const ButtonStyleSpec primarySpec = ButtonStyleSpec(
  edge: Color(0x00000000),
  bg: HsColors.teal,
  fg: HsColors.deepNavy,
);

/// Restart and new-deal buttons on the pause card.
const ButtonStyleSpec secondarySpec = ButtonStyleSpec(
  edge: HsColors.edge18,
  bg: HsColors.fill05,
  fg: HsColors.white,
);

/// `Change size or difficulty` on the game-over card (a 16 % edge).
const ButtonStyleSpec changeSetupSpec = ButtonStyleSpec(
  edge: HsColors.edge16,
  bg: HsColors.fill05,
  fg: HsColors.white,
);

/// Rules and Settings on the pause card.
const ButtonStyleSpec softSpec = ButtonStyleSpec(
  edge: HsColors.edge14,
  bg: HsColors.fill04,
  fg: HsColors.chipFg,
);

/// Main menu on both cards.
const ButtonStyleSpec ghostSpec = ButtonStyleSpec(
  edge: Color(0x00000000),
  bg: Color(0x00000000),
  fg: HsColors.muted,
);

/// The cards' drop shadow, `0 24px 60px rgba(0,0,0,.55)`, scaled.
List<BoxShadow> cardShadow(double scale) => [
  BoxShadow(
    color: const Color.fromRGBO(0, 0, 0, .55),
    offset: Offset(0, 24 * scale),
    blurRadius: 60 * scale,
  ),
];
