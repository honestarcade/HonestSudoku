// The app's owner of play: the current game, the clock, generation, the
// player's settings and statistics, and their storage.
//
// It lives in lib/ui/ rather than lib/game/ because it needs Flutter (a
// ChangeNotifier, the binding's lifecycle), which the game model's imports
// guard refuses. Every rule stays in the model; this forwards verbs, owns the
// one-second timer and the generation stream, feeds the statistics from what
// the model reports, and writes the three documents when they change.

import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/widgets.dart';
import 'package:honest_sudoku/engine/engine.dart';
import 'package:honest_sudoku/game/game.dart';
import 'package:honest_sudoku/store/app_store.dart';

import '../copy.dart';
import '../theme/board_theme.dart';
import 'random_seed_source.dart';
import 'save_scheduler.dart';

/// Makes a board off the UI thread; [generateInIsolate] is the real one.
typedef BoardGenerator = Stream<GenerationEvent> Function(
  GenerationRequest request,
);

Stream<GenerationEvent> _isolateGenerator(GenerationRequest request) =>
    generateInIsolate(request);

/// Where generation stands, for the loading screen.
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

/// A generation that did not produce a board, as the notice shows it.
final class GenerationFailureView implements Exception {
  /// Creates the view.
  const GenerationFailureView(this.tag, this.body, this.reason);

  /// The notice's kicker.
  final String tag;

  /// The notice's sentence.
  final String body;

  /// Why, or null when the player cancelled.
  final GenerationFailure? reason;

  /// As a notice.
  Notice get notice => Notice(BannerKind.error, tag, body);

  @override
  String toString() => 'GenerationFailureView($tag)';
}

/// The menu's one-line view of an unfinished game.
final class GameSummary {
  /// Creates a summary.
  const GameSummary(this.shapeLabel, this.difficultyLabel, this.elapsedText);

  /// `9×9`.
  final String shapeLabel;

  /// `Medium`.
  final String difficultyLabel;

  /// `m:ss`.
  final String elapsedText;

  /// `9×9 · MEDIUM · 0:42`, as the menu's Continue line reads.
  String get meta =>
      '$shapeLabel · ${difficultyLabel.toUpperCase()} · $elapsedText';
}

/// Owns the game on screen and everything the player keeps.
class GameController extends ChangeNotifier with WidgetsBindingObserver {
  /// Creates the controller and starts listening to the app's lifecycle.
  ///
  /// [store] opens the store; without one, or when it yields null, nothing
  /// is persisted (tests of play alone). [generator], [seeds] and [log]
  /// replace the real ones.
  GameController({
    BoardGenerator? generator,
    SeedSource? seeds,
    Future<AppStore?> Function()? store,
    this._settings = const AppSettings(),
    void Function(String message)? log,
  }) : _generator = generator ?? _isolateGenerator,
       _seeds = seeds ?? RandomSeedSource(),
       _storeFactory = store,
       _log = log ?? _defaultLog {
    WidgetsBinding.instance.addObserver(this);
    _clock = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    _saver = SaveScheduler(onSave: _saveGameAndStats);
  }

  final BoardGenerator _generator;
  final SeedSource _seeds;
  final Future<AppStore?> Function()? _storeFactory;
  final void Function(String) _log;
  late final Timer _clock;
  late final SaveScheduler _saver;
  Timer? _inactive;
  StreamSubscription<GenerationEvent>? _generation;
  Completer<void>? _generationDone;
  GenerationRequest? _lastRequest;
  AppStore? _store;
  Future<void>? _loading;
  var _boardVisible = false;
  var _disposed = false;
  var _settingsNewer = false;

  // Once-per-game guards, keyed by seed.
  int? _abandoned;
  int? _wonSeed;
  int? _lostSeed;

  static void _defaultLog(String message) =>
      developer.log(message, name: 'honest_sudoku.controller');

  /// The game on screen, if any.
  GameState? get state => _state;
  GameState? _state;

  /// The player's settings.
  AppSettings get settings => _settings;
  AppSettings _settings;

  /// The board's colour scheme key.
  String get themeKey => _settings.themeKey;

  /// The board's colours.
  BoardTheme get theme => BoardTheme.byKey(_settings.themeKey);

  /// Everything recorded.
  StatsBook get book => _book;
  StatsBook _book = StatsBook.empty;

  /// The win card's streak, read from [book].
  late final StatsSource stats = RealStatsSource(() => _book);

  /// The statistics screen's tab, remembered for the session.
  Difficulty get statsTab => _statsTab;
  Difficulty _statsTab = Difficulty.medium;
  set statsTab(Difficulty d) {
    if (d == _statsTab) return;
    _statsTab = d;
    notifyListeners();
  }

  /// Non-null while a board is being made.
  LoadingStatus? get loading => _loadingStatus;
  LoadingStatus? _loadingStatus;

