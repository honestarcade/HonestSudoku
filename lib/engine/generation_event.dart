// What the off-thread generator reports: progress with the loading screen's
// phase, then exactly one of a finished board or a failure.

import 'difficulty.dart';
import 'generator.dart';
import 'puzzle.dart';

/// The loading screen's three labels.
enum GenerationPhase {
  /// Building the full grid: below 45 %.
  generating,

  /// Removing givens: 45 % to 85 %.
  carving,

  /// Grading and handing over: 85 % and above.
  ready;

  /// The phase the loading screen shows at [fraction].
  static GenerationPhase of(double fraction) => fraction < kProgressCarving
      ? generating
      : fraction < kProgressGrading
      ? carving
      : ready;
}

/// An event on the generation stream.
sealed class GenerationEvent {
  const GenerationEvent();
}

/// Progress in `[0, 1]`, never falling, with its phase.
final class GenerationProgress extends GenerationEvent {
  /// Creates a progress event; the phase follows from [fraction].
  GenerationProgress(this.fraction) : phase = GenerationPhase.of(fraction);

  /// How far along, `0.0` to `1.0`.
  final double fraction;

  /// The label the loading screen shows.
  final GenerationPhase phase;

  @override
  bool operator ==(Object other) =>
      other is GenerationProgress && other.fraction == fraction;

  @override
  int get hashCode => fraction.hashCode;

  @override
  String toString() => 'GenerationProgress($fraction, ${phase.name})';
}

/// The finished board. Always the last event of a successful run.
final class GenerationDone extends GenerationEvent {
  /// Creates the event.
  const GenerationDone(this.puzzle);

  /// The board.
  final Puzzle puzzle;

  @override
  bool operator ==(Object other) =>
      other is GenerationDone && other.puzzle == puzzle;

  @override
  int get hashCode => puzzle.hashCode;

  @override
  String toString() => 'GenerationDone($puzzle)';
}

/// Generation ended without a board. Always the last event of a failed run.
///
/// Named so it cannot clash with the engine's [GenerationFailed] exception,
/// which [AttemptsExhausted] carries.
final class GenerationFailedEvent extends GenerationEvent {
  /// Creates the event.
  const GenerationFailedEvent(this.reason);

  /// Why.
  final GenerationFailure reason;

  @override
  bool operator ==(Object other) =>
      other is GenerationFailedEvent && other.reason == reason;

  @override
  int get hashCode => reason.hashCode;

  @override
  String toString() => 'GenerationFailedEvent($reason)';
}

/// Why a generation ended without a board.
sealed class GenerationFailure {
  const GenerationFailure();
}

/// The time ceiling passed.
final class GenerationTimeout extends GenerationFailure {
  /// Creates the failure.
  const GenerationTimeout({
    required this.seed,
    required this.ceiling,
    required this.elapsed,
    required this.lastFraction,
  });

  /// The seed asked for.
  final int seed;

  /// The ceiling that passed.
  final Duration ceiling;

  /// How long the worker had run.
  final Duration elapsed;

  /// The last progress reported.
  final double lastFraction;

  @override
  bool operator ==(Object other) =>
      other is GenerationTimeout &&
      other.seed == seed &&
      other.ceiling == ceiling &&
      other.elapsed == elapsed &&
      other.lastFraction == lastFraction;

  @override
  int get hashCode => Object.hash(seed, ceiling, elapsed, lastFraction);

  @override
  String toString() =>
      'GenerationTimeout(seed $seed after ${elapsed.inMilliseconds} ms)';
}

/// The generator used every attempt it was allowed.
final class AttemptsExhausted extends GenerationFailure {
  /// Creates the failure.
  const AttemptsExhausted(this.cause);

  /// The engine's exception, with shape, band, seed and attempts.
  final GenerationFailed cause;

  /// The seed asked for.
  int get seed => cause.seed;

  @override
  bool operator ==(Object other) =>
      other is AttemptsExhausted && other.cause == cause;

  @override
  int get hashCode => cause.hashCode;

  @override
  String toString() => 'AttemptsExhausted($cause)';
}

/// Anything else went wrong in the worker.
final class UnexpectedError extends GenerationFailure {
  /// Creates the failure.
  const UnexpectedError(this.message, this.stack);

  /// The error's text.
  final String message;

  /// The worker's stack trace, as text.
  final String stack;

  @override
  bool operator ==(Object other) =>
      other is UnexpectedError &&
      other.message == message &&
      other.stack == stack;

  @override
  int get hashCode => Object.hash(message, stack);

  @override
  String toString() => 'UnexpectedError($message)';
}
