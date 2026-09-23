// A game as the store keeps it: everything needed to put the player back
// exactly where they were, board included, so a restore never regenerates.

import 'package:honest_sudoku/engine/engine.dart';

import 'game_settings.dart';
import 'game_state.dart';
import 'lists.dart';
import 'snapshot.dart';

/// A saved game, as plain values.
final class SavedGame {
  /// Creates a saved game.
  SavedGame({
    required this.shape,
    required this.difficulty,
    required this.seed,
    required this.solution,
    required this.givens,
    required this.values,
    required this.notes,
    required this.mistakes,
    required this.moves,
    required this.elapsedSeconds,
    required this.strikeMode,
    required this.announce,
    this.history = const [],
    this.future = const [],
    this.revealed = false,
    this.won = false,
    this.lost = false,
    this.noteMode = false,
    this.selected,
  });

  /// From a game in progress.
  factory SavedGame.fromState(GameState s) => SavedGame(
    shape: s.shape,
    difficulty: s.difficulty,
    seed: s.puzzle.seed,
    solution: s.solution,
    givens: s.puzzle.givens,
    values: s.values,
    notes: s.notes,
    mistakes: s.mistakes,
    moves: s.moves,
    elapsedSeconds: s.elapsedSeconds,
    strikeMode: s.settings.strikeMode,
    announce: s.settings.announce,
    history: s.history,
    future: s.future,
    revealed: s.revealed,
    won: s.won,
    lost: s.lost,
    noteMode: s.noteMode,
    selected: s.selected,
  );

  /// Size.
  final GridShape shape;

  /// Band.
  final Difficulty difficulty;

  /// Seed.
  final int seed;

  /// The full solution.
  final List<int> solution;

  /// Which cells are given.
  final List<bool> givens;

  /// Entries.
  final List<int> values;

  /// Pencil marks.
  final List<List<int>> notes;

  /// Mistakes.
  final int mistakes;

  /// Moves.
  final int moves;

  /// Played time.
  final int elapsedSeconds;

  /// The game's strike mode.
  final StrikeMode strikeMode;

  /// The game's announce mode.
  final AnnounceMode announce;

  /// Undo steps.
  final List<Snapshot> history;

  /// Redo steps.
  final List<Snapshot> future;

  /// Wrong entries revealed.
  final bool revealed;

  /// Won.
  final bool won;

  /// Lost.
  final bool lost;

  /// Note mode.
  final bool noteMode;

  /// Selected cell.
  final int? selected;

  /// The game again, paused, with [toggles]' board settings and this game's
  /// own strike and announce modes. Throws [ArgumentError] when the saved
  /// values do not fit together.
  GameState toState(GameSettings toggles) => GameState(
    puzzle: Puzzle(
      shape: shape,
      seed: seed,
      solution: solution,
      givens: givens,
      givenCount: givens.where((g) => g).length,
      difficulty: difficulty,
    ),
    settings: toggles.copyWith(strikeMode: strikeMode, announce: announce),
    values: values,
    notes: notes,
    selected: selected,
    mistakes: mistakes,
    moves: moves,
    elapsedSeconds: elapsedSeconds,
    won: won,
    lost: lost,
    revealed: revealed,
    noteMode: noteMode,
    paused: !(won || lost),
    history: history,
    future: future,
  );

  @override
  bool operator ==(Object other) =>
      other is SavedGame &&
      other.shape == shape &&
      other.difficulty == difficulty &&
      other.seed == seed &&
      listEquals(other.solution, solution) &&
      listEquals(other.givens, givens) &&
      listEquals(other.values, values) &&
      deepListEquals(other.notes, notes) &&
      other.mistakes == mistakes &&
      other.moves == moves &&
      other.elapsedSeconds == elapsedSeconds &&
      other.strikeMode == strikeMode &&
      other.announce == announce &&
      listEquals(other.history, history) &&
      listEquals(other.future, future) &&
      other.revealed == revealed &&
      other.won == won &&
      other.lost == lost &&
      other.noteMode == noteMode &&
      other.selected == selected;

  @override
  int get hashCode => Object.hash(
    shape,
    difficulty,
    seed,
    Object.hashAll(values),
    mistakes,
    moves,
    elapsedSeconds,
    selected,
  );
}
