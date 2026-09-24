// What the player hears when a number lands (#49).
//
// GameFeedback listens to the controller and, after each placement, derives at
// most one event by priority: the last strike, then a solve, then a counted
// mistake the game announces at once, then the placement itself. A winning or
// losing entry plays only its cue, never the click as well. In At-the-end
// mode a wrong entry clicks like any other, because the thud would reveal
// what the mode hides; Zen never counts a mistake, so it clicks too.
//
// Anything that is not a placement (erase, undo, redo, a restore, a new deal)
// only moves the baseline the next placement is compared with.

import 'dart:async';
import 'dart:developer' as developer;

import 'package:honest_sudoku/engine/engine.dart';
import 'package:honest_sudoku/game/game.dart';

import '../ui/board/game_action.dart';
import '../ui/board/game_controller.dart';
import 'feedback_event.dart';
import 'sound_player.dart';

export 'feedback_event.dart';
export 'sound_player.dart';

/// Reads the asset keys the app bundles.
typedef AssetManifestReader = Future<Set<String>> Function();

/// Turns play into sounds.
class GameFeedback {
  /// Creates the feedback over a player, resolving clips through [manifest].
  GameFeedback({
    required this._player,
    AssetManifestReader? manifest,
    void Function(String message)? log,
  }) : _manifest = manifest ?? (() async => const <String>{}),
       _log = log ?? _defaultLog;

  final SoundPlayer _player;
  final AssetManifestReader _manifest;
  final void Function(String) _log;
  GameController? _controller;
  GameState? _baseline;
  var _sfx = false;

  static void _defaultLog(String message) =>
      developer.log(message, name: 'honest_sudoku.sound');

  /// The event the latest notification produced, whether or not it sounded.
  FeedbackEvent? get lastEvent => _lastEvent;
  FeedbackEvent? _lastEvent;

  /// The latest placement clashed: a counted mistake announced at once, or a
  /// value a peer already holds while conflicts are shown.
  bool get clash => _clash;
  var _clash = false;

  /// Starts listening to [controller] and loads the clips.
  Future<void> attach(GameController controller) async {
    _controller = controller;
    _baseline = controller.state;
    _sfx = controller.settings.sfx;
    controller.addListener(_changed);
    await _player.load(resolveClips(await _manifest(), _log));
  }

  /// Stops listening. The player belongs to whoever made it.
  void detach() {
    _controller?.removeListener(_changed);
    _controller = null;
  }

  void _changed() {
    final c = _controller!;
    final prev = _baseline;
    final next = _baseline = c.state;
    final sfxWas = _sfx;
    _sfx = c.settings.sfx;

    _lastEvent = null;
    _clash = false;
    if (c.lastAction == GameAction.settings && _sfx && !sfxWas) {
      // Switching Sound effects on answers with one click (owner,
      // 2026-09-19); nothing else comes from a settings change.
      _player.play(FeedbackEvent.place);
      return;
    }
    if (c.lastAction != GameAction.place || prev == null || next == null) {
      return;
    }
    final event = deriveEvent(prev, next);
    if (event == null) return;
    _lastEvent = event;
    _clash =
        event == FeedbackEvent.mistake ||
        (next.settings.conflicts &&
            c.lastPlacedIndex != null &&
            _peersHold(next, c.lastPlacedIndex!));
    if (_sfx) _player.play(event);
  }

  static bool _peersHold(GameState s, int i) {
    final v = s.values[i];
    if (v == 0) return false;
    for (final j in unitsOf(s.shape, i)) {
      if (s.values[j] == v) return true;
    }
    return false;
  }
}

/// The one event a placement from [prev] to [next] makes, or null.
FeedbackEvent? deriveEvent(GameState prev, GameState next) {
  if (next.lost && !prev.lost) return FeedbackEvent.lastStrike;
  if (next.won && !prev.won) return FeedbackEvent.solve;
  if (next.mistakes > prev.mistakes &&
      next.settings.announce == AnnounceMode.now) {
    return FeedbackEvent.mistake;
  }
  if (next.moves > prev.moves) return FeedbackEvent.place;
  return null;
}

/// Each event's asset: the real clip if bundled, else its placeholder, else
/// none (logged).
Map<FeedbackEvent, String> resolveClips(
  Set<String> bundled,
  void Function(String) log,
) {
  final out = <FeedbackEvent, String>{};
  for (final e in FeedbackEvent.values) {
    final real = 'assets/audio/${e.clip}.wav';
    final placeholder = 'assets/audio/placeholder-${e.clip}.wav';
    if (bundled.contains(real)) {
      out[e] = real;
    } else if (bundled.contains(placeholder)) {
      out[e] = placeholder;
    } else {
      log('sound: no clip for ${e.clip}');
    }
  }
  return out;
}
