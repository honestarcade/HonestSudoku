@Tags(['weekly'])
@Timeout(Duration(minutes: 90))
library;

// The weekly tier: 200 seeds for every supported size and band, 16×16 Evil
// and its graded golden included. Excluded from the gate and the pull-request
// workflow by its tag; `.github/workflows/engine-nightly.yml` runs it every
// Sunday and on demand. ENGINE_WEEKLY_SEEDS overrides the count for a quick
// manual run.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:honest_sudoku/engine/engine.dart';

import 'engine_guard_support.dart';

void main() {
  final seeds =
      int.tryParse(Platform.environment['ENGINE_WEEKLY_SEEDS'] ?? '') ?? 200;
  for (final shape in GridShape.all) {
    engineGuard(shape, seeds: seeds);
  }
  gradedGoldens(
    GridShape.monster,
    skip: {
      Difficulty.easy,
      Difficulty.medium,
      Difficulty.hard,
      Difficulty.expert,
    },
  );
}
