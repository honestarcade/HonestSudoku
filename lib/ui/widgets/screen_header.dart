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
        width: 34,
        height: 34,
        child: DesignButton(
          key: ValueKey('$keyPrefix-back'),
          spec: backButtonSpec,
          scale: 1,
          radius: 11,
          onPressed: onBack,
          semanticsLabel: 'Back',
          child: Text(
            '‹',
            style: outfit(16, scale: 1, weight: FontWeight.w500),
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
