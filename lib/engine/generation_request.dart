// What the off-thread generator is asked for.

import 'difficulty.dart';
import 'grid.dart';

/// A request to generate one board.
final class GenerationRequest {
  /// Creates a request. [maxAttempts] overrides the generator's limit, for
  /// tests.
  const GenerationRequest(
    this.shape,
    this.seed,
    this.difficulty, {
    this.maxAttempts,
  });

  /// The size.
  final GridShape shape;

  /// The seed.
  final int seed;

  /// The band.
  final Difficulty difficulty;

  /// Replaces the generator's attempt limit when set.
  final int? maxAttempts;

  @override
  bool operator ==(Object other) =>
      other is GenerationRequest &&
      other.shape == shape &&
      other.seed == seed &&
      other.difficulty == difficulty &&
      other.maxAttempts == maxAttempts;

  @override
  int get hashCode => Object.hash(shape, seed, difficulty, maxAttempts);

  @override
  String toString() =>
      'GenerationRequest(${shape.label}, seed $seed, ${difficulty.label})';
}
