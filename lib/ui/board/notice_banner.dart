// The banner under the grid: MISTAKE, GRID FULL, CHECK and the hints, in the
// design's three colourings, with an optional action for a retry.

import 'dart:math' as math;

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
    this.maxLines = 3,
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

  /// The body's line cap before an ellipsis: 3, or 2 where the pad needs
  /// the room (#53).
  final int maxLines;

  static TextStyle _tagStyle(NoticeStyle style, double scale) =>
      plexMono(8.5, scale: scale, color: style.kicker, letterSpacingEm: .16);

  static TextStyle _bodyStyle(double scale) =>
      outfit(11.5, scale: scale, color: HsColors.bodyBlue, lineHeight: 1.45);

  static TextStyle _actionStyle(NoticeStyle style, double scale) =>
      plexMono(10, scale: scale, color: style.kicker);

  /// The banner's height in logical pixels for [notice] with [maxLines],
  /// at [scale] under [textScaler], computed before layout so the pad's
  /// place and the line cap are decided in the same frame.
  static double measureHeight({
    required Notice notice,
    required double scale,
    required TextScaler textScaler,
    int maxLines = 3,
    String? actionLabel,
  }) {
    final style = noticeStyle(notice.kind);
    double laidOut(String text, TextStyle ts, double width, int lines) {
      final p = TextPainter(
        text: TextSpan(text: text, style: ts),
        textDirection: TextDirection.ltr,
        textScaler: textScaler,
        maxLines: lines,
        ellipsis: '\u2026',
      )..layout(maxWidth: width);
      final h = p.height;
      p.dispose();
      return h;
    }

    double actionWidth = 0;
    double actionHeight = 0;
    if (actionLabel != null) {
      final p = TextPainter(
        text: TextSpan(text: actionLabel, style: _actionStyle(style, scale)),
        textDirection: TextDirection.ltr,
        textScaler: textScaler,
        maxLines: 1,
      )..layout();
      actionWidth = p.width + 16 * scale + 2 + 10 * scale;
      actionHeight = p.height + 10 * scale + 2;
      p.dispose();
    }
    // Container: horizontal padding 13, the 1-px border on each side.
    final width = kPadWidth * scale - 26 * scale - 2 - actionWidth;
    final text =
        laidOut(notice.tag, _tagStyle(style, scale), width, 1) +
        7 * scale +
        laidOut(notice.body, _bodyStyle(scale), width, maxLines);
    return math.max(text, actionHeight) + 22 * scale + 2;
  }

  @override
  Widget build(BuildContext context) {
    final style = noticeStyle(notice.kind);
    final text = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          notice.tag,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: _tagStyle(style, scale),
        ),
        SizedBox(height: 7 * scale),
        Text(
          notice.body,
          maxLines: maxLines,
          overflow: TextOverflow.ellipsis,
          style: _bodyStyle(scale),
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
                        maxLines: 1,
                        softWrap: false,
                        style: _actionStyle(style, scale),
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
