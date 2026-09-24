// Plays the four game sounds (#49).
//
// The real player talks to SoundBridge.kt over a method channel: SoundPool,
// no plugin. Anywhere the channel is missing (tests, a platform without the
// bridge) it logs once and stays silent; a sound is never allowed to throw
// into the UI.

import 'dart:developer' as developer;

import 'package:flutter/services.dart';

import 'feedback_event.dart';

/// Plays [FeedbackEvent]s.
abstract class SoundPlayer {
  /// Loads each event's asset key. Plays before this completes are dropped.
  Future<void> load(Map<FeedbackEvent, String> assets);

  /// Plays [e], if it loaded.
  void play(FeedbackEvent e);

  /// Releases everything loaded.
  Future<void> dispose();
}

/// Plays nothing.
class NoSoundPlayer implements SoundPlayer {
  /// Creates the silent player.
  const NoSoundPlayer();

  @override
  Future<void> load(Map<FeedbackEvent, String> assets) async {}

  @override
  void play(FeedbackEvent e) {}

  @override
  Future<void> dispose() async {}
}

/// Plays through `SoundBridge.kt`.
class ChannelSoundPlayer implements SoundPlayer {
  /// Creates the player on its channel, logging through [log].
  ChannelSoundPlayer({
    this._channel = const MethodChannel(kSoundChannel),
    void Function(String message)? log,
  }) : _log = log ?? _defaultLog;

  final MethodChannel _channel;
  final void Function(String) _log;
  var _loaded = false;
  var _dead = false;
  final _playFailed = <FeedbackEvent>{};

  static void _defaultLog(String message) =>
      developer.log(message, name: 'honest_sudoku.sound');

  @override
  Future<void> load(Map<FeedbackEvent, String> assets) async {
    if (_dead) return;
    try {
      final loaded = await _channel.invokeMethod<int>('load', {
        for (final e in assets.entries) e.key.clip: e.value,
      });
      _loaded = true;
      if (loaded != assets.length) {
        _log('sound: ${loaded ?? 0} of ${assets.length} clips loaded');
      }
    } on Object catch (e) {
      _dead = true;
      _log('sound: no player, playing nothing ($e)');
    }
  }

  @override
  void play(FeedbackEvent e) {
    if (_dead || !_loaded) return;
    _channel.invokeMethod<void>('play', e.clip).catchError((Object error) {
      if (_playFailed.add(e)) _log('sound: ${e.clip} did not play ($error)');
    });
  }

  @override
  Future<void> dispose() async {
    if (_dead || !_loaded) return;
    _loaded = false;
    try {
      await _channel.invokeMethod<void>('release');
    } on Object catch (e) {
      _log('sound: release failed ($e)');
    }
  }
}

/// The channel SoundBridge.kt listens on.
const String kSoundChannel = 'com.honestarcade.sudoku/sound';