  /// The last generation's failure, until the next request.
  GenerationFailureView? get generationFailure => _failure;
  GenerationFailureView? _failure;

  /// Completes when the current request's board is ready; fails with a
  /// [GenerationFailureView] on failure or cancel.
  Future<void> get generationDone =>
      _generationDone?.future ?? Future<void>.value();

  /// The board on screen is one generation just produced; entering it plays
  /// rather than pauses.
  bool get justGenerated => _justGenerated;
  var _justGenerated = false;

  /// A game exists that is neither won nor lost.
  bool get hasUnfinishedGame {
    final s = _state;
    return s != null && !s.won && !s.lost;
  }

  /// The unfinished game, as the menu shows it; null when there is none.
  GameSummary? get summary {
    final s = _state;
    if (s == null || s.won || s.lost) return null;
    return GameSummary(
      s.shape.label,
      s.difficulty.label,
      fmt(s.elapsedSeconds),
    );
  }

  // ---- loading ------------------------------------------------------------

  /// Reads settings, the saved game and statistics. Idempotent; the store
  /// is opened on the first call. Rethrows when the store cannot be opened.
  Future<void> load() => _loading ??= _load().catchError((Object e) {
    _loading = null;
    throw e;
  });

  Future<void> _load() async {
    final factory = _storeFactory;
    if (factory == null) return;
    final store = _store = await factory();
    if (store == null) return;

    switch (await store.readSettings()) {
      case Present(:final value):
        _settings = value;
      case Newer():
        _settingsNewer = true;
      case Absent() || Corrupt():
        await _writeSettings();
    }

    switch (await store.readStats()) {
      case Present(:final value):
        _book = value;
      case _:
        break;
    }

    if (_state == null) {
      switch (await store.readGame()) {
        case Present(:final value):
          if (value.won || value.lost) {
            await _guard(store.deleteGame);
          } else {
            GameState? restored;
            try {
              if (supportedDifficulties(value.shape)
                  .contains(value.difficulty)) {
                restored = value.toState(_settings.game);
              }
            } on Object catch (e) {
              _log('saved game does not restore: $e');
            }
            if (restored == null) {
              await _guard(store.deleteGame);
            } else {
              _state = restored;
              // One source of truth for the running game's modes.
              _settings = _settings.copyWith(game: restored.settings);
              await _writeSettings();
            }
          }
        case _:
          break;
      }
    }
    notifyListeners();
  }

  // ---- settings -----------------------------------------------------------

  /// Applies and saves [next]. Its board toggles and modes reach an
  /// unfinished game at once (from the next placement); its last setup never
  /// touches play.
  void updateSettings(AppSettings next) {
    if (next == _settings) return;
    _settings = next;
    final s = _state;
    if (s != null && !s.won && !s.lost) {
      _state = s.withSettings(next.game);
      _saver.touch();
    }
    unawaited(_writeSettings());
    notifyListeners();
  }

  Future<void> _writeSettings() async {
    final store = _store;
    if (store == null || _settingsNewer) return;
    await _guard(() => store.writeSettings(_settings));
  }

  // ---- play -----------------------------------------------------------------

  void _apply(GameState Function(GameState s) verb) {
    final prev = _state;
    if (prev == null) return;
    final next = verb(prev);
    if (identical(next, prev)) return;
    _state = next;
    _afterChange(prev, next);
    notifyListeners();
  }

  void _afterChange(GameState prev, GameState next) {
    final seed = next.puzzle.seed;
    if (next.won && !prev.won && _wonSeed != seed) {
      _wonSeed = seed;
      _book = _book.recordWin(next.shape, next.difficulty, next.elapsedSeconds);
      unawaited(_saver.flushNow());
    } else if (next.lost && !prev.lost && _lostSeed != seed) {
      _lostSeed = seed;
      _book = _book.recordLoss(next.shape, next.difficulty);
      unawaited(_saver.flushNow());
    } else if (next.paused && !prev.paused) {
      unawaited(_saver.flushNow());
    } else {
      _saver.touch();
    }
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

  /// Restart this puzzle. Records nothing: it is the same game.
  void restart() => _apply((s) => s.restart());

  // ---- generation -----------------------------------------------------------

  /// A new puzzle with the same size and difficulty as the current one.
  void newDeal() {
    final s = _state;
    if (s == null) return;
    startNew(s.shape, s.difficulty);
  }

  /// A new puzzle of [shape] and [difficulty], with the last setup's strike
  /// and announce modes. An unfinished game is recorded as abandoned, once,
  /// and saved at once, whether or not the new board arrives.
  void startNew(GridShape shape, Difficulty difficulty) {
    final current = _state;
    if (current != null && !current.won && !current.lost) {
      final seed = current.puzzle.seed;
      if (_abandoned != seed) {
        _abandoned = seed;
        _book = _book.recordAbandon(current.shape, current.difficulty);
        unawaited(_saver.flushNow());
      }
    }
    // The seed comes through the model's newDeal when a game exists, so a
    // new board never repeats the current seed (#30).
    final seed = current == null
        ? _seeds.next()
        : current.newDeal(_seeds).$2.seed;
    _generate(GenerationRequest(shape, seed, difficulty));
  }

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
    _loadingStatus = null;
    _fail(
      const GenerationFailureView(
        Copy.generationCancelled,
        Copy.cancelled,
        null,
      ),
    );
    notifyListeners();
  }

