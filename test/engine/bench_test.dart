@Tags(['bench'])
library;

// Host timings of the synchronous generator: five seeds per supported size
// and band, after one warm-up. Not part of the gate (`bench` is excluded);
// run with `flutter test --tags bench`.
//
// The asserted medians are budgets for the host: they keep the engine guard
// tier affordable. They are not the device budget (9×9 within 1 s and 16×16
// within 5 s on a mid-range phone, 15 s ceiling), which M6 measures on
// hardware.

import 'package:flutter_test/flutter_test.dart';
import 'package:honest_sudoku/engine/engine.dart';

/// Host median budget for (shape, band), or null when only printed.
Duration? _budget(GridShape shape, Difficulty d) => switch (shape.n) {
  9 => const Duration(milliseconds: 500),
  16 when d == Difficulty.evil => const Duration(seconds: 8),
  16 => const Duration(seconds: 3),
  _ => null,
};

void main() {
  final rows = <String>[];

  setUpAll(() {
    const Generator().generate(GridShape.classic, 99, Difficulty.medium);
  });

  tearDownAll(() {
    // ignore: avoid_print
    print(
      [
        '| size | band | median ms | min ms | max ms |',
        '|---|---|---|---|---|',
        ...rows,
      ].join('\n'),
    );
  });

  for (final shape in GridShape.all) {
    for (final d in supportedDifficulties(shape)) {
      test('${shape.label} ${d.label}', () {
        final times = <int>[];
        for (var seed = 1; seed <= 5; seed++) {
          final clock = Stopwatch()..start();
          const Generator().generate(shape, seed, d);
          times.add(clock.elapsedMilliseconds);
        }
        times.sort();
        final median = times[2];
        rows.add(
          '| ${shape.label} | ${d.label} | $median | ${times.first} | '
          '${times.last} |',
        );
        final budget = _budget(shape, d);
        if (budget != null) {
          expect(
            median,
            lessThan(budget.inMilliseconds),
            reason:
                'bench: ${shape.label} ${d.label} median ${median}ms is over '
                'the ${budget.inMilliseconds}ms host budget',
          );
        }
      }, timeout: const Timeout(Duration(minutes: 5)));
    }
  }
}
