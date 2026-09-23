// The rules of play as an immutable value: every verb returns a new state,
// or this one unchanged when it does not apply.
//
// The rules are the design's prototype (`place`, `erase`, `undo`, `redo`,
// `check`, `hint`, `restart` in Honest Sudoku.dc.html), with the divergences
// the plan recorded: a pencil-mark toggle on a filled cell does nothing,
// Zen's grid-full message does not point at red cells, redo re-derives won
// and lost (so redoing a fatal entry loses again), and nothing but the pause
// card's own actions works while paused. Widgets render these states and
// forward taps; they hold no rule logic.

import 'package:honest_sudoku/engine/engine.dart';
import 'package:honest_sudoku/engine/engine.dart' as engine show check;

import 'format.dart';
import 'game_settings.dart';
import 'lists.dart';
import 'notice.dart';
import 'seed_source.dart';
import 'snapshot.dart';

/// Undo steps kept, as the design's history keeps them.
const int kHistoryCap = 120;

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
    this.paused = false,
    this.hintedCell,
    List<Snapshot> history = const [],
    List<Snapshot> future = const [],
  }) : values = List.unmodifiable(values),
       notes = List.unmodifiable([
         for (final list in notes) List<int>.unmodifiable(list),
       ]),
       history = List.unmodifiable(history),
       future = List.unmodifiable(future) {
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

  /// Play is suspended: the board is hidden and only the pause card's own
  /// actions work.
  final bool paused;

  /// The cell a hint pointed at, whose ring and notes show yellow. Cleared by
  /// any change of selection or notice.
  final int? hintedCell;

  /// Undo steps, oldest first.
  final List<Snapshot> history;

  /// Redo steps, the next one last.
  final List<Snapshot> future;

  /// There is a step to undo.
  bool get canUndo => history.isNotEmpty;

  /// There is a step to redo.
  bool get canRedo => future.isNotEmpty;

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
    if (paused) return this;
    return selected == index
        ? copyWith(clearSelected: true)
        : copyWith(selected: index);
  }

  /// Flips note mode. Allowed while auto-notes is on (the pad then still
  /// places values; see [effectiveNoteMode]) and after the game is over.
  GameState toggleNoteMode() => paused ? this : copyWith(noteMode: !noteMode);

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
    if (paused || i == null || isGiven(i) || won || lost) return this;

    if (effectiveNoteMode) {
      if (values[i] != 0) return this;
      final marks = [...notes[i]];
      marks.contains(value) ? marks.remove(value) : marks.add(value);
      marks.sort();
      return _snapshotted().copyWith(
        notes: _replace(notes, i, marks),
        clearNotice: true,
      );
    }

    if (values[i] == value) {
      final cleared = _snapshotted().copyWith(
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

    final next = _snapshotted().copyWith(
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

  /// Clears the selected cell's value and pencil marks. The design's
  /// `erase`: a no-op on a given, with nothing selected, or when the game is
  /// over. Does not count a move.
  GameState erase() {
    final i = selected;
    if (paused || i == null || isGiven(i) || won || lost) return this;
    final next = _snapshotted().copyWith(
      values: _replace(values, i, 0),
      notes: _replace(notes, i, const <int>[]),
      clearNotice: true,
    );
    return settings.autoNotes ? next._autoNoted() : next;
  }

  /// Steps back one change. Clears won, lost and the notice: the design's
  /// `undo`.
  GameState undo() {
    if (paused || history.isEmpty) return this;
    final back = history.last;
    return copyWith(
      values: back.values,
      notes: back.notes,
      mistakes: back.mistakes,
      moves: back.moves,
      history: history.sublist(0, history.length - 1),
      future: [...future, _snapshot],
      won: false,
      lost: false,
      clearNotice: true,
    );
  }

  /// Replays one undone change. Won, lost and revealed are derived again
  /// from the restored grid, so redoing a fatal entry loses again.
  GameState redo() {
    if (paused || future.isEmpty) return this;
    final forward = future.last;
    final full = !forward.values.contains(0);
    var clean = full;
    for (var j = 0; clean && j < forward.values.length; j++) {
      if (forward.values[j] != solution[j]) clean = false;
    }
    final limit = settings.strikeMode.limit;
    return copyWith(
      values: forward.values,
      notes: forward.notes,
      mistakes: forward.mistakes,
      moves: forward.moves,
      history: _capped([...history, _snapshot]),
      future: future.sublist(0, future.length - 1),
      won: full && clean,
      lost: limit != null && forward.mistakes >= limit,
      revealed: revealed || (full && !clean),
      clearNotice: true,
    );
  }

  /// Marks every wrong entry and says how things stand, through the engine's
  /// `check`: the design's Check. A no-op when the game is over or paused.
  GameState check() {
    if (paused || won || lost) return this;
    final result = engine.check(shape, values, solution);
    return copyWith(
      revealed: true,
      notice: Notice(result.banner, result.tag, result.body),
    );
  }

  /// Finds the easiest next step through the engine's `nextHint`, selects
  /// its cell and explains it (or just names it, with explanations off). A
  /// no-op when the game is over or paused, or the board is full. Note mode
  /// is untouched.
  GameState hint() {
    if (paused || won || lost || isFull) return this;
    final h = nextHint(shape, values, solution, explain: settings.hintWhy);
    if (h == null) return this;
    return copyWith(
      selected: h.cellIndex,
      hintedCell: h.cellIndex,
      notice: Notice(h.banner, h.tag, h.body),
    );
  }

  /// The same board from the start: same seed and givens, no entries,
  /// mistakes, moves, time, history, notice or selection; auto-notes
  /// applied; unpaused. Settings are kept. Works while paused, because the
  /// pause card offers it.
  GameState restart() => GameState.start(puzzle, settings);

  /// A new board with the same settings: this state unpaused with its notice
  /// and hinted cell cleared, and the request for the next board — same
  /// size and difficulty, a fresh seed from [seeds] that differs from this
  /// one (redrawn up to [kSeedRedraws] times; the last draw is kept). The
  /// caller generates the board. Works while paused.
  (GameState, GenerationRequest) newDeal(SeedSource seeds) {
    var seed = seeds.next();
    for (var k = 0; k < kSeedRedraws && seed == puzzle.seed; k++) {
      seed = seeds.next();
    }
    return (
      copyWith(paused: false, clearNotice: true),
      GenerationRequest(shape, seed, difficulty),
    );
  }

  /// Suspends play. Allowed on a finished game, so every state is
  /// constructible.
  GameState pause() => copyWith(paused: true);

  /// Resumes play.
  GameState resume() => copyWith(paused: false);

  /// One second of play: counted only while not paused and not over. Whether
  /// the board is on screen is the controller's business.
  GameState tick() => paused || won || lost
      ? this
      : copyWith(elapsedSeconds: elapsedSeconds + 1);

  /// The pause card's line, e.g. `40 of 81 cells filled · 12 entries ·
  /// 2 mistakes` (or `zen mode`), the design's grammar kept (`1 entries`).
  String get pauseFill =>
      '$filledCount of ${shape.cellCount} cells filled · $moves entries · '
      '${settings.strikeMode == StrikeMode.zen ? 'zen mode' : '$mistakes mistakes'}';

  /// The pause card's meta: `SIZE · DIFFICULTY · M:SS`, upper-cased.
  String get pauseMeta =>
      '${shape.label} · ${difficulty.label} · ${fmt(elapsedSeconds)}'
          .toUpperCase();

  Snapshot get _snapshot => Snapshot(values, notes, mistakes, moves);

  /// This state with its current values pushed onto the history and the
  /// redo stack emptied: what every changing verb does first.
  GameState _snapshotted() =>
      copyWith(history: _capped([...history, _snapshot]), future: const []);

  static List<Snapshot> _capped(List<Snapshot> h) =>
      h.length > kHistoryCap ? h.sublist(h.length - kHistoryCap) : h;

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
    bool? paused,
    int? hintedCell,
    List<Snapshot>? history,
    List<Snapshot>? future,
  }) {
    final nextSelected = clearSelected ? null : (selected ?? this.selected);
    final nextNotice = clearNotice ? null : (notice ?? this.notice);
    // The hinted cell lasts only as long as the selection and notice the
    // hint set; any change to either clears it.
    final nextHinted =
        hintedCell ??
        (nextSelected == this.selected && nextNotice == this.notice
            ? this.hintedCell
            : null);
    return GameState(
      puzzle: puzzle,
      settings: settings ?? this.settings,
      values: values ?? this.values,
      notes: notes ?? this.notes,
      selected: nextSelected,
      mistakes: mistakes ?? this.mistakes,
      moves: moves ?? this.moves,
      elapsedSeconds: elapsedSeconds ?? this.elapsedSeconds,
      won: won ?? this.won,
      lost: lost ?? this.lost,
      revealed: revealed ?? this.revealed,
      noteMode: noteMode ?? this.noteMode,
      notice: nextNotice,
      paused: paused ?? this.paused,
      hintedCell: nextHinted,
      history: history ?? this.history,
      future: future ?? this.future,
    );
  }

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
      other.notice == notice &&
      other.paused == paused &&
      other.hintedCell == hintedCell &&
      listEquals(other.history, history) &&
      listEquals(other.future, future);

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
    paused,
    hintedCell,
    Object.hashAll(history),
    Object.hashAll(future),
  );

  @override
  String toString() =>
      'GameState($boardTitle, $filledCount filled, $mistakes mistakes'
      '${won ? ', won' : ''}${lost ? ', lost' : ''})';
}
