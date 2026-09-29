// A screen's header: the ‹ button and the title, with an optional mono line.

import 'package:flutter/widgets.dart';

import '../a11y/speak.dart';
import '../board/board_styles.dart';
import '../theme/tokens.dart';
import 'design_button.dart';

/// The ‹ button's colours.
const ButtonStyleSpec backButtonSpec = ButtonStyleSpec(
  edge: HsColors.edge16,
  bg: HsColors.fill05,
  fg: HsColors.white,
);

/// The ‹ button's side, in design points.
const double kBackButtonSize = 34;

/// The ‹ glyph's size, in design points (the owner's call, 2026-09-29, #323).
const double kBackGlyphSize = 26;

// The glyph is placed by its ink, not its line box: Outfit Medium's ‹ inks
// from 0.081 to 0.403 em above the baseline while the line box's middle sits
// 0.37 em up, so centring the line box leaves it low (fontTools BoundsPen and
// hhea over assets/fonts/Outfit-Medium.ttf, 2026-09-29).
const double _backInkMidEm = .242;

/// A header.
class ScreenHeader extends StatelessWidget {
  /// Creates a header.
  const ScreenHeader({
    required this.title,
    required this.onBack,
    this.meta,
    this.keyPrefix = 'screen',
    super.key,
  });

  /// The title.
  final String title;

  /// Called by ‹.
  final VoidCallback onBack;

  /// A mono line under the title.
  final String? meta;

  /// Prefix for the back button's key: `<prefix>-back`.
  final String keyPrefix;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      SizedBox(
        width: kBackButtonSize,
        height: kBackButtonSize,
        child: DesignButton(
          key: ValueKey('$keyPrefix-back'),
          spec: backButtonSpec,
          scale: 1,
          radius: 11,
          alignment: Alignment.topCenter,
          onPressed: onBack,
          semanticsLabel: 'Back',
          // The ink's middle on the button's middle, inside the 1-pt edge.
          child: Baseline(
            baseline:
                (kBackButtonSize - 2) / 2 + _backInkMidEm * kBackGlyphSize,
            baselineType: TextBaseline.alphabetic,
            // An icon in a fixed box: system text size would push it out.
            child: Text(
              '‹',
              textScaler: TextScaler.noScaling,
              style: outfit(kBackGlyphSize, scale: 1, weight: FontWeight.w500),
            ),
          ),
        ),
      ),
      const SizedBox(width: 13),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Semantics(
              header: true,
              child: Text(
                title,
                style: outfit(19, scale: 1, weight: FontWeight.w600),
              ),
            ),
            if (meta != null) ...[
              const SizedBox(height: 6),
              // Announced when it changes (setup's summary line).
              Semantics(
                label: speak(meta!),
                liveRegion: true,
                excludeSemantics: true,
                child: Text(
                  meta!,
                  key: ValueKey('$keyPrefix-meta'),
                  style: plexMono(
                    9.5,
                    scale: 1,
                    color: HsColors.cardKicker,
                    letterSpacingEm: .16,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    ],
  );
}
