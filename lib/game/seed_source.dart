// Where a new deal's seed comes from. An interface, so the model stays free
// of randomness (the game-imports guard refuses dart:math here) and tests can
// feed a known sequence; the app's random source lives with the controller.

/// The lowest seed a new deal draws, as the design's `startNew` draws them.
const int kSeedMin = 1000;

/// The highest seed a new deal draws.
const int kSeedMax = 900999;

/// Supplies seeds for new deals.
abstract interface class SeedSource {
  /// The next seed, in `kSeedMin..kSeedMax`.
  int next();
}

/// How many times a new deal redraws a seed that repeats the current one;
/// the last draw is accepted.
const int kSeedRedraws = 10;
