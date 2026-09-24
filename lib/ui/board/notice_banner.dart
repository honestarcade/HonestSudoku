// The banner under the grid: MISTAKE, GRID FULL, CHECK and the hints, in the
// design's three colourings, with an optional action for a retry.

import 'package:flutter/widgets.dart';
import 'package:honest_sudoku/game/game.dart';

import '../a11y/labels.dart';
import '../theme/tokens.dart';
import 'board_layout.dart';
import 'board_styles.dart';

/// A small button at the banner's right.
final class NoticeAction {
  /// Creates an action.
  const NoticeAction(this.label, this.onPressed);

  /// What it says, e.g. `TRY AGAIN`.
  final String label;

  /// What it does.
  final VoidCallback onPressed;
}

/// The notice banner. The screen places it at `noticeY` and builds it only
/// while there is a notice.
class NoticeBanner extends StatelessWidget {
  /// Creates the banner for [notice].
  const NoticeBanner({
    required this.notice,
    required this.scale,
    this.action,
    this.labelled = true,
    super.key,
  });

  /// What to say.
  final Notice notice;

  /// Design points to logical pixels.
  final double scale;

  /// An optional action.
  final NoticeAction? action;

  /// Whether the banner carries its own spoken label. The board says no:
  /// its banner slot is a persistent live region that speaks for it, so a
  /// new notice is a label change TalkBack announces (#51).
  final bool labelled;

  @override
  Widget build(BuildContext context) {
    final style = noticeStyle(notice.kind);
    final text = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          notice.tag,
          textScaler: TextScaler.noScaling,
          style: plexMono(
            8.5,
            scale: scale,
            color: style.kicker,
            letterSpacingEm: .16,
          ),
        ),
        SizedBox(height: 7 * scale),
        Text(
          notice.body,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          textScaler: TextScaler.noScaling,
          style: outfit(
            11.5,
            scale: scale,
            color: HsColors.bodyBlue,
            lineHeight: 1.45,
          ),
        ),
      ],
    );
    final a = action;
    final spoken = Semantics(
      container: labelled,
      label: labelled ? noticeLabel(notice.tag, notice.body) : null,
      excludeSemantics: true,
      child: text,
    );
    return Container(
      key: const ValueKey('notice'),
      width: kPadWidth * scale,
      padding: EdgeInsets.symmetric(
        vertical: 11 * scale,
        horizontal: 13 * scale,
      ),
      decoration: BoxDecoration(
        color: style.bg,
        borderRadius: BorderRadius.circular(12 * scale),
        // The design's `box-shadow: 0 0 0 1px … inset`.
        border: Border.all(color: style.ring),
      ),
      child: a == null
          ? spoken
          : Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: spoken),
                SizedBox(width: 10 * scale),
                Semantics(
                  container: true,
                  button: true,
                  label: sentenceCase(a.label),
                  onTap: a.onPressed,
                  excludeSemantics: true,
                  child: GestureDetector(
                    key: const ValueKey('notice-action'),
                    behavior: HitTestBehavior.opaque,
                    excludeFromSemantics: true,
                    onTap: a.onPressed,
                    child: Container(
                      padding: EdgeInsets.symmetric(
                        vertical: 5 * scale,
                        horizontal: 8 * scale,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8 * scale),
                        border: Border.all(color: style.kicker),
                      ),
                      child: Text(
                        a.label,
                        textScaler: TextScaler.noScaling,
                        style: plexMono(10, scale: scale, color: style.kicker),
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
