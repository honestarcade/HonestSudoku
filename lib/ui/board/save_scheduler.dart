// When the game is written: a short trailing-edge debounce so a burst of
// taps is one write, a maximum wait so a long burst still lands, and a way
// to write at once (pause, background, a win) that cancels the pending one.

import 'dart:async';

/// Debounces saves.
final class SaveScheduler {
  /// Creates the scheduler.
  SaveScheduler({
    required this.onSave,
    this.delay = const Duration(milliseconds: 250),
    this.maxWait = const Duration(seconds: 2),
  });

  /// Performs one save.
  final Future<void> Function() onSave;

  /// Quiet time before a debounced save.
  final Duration delay;

  /// Longest a change waits while changes keep coming.
  final Duration maxWait;

  Timer? _timer;
  Timer? _cap;
  Future<void> _last = Future<void>.value();

  /// Something changed: save after [delay] of quiet, or [maxWait] at most.
  void touch() {
    _timer?.cancel();
    _timer = Timer(delay, _fire);
    _cap ??= Timer(maxWait, _fire);
  }

  /// Saves now, cancelling any pending save; completes when it is written.
  Future<void> flushNow() {
    cancel();
    return _run();
  }

  /// Drops any pending save.
  void cancel() {
    _timer?.cancel();
    _cap?.cancel();
    _timer = null;
    _cap = null;
  }

  void _fire() {
    cancel();
    unawaited(_run());
  }

  Future<void> _run() => _last = _last.then((_) => onSave()).catchError((_) {});

  /// Completes when every save started so far has finished.
  Future<void> get idle => _last;
}
