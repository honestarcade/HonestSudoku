// A stable fingerprint of a board, for the golden fixtures: 64-bit FNV-1a
// over `<n>;<solution, comma-separated>;<givens as 0/1>`.

import 'package:honest_sudoku/engine/engine.dart';

const int _fnvOffset = 0xcbf29ce484222325;
const int _fnvPrime = 0x100000001b3;

/// 64-bit FNV-1a of [text]'s code units, as 16 lower-case hex digits.
String fnv1a64(String text) => fnv1a64Of(text.codeUnits);

/// 64-bit FNV-1a of [units] (code units or bytes), as 16 lower-case hex
/// digits; the audio placeholders' digests use it over file bytes (#49).
String fnv1a64Of(Iterable<int> units) {
  var h = _fnvOffset;
  for (final unit in units) {
    h ^= unit;
    h *= _fnvPrime; // wraps at 64 bits on the VM
  }
  // Two 32-bit halves: a VM int is signed, so `toUnsigned(64)` cannot hold a
  // hash with its top bit set.
  return (h >>> 32).toRadixString(16).padLeft(8, '0') +
      (h & 0xFFFFFFFF).toRadixString(16).padLeft(8, '0');
}

/// The canonical string a board's hash is taken over.
String canonicalBoard(Puzzle p) =>
    '${p.shape.n};${p.solution.join(',')};'
    '${p.givens.map((g) => g ? '1' : '0').join()}';

/// The board's golden hash.
String boardHash(Puzzle p) => fnv1a64(canonicalBoard(p));
