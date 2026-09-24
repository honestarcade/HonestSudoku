// Board generation off the UI thread, with progress, a time ceiling and
// cancel.
//
// The generator itself is synchronous and clock-free, so it stays
// deterministic; this wrapper owns the isolate, the clock and the timer. It
// is the one engine file the source guard lets use them
// (test/guards/engine_rules.dart, `engineClockAllowed`).
//
// `Isolate.run` is not used: progress needs a live SendPort for the whole
// run, and a timeout or a cancel needs the Isolate handle to kill.

import 'dart:async';
import 'dart:isolate';

import 'difficulty.dart';
import 'generation_event.dart';
import 'generation_request.dart';
import 'generator.dart';
import 'puzzle.dart';

/// The owner's ceiling on one generation: past it the player gets a clear
/// failure rather than a spinner. The documented fallback for a slow
/// 16×16 request.
const Duration kGenerationCeiling = Duration(seconds: 15);

/// Makes the board, reporting progress. The real one is [Generator.generate].
typedef GenerateFn = Puzzle Function(
  GenerationRequest request,
  ProgressCallback onProgress,
);

/// The message a worker receives: where to report, what to make, and (in
/// tests) what makes it.
typedef WorkerMessage = (SendPort, GenerationRequest, GenerateFn?);

/// Tests only: replaces the generator inside the real worker (a slow one, a
/// failing one), so the worker's own error handling is what gets tested. Must
/// be a top-level or static function. Not `@visibleForTesting`: that
/// annotation lives in `package:meta`, which this app does not declare, and
/// declaring a package for one annotation is not a lean dependency
/// (invariant 3).
GenerateFn? generateOverride;

/// Tests only: called with each spawned isolate, so a test can check it has
/// gone.
void Function(Isolate)? onIsolateSpawned;

Puzzle _generate(GenerationRequest request, ProgressCallback onProgress) =>
    Generator(maxAttempts: request.maxAttempts).generate(
      request.shape,
      request.seed,
      request.difficulty,
      onProgress: onProgress,
    );

/// The worker: generate, report progress, send the board or the reason. A
/// failure is always sent as a value, never left to escape the isolate.
void generationWorker(WorkerMessage message) {
  final (port, request, generate) = message;
  try {
    final puzzle = (generate ?? _generate)(
      request,
      (f) => port.send(('progress', f)),
    );
    port.send(('done', puzzle));
  } on GenerationFailed catch (e) {
    port.send(('failed', AttemptsExhausted(e)));
  } on Object catch (e, stack) {
    port.send(('failed', UnexpectedError('$e', '$stack')));
  }
}

/// Generates [request] in a background isolate.
///
/// The stream is lazy and single-subscription: the isolate spawns when it is
/// listened to, and the [timeout] clock starts at the spawn. It emits
/// [GenerationProgress] events, never falling, starting at `0.0` and reaching
/// `1.0` before success, then exactly one [GenerationDone] or
/// [GenerationFailedEvent], and closes. Cancelling the subscription kills the
/// isolate. A null [timeout] disables the ceiling.
///
/// Throws [UnsupportedDifficulty] at once, before any stream exists, for a
/// pair the design does not offer. Every other failure is an event, never a
/// stream error.
Stream<GenerationEvent> generateInIsolate(
  GenerationRequest request, {
  Duration? timeout = kGenerationCeiling,
}) {
  if (!supportedDifficulties(request.shape).contains(request.difficulty)) {
    throw UnsupportedDifficulty(
      request.shape,
      request.difficulty,
      request.seed,
    );
  }

  late final StreamController<GenerationEvent> controller;
  final receive = ReceivePort();
  final errors = ReceivePort();
  final exits = ReceivePort();
  final clock = Stopwatch();
  Isolate? isolate;
  Timer? timer;
  var finished = false;
  var cancelled = false;
  var last = -1.0;

  void shutDown() {
    timer?.cancel();
    isolate?.kill(priority: Isolate.immediate);
    receive.close();
    errors.close();
    exits.close();
  }

  void progress(double f) {
    if (finished) return;
    final clamped = f < 0 ? 0.0 : (f > 1 ? 1.0 : f);
    if (clamped <= last) return;
    last = clamped;
    controller.add(GenerationProgress(clamped));
  }

  void finish(GenerationEvent event) {
    if (finished) return;
    if (event is GenerationDone) progress(1.0);
    finished = true;
    shutDown();
    controller.add(event);
    unawaited(controller.close());
  }

  receive.listen((message) {
    switch (message) {
      case ('progress', final double f):
        progress(f);
      case ('done', final Puzzle p):
        finish(GenerationDone(p));
      case ('failed', final GenerationFailure reason):
        finish(GenerationFailedEvent(reason));
      default:
        finish(
          GenerationFailedEvent(
            UnexpectedError('unexpected worker message: $message', ''),
          ),
        );
    }
  });
  errors.listen((error) {
    final parts = error as List<Object?>;
    finish(
      GenerationFailedEvent(UnexpectedError('${parts[0]}', '${parts[1]}')),
    );
  });
  exits.listen((_) {
    finish(
      GenerationFailedEvent(
        const UnexpectedError('the worker exited without a result', ''),
      ),
    );
  });

  Future<void> spawn() async {
    progress(0.0);
    clock.start();
    if (timeout != null) {
      timer = Timer(timeout, () {
        finish(
          GenerationFailedEvent(
            GenerationTimeout(
              seed: request.seed,
              ceiling: timeout,
              elapsed: clock.elapsed,
              lastFraction: last < 0 ? 0.0 : last,
            ),
          ),
        );
      });
    }
    try {
      final spawned = await Isolate.spawn<WorkerMessage>(
        generationWorker,
        (receive.sendPort, request, generateOverride),
        onError: errors.sendPort,
        onExit: exits.sendPort,
      );
      if (cancelled || finished) {
        spawned.kill(priority: Isolate.immediate);
        return;
      }
      isolate = spawned;
      onIsolateSpawned?.call(spawned);
    } on Object catch (e, stack) {
      finish(GenerationFailedEvent(UnexpectedError('$e', '$stack')));
    }
  }

  controller = StreamController<GenerationEvent>(
    onListen: () => unawaited(spawn()),
    onCancel: () {
      cancelled = true;
      finished = true;
      shutDown();
    },
  );
  return controller.stream;
}
