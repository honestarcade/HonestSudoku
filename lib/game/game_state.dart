// The rules of play as an immutable value: every verb returns a new state,
// or this one unchanged when it does not apply.
//
// The rules are the design's prototype (`place`, `erase`, `undo`, `redo`,
// `check`, `hint`, `restart` in Honest Sudoku.dc.html), with the divergences
// the plan recorded: a pencil-mark toggle on a filled cell does nothing, and
// Zen's grid-full message does not point at red cells. Widgets render these
// states and forward taps; they hold no rule logic.

import 'package:honest_sudoku/engine/engine.dart';

import 'game_settings.dart';
import 'lists.dart';
import 'notice.dart';

/// One game in progress.
final class GameState {
  /// A state from its parts; validates lengths and ranges.
  GameState({
    required this.puzzle,
    required this.settings,
    required List<int> values,
    required List<List<int>> notes,
    this.selected,
    this.mistakes = 0,
    this.moves = 0,
    this.elapsedSeconds = 0,
    this.won = false,
    this.lost = false,
    this.revealed = false,
    this.noteMode = false,
    this.notice,
  }) : values = List.unmodifiable(values),
       notes = List.unmodifiable([
         for (final list in notes) List<int>.unmodifiable(list),
       ]) {
    if (puzzle.difficulty == null) {
      throw ArgumentError.value(puzzle, 'puzzle', 'must be graded');
    }
    checkValues(puzzle.shape, this.values);
    if (this.notes.length != puzzle.shape.cellCount) {
      throw ArgumentError.value(this.notes.length, 'notes', 'wrong length');
    }
    final s = selected;
    if (s != null) checkIndex(puzzle.shape, s);
  }

  /// A fresh game on [puzzle]: givens filled, nothing selected, and every
  /// empty cell's candidates noted when [settings] asks for auto-notes.
  factory GameState.start(
    Puzzle puzzle, [
    GameSettings settings = const GameSettings(),
  ]) {
    final state = GameState(
      puzzle: puzzle,
      settings: settings,
      values: puzzle.startingValues(),
      notes: List.generate(puzzle.shape.cellCount, (_) => const <int>[]),
    );
    return settings.autoNotes ? state._autoNoted() : state;
  }

  /// The board being played.
  final Puzzle puzzle;

  /// How the player wants to play.
  final GameSettings settings;

  /// Current entries, givens included; 0 for empty.
  final List<int> values;

  /// Pencil marks per cell, ascending.
  final List<List<int>> notes;

  /// The selected cell, if any.
  final int? selected;

  /// Wrong entries counted so far.
  final int mistakes;

  /// Values placed (clears and pencil marks do not count).
  final int moves;

  /// Played time.
  final int elapsedSeconds;

  /// Every cell filled and correct.
  final bool won;

  /// The strike limit was reached.
  final bool lost;

  /// Wrong entries are shown whatever the announce mode (after Check, or a
  /// full grid).
  final bool revealed;

  /// The pad leaves pencil marks instead of values.
  final bool noteMode;

  /// The banner under the grid, if any.
  final Notice? notice;

  /// The grid's shape.
  GridShape get shape => puzzle.shape;

  /// The grid's side length.
  int get n => puzzle.shape.n;

  /// The solution.
  List<int> get solution => puzzle.solution;

  /// The band the puzzle was generated to.
  Difficulty get difficulty => puzzle.difficulty!;

  /// Pencil marks are what the pad leaves: note mode on and auto-notes off.
  bool get effectiveNoteMode => noteMode && !settings.autoNotes;

  /// Whether wrong entries are tinted: never in Zen; otherwise when mistakes
  /// are announced at once, or once they have been revealed.
  bool get showWrong =>
      settings.strikeMode != StrikeMode.zen &&
      (settings.announce == AnnounceMode.now || revealed);

  /// True for a given cell.
  bool isGiven(int i) => puzzle.givens[i];

  /// The raw comparison: filled and not the solution. The renderer gates it
  /// with [showWrong].
  bool isWrong(int i) => values[i] != 0 && values[i] != puzzle.solution[i];

  /// No cell is empty.
  bool get isFull => !values.contains(0);

  /// Cells holding a value.
  int get filledCount => values.where((v) => v != 0).length;

  /// Cells holding [value].
  int countOf(int value) => values.where((v) => v == value).length;

  /// The selected cell's peers (row, column, box), whatever the settings.
  Set<int> get peersOfSelected {
    final s = selected;
    return s == null ? const {} : unitsOf(shape, s).toSet();
  }

  /// Cells holding the selected cell's value, not counting the selected cell.
  Set<int> get sameValueCells {
    final s = selected;
    if (s == null || values[s] == 0) return const {};
    final v = values[s];
    return {
      for (var i = 0; i < values.length; i++)
        if (i != s && values[i] == v) i,
    };
  }

  /// Peers holding the selected cell's value, when conflicts are shown.
  Set<int> get conflictCells {
    final s = selected;
    if (!settings.conflicts || s == null || values[s] == 0) return const {};
    return {
      for (final p in unitsOf(shape, s))
        if (values[p] == values[s]) p,
    };
  }

  /// `<size> · <difficulty>`, as the top bar reads.
  String get boardTitle => '${shape.label} · ${difficulty.label}';

  /// Selects [index], or deselects it when it is already selected. Leaves the
  /// notice alone.
  GameState select(int index) {
    checkIndex(shape, index);
    return selected == index
        ? copyWith(clearSelected: true)
        : copyWith(selected: index);
  }

