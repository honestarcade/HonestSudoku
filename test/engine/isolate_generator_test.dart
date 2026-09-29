@Timeout(Duration(minutes: 3))
library;

import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter_test/flutter_test.dart';
import 'package:honest_sudoku/engine/engine.dart';

/// Reports once, then works forever.
Puzzle slowGenerate(GenerationRequest request, ProgressCallback onProgress) {
  onProgress(0.2);
  while (true) {
    sleep(const Duration(milliseconds: 5));
  }
}

/// Runs out of attempts, as the engine reports it.
Puzzle exhaustedGenerate(GenerationRequest r, ProgressCallback onProgress) =>
    throw GenerationFailed(r.shape, r.difficulty, r.seed, 7);

/// Fails in a way nothing anticipated.
Puzzle brokenGenerate(GenerationRequest r, ProgressCallback onProgress) =>
    throw StateError('boom');

/// True when [isolate] answers a ping within [window].
Future<bool> answers(Isolate isolate, Duration window) async {
  final pong = ReceivePort();
  isolate.ping(pong.sendPort, response: true);
  try {
    await pong.first.timeout(window);
    return true;
  } on TimeoutException {
    return false;
  } finally {
    pong.close();
  }
}

void main() {
  tearDown(() {
    generateOverride = null;
    onIsolateSpawned = null;
  });

  for (final shape in GridShape.all) {
    test('${shape.label}: progress never falls, phases in order, then the '
        'board the synchronous generator makes', () async {
      final events = await generateInIsolate(
        GenerationRequest(shape, 1, Difficulty.easy),
      ).toList();
      final progress = events.whereType<GenerationProgress>().toList();
      expect(progress.first.fraction, 0.0);
      expect(progress.last.fraction, 1.0);
      for (var i = 1; i < progress.length; i++) {
        expect(progress[i].fraction, greaterThan(progress[i - 1].fraction));
        expect(
          progress[i].phase.index,
          greaterThanOrEqualTo(progress[i - 1].phase.index),
        );
      }
      expect(
        progress.map((p) => p.phase).toSet(),
        GenerationPhase.values.toSet(),
      );
      expect(events.last, isA<GenerationDone>());
      expect(events.whereType<GenerationDone>(), hasLength(1));
      expect(
        (events.last as GenerationDone).puzzle,
        const Generator().generate(shape, 1, Difficulty.easy),
      );
    });
  }

  test('the phase follows the design thresholds', () {
    expect(GenerationPhase.of(0.44), GenerationPhase.generating);
    expect(GenerationPhase.of(0.45), GenerationPhase.carving);
    expect(GenerationPhase.of(0.849), GenerationPhase.carving);
    expect(GenerationPhase.of(0.85), GenerationPhase.ready);
    expect(kGenerationCeiling, const Duration(seconds: 15));
  });

  test('a fast request never fails', () async {
    final events = await generateInIsolate(
      const GenerationRequest(GridShape.mini, 3, Difficulty.easy),
    ).toList();
    expect(events.whereType<GenerationFailedEvent>(), isEmpty);
  });

  test(
    'the ceiling kills the worker and says so; nothing arrives after',
    () async {
      generateOverride = slowGenerate;
      Isolate? spawned;
      onIsolateSpawned = (i) => spawned = i;
      final events = <GenerationEvent>[];
      final done = Completer<void>();
      generateInIsolate(
        const GenerationRequest(GridShape.classic, 5, Difficulty.easy),
        timeout: const Duration(milliseconds: 50),
      ).listen(events.add, onDone: done.complete);
      await done.future;
      expect(
        events.whereType<GenerationFailedEvent>(),
        hasLength(1),
        reason: 'exactly one failure event',
      );
      final failure = events.last as GenerationFailedEvent;
      final reason = failure.reason as GenerationTimeout;
      expect(reason.seed, 5);
      expect(reason.ceiling, const Duration(milliseconds: 50));
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(events.last, same(failure), reason: 'nothing after the timeout');
      expect(events.whereType<GenerationDone>(), isEmpty);
      expect(
        await answers(spawned!, const Duration(milliseconds: 100)),
        isFalse,
      );
    },
  );

  test(
    'cancelling kills the worker within 100 ms; nothing arrives after',
    () async {
      generateOverride = slowGenerate;
      final spawnedC = Completer<Isolate>();
      onIsolateSpawned = spawnedC.complete;
      final events = <GenerationEvent>[];
      final sub = generateInIsolate(
        const GenerationRequest(GridShape.classic, 5, Difficulty.easy),
        timeout: null,
      ).listen(events.add);
      final isolate = await spawnedC.future;
      expect(
        await answers(isolate, const Duration(seconds: 2)),
        isTrue,
        reason: 'the worker is alive before the cancel',
      );
      await sub.cancel();
      // A ping sent in the same instant as the kill can still be answered
      // (measured: yes at 4 ms, no at 50 ms), so poll until it goes quiet and
      // require that before 100 ms.
      final clock = Stopwatch()..start();
      var alive = true;
      while (alive && clock.elapsed < const Duration(milliseconds: 100)) {
        alive = await answers(isolate, const Duration(milliseconds: 20));
      }
      expect(alive, isFalse, reason: 'still answering 100 ms after cancel');
      final seen = events.length;
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(events.length, seen, reason: 'no late progress or result');
      expect(events.whereType<GenerationDone>(), isEmpty);
    },
  );

  // The ceiling is a Timer, so a zone that holds every timer the wrapper
  // makes, and fires them by hand, runs the clock past 15 s without the real
  // wait. The slow worker never finishes, so only a timer can end the stream.
  for (final (timeout, ends) in [(kGenerationCeiling, true), (null, false)]) {
    test('timeout: $timeout ${ends ? 'ends' : 'does not end'} a generation '
        'still running past the 15 s ceiling', () async {
      generateOverride = slowGenerate;
      final held = <_HeldTimer>[];
      final events = <GenerationEvent>[];
      final sub = runZoned(
        () => generateInIsolate(
          const GenerationRequest(GridShape.classic, 5, Difficulty.easy),
          timeout: timeout,
        ).listen(events.add),
        zoneSpecification: ZoneSpecification(
          createTimer: (self, parent, zone, duration, callback) {
            final timer = _HeldTimer(duration, callback);
            held.add(timer);
            return timer;
          },
        ),
      );
      for (final timer in held) {
        if (timer.duration <= const Duration(seconds: 16)) timer.fire();
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(
        events.whereType<GenerationFailedEvent>().map((e) => e.reason),
        ends ? [isA<GenerationTimeout>()] : isEmpty,
        reason: ends
            ? 'the ceiling fails the request at 15 s'
            : 'a null timeout sets no ceiling, so nothing fails at 16 s',
      );
      await sub.cancel();
    });
  }

  test('running out of attempts is an event carrying the seed', () async {
    // Real: 9×9 Expert from seed 1 needs more than one attempt.
    final events = await generateInIsolate(
      const GenerationRequest(
        GridShape.classic,
        1,
        Difficulty.expert,
        maxAttempts: 1,
      ),
    ).toList();
    expect(
      events.whereType<GenerationFailedEvent>(),
      hasLength(1),
      reason: 'exactly one failure event',
    );
    final reason = (events.last as GenerationFailedEvent).reason;
    expect(reason, isA<AttemptsExhausted>());
    expect((reason as AttemptsExhausted).seed, 1);
    expect(reason.cause.attempts, 1);
  });

  test(
    'a GenerationFailed in the worker arrives as AttemptsExhausted',
    () async {
      generateOverride = exhaustedGenerate;
      final events = await generateInIsolate(
        const GenerationRequest(GridShape.classic, 8, Difficulty.hard),
      ).toList();
      expect(
        events.whereType<GenerationFailedEvent>(),
        hasLength(1),
        reason: 'exactly one failure event',
      );
      final reason = (events.last as GenerationFailedEvent).reason;
      expect(reason, isA<AttemptsExhausted>());
      expect((reason as AttemptsExhausted).seed, 8);
      expect(reason.cause.attempts, 7);
    },
  );

  test('any other worker error is an UnexpectedError event', () async {
    generateOverride = brokenGenerate;
    final events = await generateInIsolate(
      const GenerationRequest(GridShape.classic, 8, Difficulty.hard),
    ).toList();
    expect(
      events.whereType<GenerationFailedEvent>(),
      hasLength(1),
      reason: 'exactly one failure event',
    );
    final reason = (events.last as GenerationFailedEvent).reason;
    expect(reason, isA<UnexpectedError>());
    expect((reason as UnexpectedError).message, contains('boom'));
  });

  test('an unsupported pair throws before any stream exists', () {
    expect(
      () => generateInIsolate(
        const GenerationRequest(GridShape.mini, 1, Difficulty.evil),
      ),
      throwsA(isA<UnsupportedDifficulty>()),
    );
  });
}

/// A timer that never fires on its own; the test fires it.
final class _HeldTimer implements Timer {
  _HeldTimer(this.duration, this._callback);

  final Duration duration;
  final void Function() _callback;
  var _active = true;

  void fire() {
    if (!_active) return;
    _active = false;
    _callback();
  }

  @override
  void cancel() => _active = false;

  @override
  bool get isActive => _active;

  @override
  int get tick => 0;
}
