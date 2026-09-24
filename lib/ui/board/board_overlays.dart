// Which of the board, the pause card and the game-over card is showing.
//
// Both cards replace the board rather than cover it: the board subtree is not
// built, so no digit is on screen behind them (the design draws the
// game-over card over a live board; the plan hides it too).

import 'package:flutter/widgets.dart';
import 'package:honest_sudoku/game/game.dart';

import 'game_over_overlay.dart';
import 'pause_overlay.dart';

/// Chooses between [board] and the two cards. A finished game shows the
/// game-over card whether or not it is paused.
class BoardOverlays extends StatelessWidget {
  /// Creates the selector.
  const BoardOverlays({
    required this.state,
    required this.board,
    required this.stats,
    required this.scale,
    required this.onResume,
    required this.onRestart,
    required this.onNewDeal,
    required this.onRules,
    required this.onSettings,
    required this.onMainMenu,
    required this.onChangeSetup,
    super.key,
  });

  /// The game.
  final GameState state;

  /// Builds the board, only when it shows.
  final WidgetBuilder board;

  /// Where the win card's streak comes from.
  final StatsSource stats;

  /// Design points to logical pixels.
  final double scale;

  /// Resume.
  final VoidCallback onResume;

  /// Restart this puzzle.
  final VoidCallback onRestart;

  /// New puzzle, same settings / Next puzzle / New puzzle.
  final VoidCallback onNewDeal;

  /// Rules.
  final VoidCallback onRules;

  /// Settings.
  final VoidCallback onSettings;

  /// Main menu.
  final VoidCallback onMainMenu;

  /// Change size or difficulty.
  final VoidCallback onChangeSetup;

  @override
  Widget build(BuildContext context) {
    if (state.won || state.lost) {
      return GameOverOverlay(
        // A new game's win rises again.
        key: ValueKey('over-${state.won}-${state.puzzle.seed}'),
        state: state,
        stats: stats,
        scale: scale,
        onNewDeal: onNewDeal,
        onChangeSetup: onChangeSetup,
        onMainMenu: onMainMenu,
      );
    }
    if (state.paused) {
      return PauseOverlay(
        state: state,
        scale: scale,
        onResume: onResume,
        onRestart: onRestart,
        onNewDeal: onNewDeal,
        onRules: onRules,
        onSettings: onSettings,
        onMainMenu: onMainMenu,
      );
    }
    return board(context);
  }
}