  void _fail(GenerationFailureView view) {
    _failure = view;
    final done = _generationDone;
    if (done != null && !done.isCompleted) {
      // Nobody may be listening; the error is also on [generationFailure].
      done.future.ignore();
      done.completeError(view);
    }
  }

  void _generate(GenerationRequest request) {
    unawaited(_generation?.cancel());
    _lastRequest = request;
    _loadingStatus = const LoadingStatus(0, GenerationPhase.generating);
    _failure = null;
    _generationDone = Completer<void>();
    // The new game's modes are the last setup's; the running game keeps its
    // own until the new board replaces it.
    final setup = _settings.lastSetup;
    final modes = _settings.game.copyWith(
      strikeMode: setup.strikeMode,
      announce: setup.announce,
    );
    notifyListeners();
    _generation = _generator(request).listen((event) {
      if (_disposed) return;
      switch (event) {
        case GenerationProgress(:final fraction, :final phase):
          _loadingStatus = LoadingStatus(fraction, phase);
        case GenerationDone(:final puzzle):
          _generation = null;
          _loadingStatus = null;
          _state = GameState.start(puzzle, modes);
          _settings = _settings.copyWith(game: modes);
          _justGenerated = true;
          _book = _book.recordStart(puzzle.shape, puzzle.difficulty!);
          unawaited(_writeSettings());
          unawaited(_saver.flushNow());
          final done = _generationDone;
          if (done != null && !done.isCompleted) done.complete();
        case GenerationFailedEvent(:final reason):
          _generation = null;
          _loadingStatus = null;
          _fail(
            GenerationFailureView(Copy.generationFailed, switch (reason) {
              GenerationTimeout() => Copy.failedTimeout,
              AttemptsExhausted() => Copy.failedAttempts,
              UnexpectedError() => Copy.failedUnexpected,
            }, reason),
          );
      }
      notifyListeners();
    });
  }

  // ---- the board on screen --------------------------------------------------

  /// The board route became the one on screen. A board generation just made
  /// plays; any other return lands paused.
  void enterBoard() {
    _boardVisible = true;
    if (_justGenerated) {
      _justGenerated = false;
      return;
    }
    final s = _state;
    if (s != null && !s.won && !s.lost && !s.paused) pause();
  }

  /// The board route is (or is no longer) the one on screen; time counts
  /// only while it is, and leaving it saves.
  void setBoardVisible(bool visible) {
    _boardVisible = visible;
    if (!visible) unawaited(_saver.flushNow());
  }

  void _tick() {
    final s = _state;
    if (s == null || !_boardVisible || _loadingStatus != null) return;
    final next = s.tick();
    if (identical(next, s)) return;
    _state = next;
    _book = _book.recordTime(s.shape, s.difficulty, 1);
    notifyListeners();
  }

  // ---- statistics -----------------------------------------------------------

  /// Forgets every statistic. An unfinished game's start is recorded again,
  /// so its win or loss still has a start to belong to.
  Future<void> resetStats() async {
    var book = StatsBook.empty;
    final s = _state;
    if (s != null && !s.won && !s.lost) {
      book = book.recordStart(s.shape, s.difficulty);
    }
    _book = book;
    notifyListeners();
    await _saver.flushNow();
  }

  // ---- storage --------------------------------------------------------------

  Future<void> _saveGameAndStats() async {
    final store = _store;
    if (store == null) return;
    final s = _state;
    if (s != null) {
      await _guard(() => store.writeGame(SavedGame.fromState(s)));
    }
    await _guard(() => store.writeStats(_book));
  }

  Future<void> _guard(Future<void> Function() write) async {
    try {
      await write();
    } on StoreNewerVersion catch (e) {
      _log('not written: $e');
    } on Object catch (e) {
      _log('write failed: $e');
    }
  }

  /// Writes anything pending; completes when it is on disk.
  Future<void> flush() => _saver.flushNow();

  // ---- lifecycle ------------------------------------------------------------

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused ||
          AppLifecycleState.hidden ||
          AppLifecycleState.detached:
        _inactive?.cancel();
        _pauseForBackground();
        unawaited(_saver.flushNow());
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
    pause();
  }

  @override
  void dispose() {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    _clock.cancel();
    _inactive?.cancel();
    unawaited(_generation?.cancel());
    unawaited(_saver.flushNow());
    super.dispose();
  }
}
