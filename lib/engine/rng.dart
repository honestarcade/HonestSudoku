// The design's seeded PRNG, `rnd(seed)`: a mulberry32 variant.
//
// JavaScript does this arithmetic in 32-bit integers through `Math.imul`,
// `>>>` and `^`. Dart's VM integers are 64-bit, so every step is masked back
// to 32 bits explicitly; with that, the sequence is the same on every device
// and matches the design's. The Dart VM is the app's only target — on the web
// the multiply would lose precision, which is why this is not written for it.

const int _mask32 = 0xFFFFFFFF;

int _imul(int a, int b) => (a * b) & _mask32;

/// A seeded 32-bit generator with the design's `rnd` algorithm.
final class Rng {
  /// Seeds the generator. The seed is masked to 32 bits, as JavaScript's
  /// `seed >>> 0` does, so 0 and negative seeds are legal.
  Rng(int seed) : _a = seed & _mask32;

  int _a;

  /// The next raw output, `0 <= x < 2^32`.
  int nextUint32() {
    _a = (_a + 0x6D2B79F5) & _mask32;
    var t = _imul(_a ^ (_a >> 15), 1 | _a);
    t = ((t + _imul(t ^ (t >> 7), 61 | t)) & _mask32) ^ t;
    return (t ^ (t >> 14)) & _mask32;
  }

  /// The design's `r()`: the next output divided by 2^32, in `[0, 1)`.
  double nextDouble() => nextUint32() / 4294967296;

  /// `floor(r() * bound)`, as the design's shuffle draws an index.
  int nextInt(int bound) {
    if (bound <= 0) {
      throw ArgumentError.value(bound, 'bound', 'must be positive');
    }
    return (nextDouble() * bound).floor();
  }

  /// The design's `shuf`: Fisher–Yates from the end, in place. Returns [list].
  List<T> shuffle<T>(List<T> list) {
    for (var i = list.length - 1; i > 0; i--) {
      final j = nextInt(i + 1);
      final t = list[i];
      list[i] = list[j];
      list[j] = t;
    }
    return list;
  }
}