  /// Flips note mode. Allowed while auto-notes is on (the pad then still
  /// places values; see [effectiveNoteMode]) and after the game is over.
  GameState toggleNoteMode() => copyWith(noteMode: !noteMode);

  /// Applies [settings] mid-game. Turning auto-notes on fills every empty
  /// cell's candidates at once; turning it off keeps them as hand notes.
  GameState withSettings(GameSettings settings) {
    final next = copyWith(settings: settings);
    return settings.autoNotes ? next._autoNoted() : next;
  }

  /// Places [value] in the selected cell, or toggles it as a pencil mark in
  /// note mode. The design's `place`.
  GameState place(int value) {
    if (value < 1 || value > n) {
      throw ArgumentError.value(value, 'value', 'outside 1..$n');
    }
    final i = selected;
    if (i == null || isGiven(i) || won || lost) return this;

    if (effectiveNoteMode) {
      if (values[i] != 0) return this;
      final marks = [...notes[i]];
      marks.contains(value) ? marks.remove(value) : marks.add(value);
      marks.sort();
      return copyWith(notes: _replace(notes, i, marks), clearNotice: true);
    }

    if (values[i] == value) {
      final cleared = copyWith(
        values: _replace(values, i, 0),
        clearNotice: true,
      );
      return settings.autoNotes ? cleared._autoNoted() : cleared;
    }

    final nextValues = _replace(values, i, value);
    var nextNotes = _replace(notes, i, const <int>[]);
    var nextMistakes = mistakes;
    var nextLost = lost;
    var nextRevealed = revealed;
    Notice? nextNotice;
    var nextWon = false;

    if (value != solution[i] && settings.strikeMode.countsMistakes) {
      nextMistakes++;
      final limit = settings.strikeMode.limit;
      if (settings.announce == AnnounceMode.now) {
        nextNotice = Notice(
          BannerKind.error,
          kTagMistake,
          mistakeBody(nextMistakes, limit),
        );
      }
      if (limit != null && nextMistakes >= limit) nextLost = true;
    }

    if (settings.autoClear) {
      final peers = unitsOf(shape, i).toSet();
      nextNotes = [
        for (var j = 0; j < nextNotes.length; j++)
          peers.contains(j) && nextNotes[j].contains(value)
              ? nextNotes[j].where((x) => x != value).toList()
              : nextNotes[j],
      ];
    }

    if (!nextValues.contains(0)) {
      var clean = true;
      for (var j = 0; j < nextValues.length; j++) {
        if (nextValues[j] != solution[j]) clean = false;
      }
      if (clean) {
        nextWon = true;
      } else {
        nextRevealed = true;
        nextNotice = Notice(
          BannerKind.error,
          kTagGridFull,
          settings.strikeMode == StrikeMode.zen
              ? kGridFullBodyZen
              : kGridFullBody,
        );
      }
    }

    final next = copyWith(
      values: nextValues,
      notes: nextNotes,
      moves: moves + 1,
      mistakes: nextMistakes,
      lost: nextLost,
      won: nextWon,
      revealed: nextRevealed,
      notice: nextNotice,
      clearNotice: nextNotice == null,
    );
    return settings.autoNotes ? next._autoNoted() : next;
  }

  /// Every empty cell's notes set to its candidates; filled cells none.
  GameState _autoNoted() => copyWith(
    notes: [
      for (var i = 0; i < values.length; i++)
        values[i] == 0 ? candidates(shape, values, i) : const <int>[],
    ],
  );

  static List<T> _replace<T>(List<T> list, int index, T value) =>
      [...list]..[index] = value;

  /// A copy with the given fields replaced. `clearSelected` and
  /// `clearNotice` set those two to null.
  GameState copyWith({
    GameSettings? settings,
    List<int>? values,
    List<List<int>>? notes,
    int? selected,
    bool clearSelected = false,
    int? mistakes,
    int? moves,
    int? elapsedSeconds,
    bool? won,
    bool? lost,
    bool? revealed,
    bool? noteMode,
    Notice? notice,
    bool clearNotice = false,
  }) => GameState(
    puzzle: puzzle,
    settings: settings ?? this.settings,
    values: values ?? this.values,
    notes: notes ?? this.notes,
    selected: clearSelected ? null : (selected ?? this.selected),
    mistakes: mistakes ?? this.mistakes,
    moves: moves ?? this.moves,
    elapsedSeconds: elapsedSeconds ?? this.elapsedSeconds,
    won: won ?? this.won,
    lost: lost ?? this.lost,
    revealed: revealed ?? this.revealed,
    noteMode: noteMode ?? this.noteMode,
    notice: clearNotice ? null : (notice ?? this.notice),
  );

  @override
  bool operator ==(Object other) =>
      other is GameState &&
      other.puzzle == puzzle &&
      other.settings == settings &&
      listEquals(other.values, values) &&
      deepListEquals(other.notes, notes) &&
      other.selected == selected &&
      other.mistakes == mistakes &&
      other.moves == moves &&
      other.elapsedSeconds == elapsedSeconds &&
      other.won == won &&
      other.lost == lost &&
      other.revealed == revealed &&
      other.noteMode == noteMode &&
      other.notice == notice;

  @override
  int get hashCode => Object.hash(
    puzzle,
    settings,
    Object.hashAll(values),
    deepListHash(notes),
    selected,
    mistakes,
    moves,
    elapsedSeconds,
    won,
    lost,
    revealed,
    noteMode,
    notice,
  );

  @override
  String toString() =>
      'GameState($boardTitle, $filledCount filled, $mistakes mistakes'
      '${won ? ', won' : ''}${lost ? ', lost' : ''})';
}
