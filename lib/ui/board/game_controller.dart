// The board screen's owner: the current game, the clock, generation, and the
// app's lifecycle.
//
// It lives in lib/ui/ rather than lib/game/ because it needs Flutter (a
// ChangeNotifier, the binding's lifecycle), which the game model's imports
// guard refuses. Every rule stays in the model; this forwards verbs, owns the
// one-second timer and the generation stream, and pauses the game when the
// player leaves the app.

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:honest_sudoku/engine/engine.dart';
import 'package:honest_sudoku/game/game.dart';

import '../strings.dart';
import '../theme/board_theme.dart';
import 'random_seed_source.dart';

/// Makes a board off the UI thread; [generateInIsolate] is the real one.
typedef BoardGenerator = Stream<GenerationEvent> Function(
  GenerationRequest request,
);

Stream<GenerationEvent> _isolateGenerator(GenerationRequest request) =>
    generateInIsolate(request);

/// Where generation stands, for the loading placeholder.
final class LoadingStatus {
  /// Creates a status.
  const LoadingStatus(this.fraction, this.phase);

  /// `0.0` to `1.0`.
  final double fraction;

  /// The label: GENERATING, CARVING GIVENS or READY.
  final GenerationPhase phase;

  @override
  bool operator ==(Object other) =>
      other is LoadingStatus &&
      other.fraction == fraction &&
      other.phase == phase;

  @override
  int get hashCode => Object.hash(fraction, phase);
}

/// A generation that did not produce a board, as the banner shows it.
final class GenerationFailureView {
  /// Creates the view.
  const GenerationFailureView(this.tag, this.body, this.reason);

  /// The banner's kicker.
  final String tag;

  /// The banner's sentence.
  final String body;

  /// Why, or null when the player cancelled.
  final GenerationFailure? reason;

  /// As a notice.
  Notice get notice => Notice(BannerKind.error, tag, body);
}

