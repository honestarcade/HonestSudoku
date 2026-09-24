// The pause card. The board is not drawn behind it (board_overlays.dart
// leaves it out of the tree), so pausing cannot be used to study the grid.

import 'package:flutter/widgets.dart';
import 'package:honest_sudoku/game/game.dart';

import '../a11y/labels.dart';
import '../strings.dart';
import '../theme/tokens.dart';
import 'overlay_parts.dart';

/// The pause card over its scrim.
class PauseOverlay extends StatelessWidget {
  /// Creates the card for [state].
  const PauseOverlay({
    required this.state,
    required this.scale,
    required this.onResume,
    required this.onRestart,
    required this.onNewDeal,
    required this.onRules,
    required this.onSettings,
    required this.onMainMenu,
    super.key,
  });

  /// The paused game.
  final GameState state;

  /// Design points to logical pixels.
  final double scale;

  /// Resume.
  final VoidCallback onResume;

  /// Restart this puzzle.
  final VoidCallback onRestart;

  /// New puzzle, same settings.
  final VoidCallback onNewDeal;

  /// Rules.
  final VoidCallback onRules;

  /// Settings.
  final VoidCallback onSettings;

  /// Main menu.
  final VoidCallback onMainMenu;

  @override
  Widget build(BuildContext context) {
    final s = scale;
    final gap = SizedBox(height: 9 * s);
    return OverlayFrame(
      key: const ValueKey('overlay-pause'),
      scrim: HsColors.pauseScrim,
      scale: s,
      card: Container(
        padding: EdgeInsets.all(22 * s),
        decoration: BoxDecoration(
          color: HsColors.cardNavy,
          borderRadius: BorderRadius.circular(20 * s),
          border: Border.all(color: HsColors.edge10),
          boxShadow: cardShadow(s),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            // The board screen's live region announces the title.
            ExcludeSemantics(
              child: Text(
                UiStrings.paused,
                textScaler: TextScaler.noScaling,
                style: outfit(19, scale: s, weight: FontWeight.w600),
              ),
            ),
            SizedBox(height: 8 * s),
            Semantics(
              label: pauseMetaLabel(
                state.shape.label,
                state.difficulty.label,
                state.elapsedSeconds,
              ),
              excludeSemantics: true,
              child: Text(
                state.pauseMeta,
                textScaler: TextScaler.noScaling,
                style: plexMono(
                  10,
                  scale: s,
                  color: HsColors.muted,
                  letterSpacingEm: .14,
                ),
              ),
            ),
            SizedBox(height: 14 * s),
            Container(
              padding: EdgeInsets.symmetric(
                vertical: 12 * s,
                horizontal: 13 * s,
              ),
              decoration: BoxDecoration(
                color: HsColors.fill06,
                borderRadius: BorderRadius.circular(12 * s),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Semantics(
                    label: sentenceCase(UiStrings.boardHidden),
                    excludeSemantics: true,
                    child: Text(
                      UiStrings.boardHidden,
                      textScaler: TextScaler.noScaling,
                      style: plexMono(
                        8.5,
                        scale: s,
                        color: HsColors.kicker,
                        letterSpacingEm: .16,
                      ),
                    ),
                  ),
                  SizedBox(height: 7 * s),
                  Semantics(
                    label: fillLabel(
                      filled: state.filledCount,
                      cells: state.shape.cellCount,
                      entries: state.moves,
                      mistakes: state.mistakes,
                      zen: state.settings.strikeMode == StrikeMode.zen,
                    ),
                    excludeSemantics: true,
                    child: Text(
                      state.pauseFill,
                      textScaler: TextScaler.noScaling,
                      style: outfit(
                        11.5,
                        scale: s,
                        color: HsColors.bodySoft,
                        lineHeight: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: 16 * s),
            cardButton(
              label: UiStrings.resume,
              name: 'resume',
              onPressed: onResume,
              spec: primarySpec,
              scale: s,
              padding: 15,
              fontSize: 15,
              weight: FontWeight.w600,
            ),
            gap,
            cardButton(
              label: UiStrings.restart,
              name: 'restart',
              onPressed: onRestart,
              spec: secondarySpec,
              scale: s,
              padding: 14,
              fontSize: 14,
            ),
            gap,
            cardButton(
              label: UiStrings.newDeal,
              name: 'new-deal',
              onPressed: onNewDeal,
              spec: secondarySpec,
              scale: s,
              padding: 14,
              fontSize: 14,
            ),
            gap,
            Row(
              children: [
                Expanded(
                  child: cardButton(
                    label: UiStrings.rules,
                    name: 'rules',
                    onPressed: onRules,
                    spec: softSpec,
                    scale: s,
                    padding: 13,
                    fontSize: 13,
                  ),
                ),
                SizedBox(width: 9 * s),
                Expanded(
                  child: cardButton(
                    label: UiStrings.settings,
                    name: 'settings',
                    onPressed: onSettings,
                    spec: softSpec,
                    scale: s,
                    padding: 13,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
            gap,
            cardButton(
              label: UiStrings.mainMenu,
              name: 'main-menu',
              onPressed: onMainMenu,
              spec: ghostSpec,
              scale: s,
              padding: 13,
              fontSize: 13,
            ),
          ],
        ),
      ),
    );
  }
}
