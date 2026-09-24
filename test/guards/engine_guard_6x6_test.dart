@Tags(['guard', 'slow'])
@Timeout(Duration(minutes: 10))
library;

// Invariants 2 and 4 on 6×6 (see engine_guard_support.dart). Tagged
// `slow` as well as `guard`: the gate and CI run it, but the mutation
// battery's per-mutation suite does not, and the mutations aimed at it set
// `slow=True`.

import 'package:flutter_test/flutter_test.dart';
import 'package:honest_sudoku/engine/engine.dart';

import 'engine_guard_support.dart';

void main() {
  engineGuard(GridShape.short, seeds: prSeeds(GridShape.short));
  gradedGoldens(GridShape.short);
}
