// The strip above the grid: the pause button carrying the size and
// difficulty, and the readout chips — the timer, and the strike count or ZEN.

import 'package:flutter/widgets.dart';
import 'package:honest_sudoku/game/game.dart';

import '../theme/tokens.dart';
import '../widgets/design_button.dart';
import 'board_layout.dart';
import 'board_styles.dart';

/// The top bar. The screen places it at `kTopBarY`.
class TopBar extends StatelessWidget {
  /// Creates the bar.
  const TopBar({
    required this.title,
    required this.elapsedSeconds,
    required this.mistakes,
    required this.strikeMode,
    required this.showTimer,
    required this.isOver,
    required this.scale,
    required this.onPause,
    super.key,
  });

  /// `<size> · <difficulty>`.
  final String title;

  /// Played time.
  final int elapsedSeconds;

  /// Mistakes counted.
  final int mistakes;

  /// Decides ZEN or `✕ n[/limit]`.
  final StrikeMode strikeMode;

  /// Whether the timer chip shows.
  final bool showTimer;

  /// The game is won or lost: the pause button does nothing.
  final bool isOver;

  /// Design points to logical pixels.
  final double scale;

  /// The pause button was tapped.
  final VoidCallback onPause;

  @override
  Widget build(BuildContext context) {
    final limit = strikeMode.limit;
    return Container(
      width: kFrameWidth * scale,
      height: kTopBarHeight * scale,
      padding: EdgeInsets.symmetric(horizontal: 14 * scale),
      child: Row(
        children: [
          DesignButton(
            key: const ValueKey('pause-button'),
            spec: const ButtonStyleSpec(
              edge: HsColors.edge14,
              bg: HsColors.fill06,
              fg: HsColors.white,
            ),
            scale: scale,
            radius: 10,
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 11),
            onPressed: isOver ? null : onPause,
            child: Text(
              '❚❚ $title',
              softWrap: false,
              textScaler: TextScaler.noScaling,
              style: outfit(11.5, scale: scale, weight: FontWeight.w500),
            ),
          ),
          const Spacer(),
          if (showTimer) ...[
            ReadoutChip(
              key: const ValueKey('chip-timer'),
              text: fmt(elapsedSeconds),
              style: plainChipStyle,
              scale: scale,
            ),
            SizedBox(width: 6 * scale),
          ],
          if (strikeMode == StrikeMode.zen)
            ReadoutChip(
              key: const ValueKey('chip-zen'),
              text: 'ZEN',
              style: zenChipStyle,
              scale: scale,
            )
          else
            ReadoutChip(
              key: const ValueKey('chip-strike'),
              text: '✕ $mistakes${limit == null ? '' : '/$limit'}',
              style: strikeChipStyle(mistakes),
              scale: scale,
            ),
        ],
      ),
    );
  }
}

/// One readout chip.
class ReadoutChip extends StatelessWidget {
  /// Creates a chip.
  const ReadoutChip({
    required this.text,
    required this.style,
    required this.scale,
    super.key,
  });

  /// What it reads.
  final String text;

  /// Its colours.
  final ChipStyle style;

  /// Design points to logical pixels.
  final double scale;

  @override
  Widget build(BuildContext context) => Container(
    padding: EdgeInsets.symmetric(vertical: 7 * scale, horizontal: 9 * scale),
    decoration: BoxDecoration(
      color: style.bg,
      borderRadius: BorderRadius.circular(9 * scale),
    ),
    child: Text(
      text,
      softWrap: false,
      textScaler: TextScaler.noScaling,
      style: plexMono(10, scale: scale, color: style.fg),
    ),
  );
}
