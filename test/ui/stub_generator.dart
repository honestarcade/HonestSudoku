// Stand-ins for the isolate generator in widget tests: real isolates do not
// run under the test's fake clock.

import 'dart:async';

import 'package:honest_sudoku/engine/engine.dart';
import 'package:honest_sudoku/game/game.dart';

import '../game/fixtures.dart';

/// Records requests and answers each with a fixture board, or a failure.
final class StubGenerator {
  /// Requests seen, in order.
  final requests = <GenerationRequest>[];

  /// When set, the next requests fail with this.
  GenerationFailure? failWith;

  /// When true, requests never finish (until cancelled).
  var hang = false;

  /// Set when a hanging request was cancelled.
  var cancelled = false;

  /// The generator function.
  Stream<GenerationEvent> call(GenerationRequest r) {
    requests.add(r);
    if (hang) {
      final c = StreamController<GenerationEvent>(
        onCancel: () => cancelled = true,
      );
      c.add(GenerationProgress(.3));
      return c.stream;
    }
    final fail = failWith;
    return Stream.fromIterable([
      GenerationProgress(.5),
      if (fail != null)
        GenerationFailedEvent(fail)
      else
        GenerationDone(
          fixturePuzzle(r.shape, difficulty: r.difficulty, seed: r.seed),
        ),
    ]);
  }
}

/// A timeout failure.
const GenerationFailure timeoutFailure = GenerationTimeout(
  seed: 1,
  ceiling: Duration(seconds: 15),
  elapsed: Duration(seconds: 15),
  lastFraction: .5,
);

/// Seeds 5000, 5001, …
final class CountingSeeds implements SeedSource {
  var _next = 5000;
  @override
  int next() => _next++;
}
