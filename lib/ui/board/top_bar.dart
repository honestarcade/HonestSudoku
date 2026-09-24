// The strip above the grid: the pause button carrying the size and
// difficulty, and the readout chips — the timer, and the strike count or ZEN.

import 'package:flutter/widgets.dart';
import 'package:honest_sudoku/game/game.dart';

import '../a11y/labels.dart';
import '../theme/tokens.dart';
import '../widgets/design_button.dart';
import 'board_layout.dart';
import 'board_styles.dart';

/// The top bar. The screen places it at `kTopBarY`.
class TopBar extends StatelessWidget {
  /// Creates the bar.
  const TopBar({
    required this.title,
    required this.pauseSemantics,
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

  /// What a screen reader says for the pause button.
  final String pauseSemantics;

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
            semanticsLabel: pauseSemantics,
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
              semanticsLabel: timeLabel(elapsedSeconds),
              style: plainChipStyle,
              scale: scale,
            ),
            SizedBox(width: 6 * scale),
          ],
          if (strikeMode == StrikeMode.zen)
            ReadoutChip(
              key: const ValueKey('chip-zen'),
              text: 'ZEN',
              semanticsLabel: strikeLabel(mistakes: mistakes, zen: true),
              liveRegion: true,
              style: zenChipStyle,
              scale: scale,
            )
          else
            ReadoutChip(
              key: const ValueKey('chip-strike'),
              text: '✕ $mistakes${limit == null ? '' : '/$limit'}',
              semanticsLabel: strikeLabel(mistakes: mistakes, limit: limit),
              liveRegion: true,
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
    required this.semanticsLabel,
    required this.style,
    required this.scale,
    this.liveRegion = false,
    super.key,
  });

  /// What it reads.
  final String text;

  /// What a screen reader says: a label, not a button.
  final String semanticsLabel;

  /// Whether a change is announced (the strike count).
  final bool liveRegion;

  /// Its colours.
  final ChipStyle style;

  /// Design points to logical pixels.
  final double scale;

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    label: semanticsLabel,
    liveRegion: liveRegion,
    excludeSemantics: true,
    child: Container(
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
    ),
  );
}
