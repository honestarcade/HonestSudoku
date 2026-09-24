import 'package:flutter_test/flutter_test.dart';
import 'package:honest_sudoku/engine/engine.dart';

void main() {
  test('the first ten outputs for seed 20260824 match the design rnd', () {
    // Computed once by running the design file's own `rnd` (Honest
    // Sudoku.dc.html, line 965) in node v24.15.0 on 2026-09-23, and pinned.
    final rng = Rng(20260824);
    expect(
      [for (var i = 0; i < 10; i++) rng.nextUint32()],
      [
        1751195911,
        1704927812,
        1089152012,
        2552915171,
        1176881197,
        117546792,
        1098392341,
        3133516670,
        298222747,
        3802768956,
      ],
    );
  });

  test('nextDouble is the raw output over 2^32', () {
    final a = Rng(7);
    final b = Rng(7);
    expect(a.nextDouble(), b.nextUint32() / 4294967296);
  });

  test('seeds are masked to 32 bits; 0 is legal', () {
    expect(Rng(-1).nextUint32(), Rng(0xFFFFFFFF).nextUint32());
    expect(Rng(1 << 32).nextUint32(), Rng(0).nextUint32());
  });

  test('a different seed gives a different stream', () {
    expect(Rng(1).nextUint32(), isNot(Rng(2).nextUint32()));
  });

  test('shuffle is a permutation and nextInt refuses a bad bound', () {
    final list = Rng(3).shuffle(List.generate(20, (i) => i));
    expect(list.toSet().length, 20);
    expect(list, isNot(List.generate(20, (i) => i)));
    expect(() => Rng(1).nextInt(0), throwsArgumentError);
  });
}
