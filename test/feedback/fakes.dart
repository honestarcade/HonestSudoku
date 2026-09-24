// Recording fakes for the feedback ports (#49, #55).

import 'package:honest_sudoku/feedback/game_feedback.dart';

/// Records what would have played.
final class RecordingPlayer implements SoundPlayer {
  /// Every load, in order.
  final loaded = <Map<FeedbackEvent, String>>[];

  /// Every play, in order.
  final played = <FeedbackEvent>[];

  @override
  Future<void> load(Map<FeedbackEvent, String> assets) async =>
      loaded.add(assets);

  @override
  void play(FeedbackEvent e) => played.add(e);

  @override
  Future<void> dispose() async {}
}

/// Records every tick, in order: `light` or `medium`.
final class RecordingHaptics implements HapticsPort {
  /// The ticks.
  final ticks = <String>[];

  @override
  Future<void> light() async => ticks.add('light');

  @override
  Future<void> medium() async => ticks.add('medium');
}
