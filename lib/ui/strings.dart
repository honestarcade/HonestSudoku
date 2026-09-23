// The board screen's own copy, verbatim from the design file's templates
// (the pause card, the win and out-of-strikes cards) and the generation
// failure messages the plan wrote for the loading path.

import 'package:honest_sudoku/engine/engine.dart' show GenerationPhase;

/// Board-screen copy.
abstract final class UiStrings {
  /// Pause card title.
  static const paused = 'Paused';

  /// Pause card panel kicker.
  static const boardHidden = 'BOARD HIDDEN WHILE PAUSED';

  /// Pause card primary.
  static const resume = 'Resume';

  /// Pause card: same board again.
  static const restart = 'Restart this puzzle';

  /// Pause card: new board, same settings.
  static const newDeal = 'New puzzle, same settings';

  /// Pause card: how to play.
  static const rules = 'Rules';

  /// Pause card: settings.
  static const settings = 'Settings';

  /// Both cards: back to the menu.
  static const mainMenu = 'Main menu';

  /// Won card kicker.
  static const wonTag = 'PUZZLE SOLVED';

  /// Won card title.
  static const wonTitle = 'Grid complete';

  /// Won card body.
  static String wonBody(String size, String difficulty) =>
      'Every row, column and box checks out. Recorded under $size '
      '$difficulty.';

  /// Won card primary.
  static const nextPuzzle = 'Next puzzle';

  /// Lost card kicker.
  static const lostTag = 'OUT OF STRIKES';

  /// Lost card title.
  static const lostTitle = 'That was the last strike';

  /// Lost card body.
  static String lostBody(int limit) =>
      'You set a limit of $limit. The puzzle is still here if you undo — or '
      'take a fresh one.';

  /// Lost card primary.
  static const newPuzzle = 'New puzzle';

  /// Both game-over cards: back to setup.
  static const changeSetup = 'Change size or difficulty';

  /// Tile keys.
  static const time = 'TIME';

  /// Tile key.
  static const entries = 'ENTRIES';

  /// Tile key.
  static const mistakes = 'MISTAKES';

  /// Tile key.
  static const streak = 'STREAK';

  /// Tile key.
  static const filled = 'FILLED';

  /// Tile key.
  static const difficulty = 'DIFFICULTY';

  /// Generation failure kicker.
  static const generationFailed = 'GENERATION FAILED';

  /// Generation cancelled kicker.
  static const generationCancelled = 'GENERATION CANCELLED';

  /// The time ceiling passed.
  static const failedTimeout = "Couldn't build a board in time. Try again.";

  /// Attempts ran out.
  static const failedAttempts =
      "Couldn't find a board for this seed. Try again.";

  /// Anything else.
  static const failedUnexpected =
      'Something went wrong building the board. Try again.';

  /// The player backed out.
  static const cancelled = 'Board building was cancelled.';

  /// The retry action.
  static const tryAgain = 'TRY AGAIN';

  /// The loading label for [phase]: the design's `loadLabel`.
  static String phaseLabel(GenerationPhase phase) => switch (phase) {
    GenerationPhase.generating => 'GENERATING',
    GenerationPhase.carving => 'CARVING GIVENS',
    GenerationPhase.ready => 'READY',
  };
}