/// Owns the game on screen.
class GameController extends ChangeNotifier with WidgetsBindingObserver {
  /// Creates the controller and starts listening to the app's lifecycle.
  GameController({
    BoardGenerator? generator,
    SeedSource? seeds,
    this.settings = const GameSettings(),
    this.theme = BoardTheme.navy,
    this.stats = const NoStats(),
  }) : _generator = generator ?? _isolateGenerator,
       _seeds = seeds ?? RandomSeedSource() {
    WidgetsBinding.instance.addObserver(this);
    _clock = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  final BoardGenerator _generator;
  final SeedSource _seeds;
  late final Timer _clock;
  Timer? _inactive;
  StreamSubscription<GenerationEvent>? _generation;
  GenerationRequest? _lastRequest;
  var _boardVisible = true;
  var _disposed = false;

  /// The game on screen, if any.
  GameState? get state => _state;
  GameState? _state;

  /// How the player wants to play; applied to every new game.
  GameSettings settings;

  /// The board's colours.
  BoardTheme theme;

  /// Where the win card's streak comes from.
  StatsSource stats;

  /// Non-null while a board is being made.
  LoadingStatus? get loading => _loading;
  LoadingStatus? _loading;

  /// The last generation's failure, until a retry or the next action.
  GenerationFailureView? get generationFailure => _failure;
  GenerationFailureView? _failure;

  void _set(GameState? next) {
    if (identical(next, _state) && _failure == null) return;
    _state = next;
    _failure = null;
    notifyListeners();
  }

  void _apply(GameState Function(GameState s) verb) {
    final s = _state;
    if (s == null) return;
    _set(verb(s));
  }

  /// Selects or deselects a cell.
  void select(int index) => _apply((s) => s.select(index));

  /// Places a value, or toggles a pencil mark.
  void place(int value) => _apply((s) => s.place(value));

  /// Erases the selected cell.
  void erase() => _apply((s) => s.erase());

  /// Undo.
  void undo() => _apply((s) => s.undo());

  /// Redo.
  void redo() => _apply((s) => s.redo());

  /// Note mode on or off.
  void toggleNotes() => _apply((s) => s.toggleNoteMode());

  /// The easiest next step.
  void hint() => _apply((s) => s.hint());

  /// Check.
  void check() => _apply((s) => s.check());

  /// Pause.
  void pause() => _apply((s) => s.pause());

  /// Resume.
  void resume() => _apply((s) => s.resume());

  /// Restart this puzzle.
  void restart() => _apply((s) => s.restart());

  /// Applies new settings to this game and every later one.
  void updateSettings(GameSettings next) {
    settings = next;
    final s = _state;
    if (s != null) {
      _state = s.withSettings(next);
    }
    notifyListeners();
  }

  /// A new puzzle with the same settings. On failure the current board stays.
  void newDeal() {
    final s = _state;
    if (s == null) return;
    final (next, request) = s.newDeal(_seeds);
    _state = next;
    _generate(request);
  }

  /// A new puzzle of [shape] and [difficulty].
  void startNew(GridShape shape, Difficulty difficulty) =>
      _generate(GenerationRequest(shape, _seeds.next(), difficulty));

  /// Tries the last request again with a fresh seed.
  void retry() {
    final last = _lastRequest;
    if (last == null) return;
    _generate(GenerationRequest(last.shape, _seeds.next(), last.difficulty));
  }

  /// The player backed out of the loading screen.
  void cancelGeneration() {
    if (_generation == null) return;
    unawaited(_generation!.cancel());
    _generation = null;
    _loading = null;
    _failure = const GenerationFailureView(
      UiStrings.generationCancelled,
      UiStrings.cancelled,
      null,
    );
    notifyListeners();
  }

  void _generate(GenerationRequest request) {
    unawaited(_generation?.cancel());
    _lastRequest = request;
    _loading = const LoadingStatus(0, GenerationPhase.generating);
    _failure = null;
    notifyListeners();
    _generation = _generator(request).listen((event) {
      if (_disposed) return;
      switch (event) {
        case GenerationProgress(:final fraction, :final phase):
          _loading = LoadingStatus(fraction, phase);
        case GenerationDone(:final puzzle):
          _generation = null;
          _loading = null;
          _state = GameState.start(puzzle, settings);
        case GenerationFailedEvent(:final reason):
          _generation = null;
          _loading = null;
          _failure = GenerationFailureView(
            UiStrings.generationFailed,
            switch (reason) {
              GenerationTimeout() => UiStrings.failedTimeout,
              AttemptsExhausted() => UiStrings.failedAttempts,
              UnexpectedError() => UiStrings.failedUnexpected,
            },
            reason,
          );
      }
      notifyListeners();
    });
  }

  /// The board route is (or is no longer) the one on screen; time counts
  /// only while it is.
  void setBoardVisible(bool visible) => _boardVisible = visible;

  void _tick() {
    final s = _state;
    if (s == null || !_boardVisible || _loading != null) return;
    final next = s.tick();
    if (!identical(next, s)) {
      _state = next;
      notifyListeners();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused ||
          AppLifecycleState.hidden ||
          AppLifecycleState.detached:
        _inactive?.cancel();
        _pauseForBackground();
      case AppLifecycleState.inactive:
        // A notification shade or a dialog flickers through inactive; only a
        // lasting one pauses.
        _inactive?.cancel();
        _inactive = Timer(
          const Duration(milliseconds: 300),
          _pauseForBackground,
        );
      case AppLifecycleState.resumed:
        _inactive?.cancel();
    }
  }

  void _pauseForBackground() {
    final s = _state;
    if (s == null || !_boardVisible || s.won || s.lost || s.paused) return;
    _state = s.pause();
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    _clock.cancel();
    _inactive?.cancel();
    unawaited(_generation?.cancel());
    super.dispose();
  }
}
