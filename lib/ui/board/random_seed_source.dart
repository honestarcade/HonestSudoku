// The app's seed source for new deals: uniform in the design's range.

import 'dart:math';

import 'package:honest_sudoku/game/game.dart';

/// Seeds from a system random source.
final class RandomSeedSource implements SeedSource {
  /// Creates the source. [random] replaces the system one, for tests.
  RandomSeedSource([Random? random]) : _random = random ?? Random();

  final Random _random;

  @override
  int next() => kSeedMin + _random.nextInt(kSeedMax - kSeedMin + 1);
}
