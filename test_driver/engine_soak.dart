// The engine on the device (#65): the real off-thread generator for every
// supported size and band, timed from request to board, every board checked
// by the solver's counter and the grader, and the golden fingerprints
// recomputed with the device's own arithmetic. Driven by
// test_driver/engine_soak_test.dart through tools/soak.sh; never shipped
// (the release build's target is lib/main.dart) and never part of the gate
// (it lives outside test/).
//
// This side measures and reports; the driver asserts. Each pair's summary is
// also logged as one `SOAK {json}` line, which tools/soak.sh collects with
// `adb logcat -d`.

import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:isolate';

import 'package:flutter/material.dart';
import 'package:flutter_driver/driver_extension.dart';
import 'package:honest_sudoku/engine/engine.dart';

import '../test/helpers/board_hash.dart';

/// A timed generation that never ends is not a measurement; one that runs
/// this long is recorded as a failure with its elapsed time. Ten times the
/// ceiling, so a run that merely overruns the ceiling is still measured.
const Duration kSoakRunLimit = Duration(seconds: 150);

/// The ungraded carves' seeds and the graded goldens' seed, as
/// test/helpers/golden_recorder.dart pins them. Written out here because
/// that file reads the fixture with dart:io paths the device does not have.
const List<int> kGoldenSeeds = [1, 2, 20260824];
const int kGradedGoldenSeed = 20260824;

/// One timed generation.
final class _Run {
  _Run({
    required this.seed,
    required this.wallMs,
    required this.generatingMs,
    required this.carvingMs,
    required this.gradingMs,
    this.attempts,
    this.problem,
  });

  final int seed;
  final int wallMs;
  final int generatingMs;
  final int carvingMs;
  final int gradingMs;
  final int? attempts;

  /// Why this board fails the soak, or null.
  final String? problem;
}

/// Generates (shape, seed, band) through [generateInIsolate], exactly as the
/// app asks for a board, and times it from the request to the board.
Future<_Run> _timed(GridShape shape, int seed, Difficulty d) async {
  final clock = Stopwatch()..start();
  int? carvingAt;
  int? gradingAt;
  final done = Completer<GenerationEvent>();
  final sub =
      generateInIsolate(
        GenerationRequest(shape, seed, d),
        timeout: kSoakRunLimit,
      ).listen((e) {
        switch (e) {
          case GenerationProgress(:final phase):
            final now = clock.elapsedMilliseconds;
            if (phase != GenerationPhase.generating) carvingAt ??= now;
            if (phase == GenerationPhase.ready) gradingAt ??= now;
          case GenerationDone() || GenerationFailedEvent():
            if (!done.isCompleted) done.complete(e);
        }
      });
  final event = await done.future;
  final wall = clock.elapsedMilliseconds;
  await sub.cancel();
  final carving = carvingAt ?? wall;
  final grading = gradingAt ?? wall;
  String? problem;
  int? attempts;
  switch (event) {
    case GenerationDone(:final puzzle):
      attempts = puzzle.attempts;
      final values = puzzle.startingValues();
      final solutions = countSolutions(shape, values);
      final g = grade(shape, values);
      if (solutions != 1) {
        problem = 'has $solutions solutions (counted up to 2), not exactly 1';
      } else if (puzzle.difficulty != d || g.band != d) {
        problem =
            'asked for ${d.label}, labelled ${puzzle.difficulty?.label}, '
            'grades ${g.band.label} (${g.technique.name})';
      } else if (puzzle.seed != seed || puzzle.shape != shape) {
        problem = 'answered seed ${puzzle.seed} ${puzzle.shape.label}';
      }
    case GenerationFailedEvent(:final reason):
      problem = 'no board: $reason';
    case GenerationProgress():
      problem = 'the stream ended on progress';
  }
  return _Run(
    seed: seed,
    wallMs: wall,
    generatingMs: carving,
    carvingMs: grading - carving,
    gradingMs: wall - grading,
    attempts: attempts,
    problem: problem,
  );
}

/// The mean of the two middle values of an even-length sorted list, the
/// middle one of an odd.
num _median(List<int> sorted) {
  final k = sorted.length;
  if (k.isOdd) return sorted[k ~/ 2];
  final twice = sorted[k ~/ 2 - 1] + sorted[k ~/ 2];
  return twice.isEven ? twice ~/ 2 : twice / 2;
}

/// One pair: an untimed warm-up, then seeds `1..seeds`, summarised.
Future<Map<String, Object?>> _soakPair(
  GridShape shape,
  Difficulty d,
  int seeds,
) async {
  // Warms the isolate path; discarded unchecked, as the table does not
  // report it.
  await generateInIsolate(GenerationRequest(shape, 0, d)).last;
  final runs = <_Run>[
    for (var seed = 1; seed <= seeds; seed++) await _timed(shape, seed, d),
  ];
  final times = [for (final r in runs) r.wallMs]..sort();
  final attempts = [
    for (final r in runs)
      if (r.attempts != null) r.attempts!,
  ]..sort();
  final wall = runs.fold<int>(0, (a, r) => a + r.wallMs);
  final carving = runs.fold<int>(0, (a, r) => a + r.carvingMs);
  final summary = <String, Object?>{
    'shape': shape.label.replaceAll('×', 'x'),
    'difficulty': d.key,
    'medianMs': _median(times).round(),
    'worstMs': times.last,
    'bestMs': times.first,
    'attemptsMedian': attempts.isEmpty ? null : _median(attempts),
    'attemptsWorst': attempts.isEmpty ? null : attempts.last,
    'seeds': seeds,
    'ceilingMs': kGenerationCeiling.inMilliseconds,
    'generatingMs': runs.fold<int>(0, (a, r) => a + r.generatingMs),
    'carvingMs': carving,
    'gradingMs': runs.fold<int>(0, (a, r) => a + r.gradingMs),
    'carvingPct': wall == 0 ? 0 : (carving * 100 / wall).round(),
    'worstSeed': runs.reduce((a, b) => b.wallMs > a.wallMs ? b : a).seed,
    'problems': [
      for (final r in runs)
        if (r.problem != null)
          'seed ${r.seed} ${shape.label} ${d.label}: ${r.problem}',
    ],
  };
  developer.log('SOAK ${jsonEncode(summary)}', name: 'honest_sudoku.soak');
  // Printed as well: in the profile build the log line never reached
  // logcat, the printed one did (sudoku-dev emulator, 2026-09-30, one
  // `I flutter` SOAK line per pair and no other).
  debugPrint('SOAK ${jsonEncode(summary)}');
  return summary;
}

/// Every golden fingerprint, in test/fixtures/golden_boards.json's shape,
/// computed on this device. Each in its own isolate, so the driver
/// extension stays responsive while a slow one runs.
Future<Map<String, Object?>> _goldens() async => {
  'boards': [
    for (final shape in GridShape.all)
      for (final seed in kGoldenSeeds)
        await Isolate.run(() {
          final p = const Generator().carveToUniqueness(shape, seed);
          return <String, Object>{
            'shape': shape.label.replaceAll('×', 'x'),
            'seed': seed,
            'hash': boardHash(p),
            'givenCount': p.givenCount,
          };
        }),
  ],
  'graded': [
    for (final shape in GridShape.all)
      for (final d in supportedDifficulties(shape))
        await Isolate.run(() {
          final p = const Generator().generate(shape, kGradedGoldenSeed, d);
          return <String, Object>{
            'shape': shape.label.replaceAll('×', 'x'),
            'difficulty': d.key,
            'seed': kGradedGoldenSeed,
            'hash': boardHash(p),
            'technique': p.technique!.name,
            'givenCount': p.givenCount,
            'attempts': p.attempts!,
          };
        }),
  ],
};

/// Answers the driver. `pairs` lists the supported pairs;
/// `pair:<shape>:<band>:<seeds>` soaks one; `goldens` recomputes the
/// fingerprints.
Future<String> _answer(String? request) async {
  final parts = (request ?? '').split(':');
  return jsonEncode(switch (parts.first) {
    'pairs' => [
      for (final shape in GridShape.all)
        for (final d in supportedDifficulties(shape))
          '${shape.label.replaceAll('×', 'x')}:${d.key}',
    ],
    'pair' => await _soakPair(
      GridShape.byLabel(parts[1]),
      Difficulty.byKey(parts[2]),
      int.parse(parts[3]),
    ),
    'goldens' => await _goldens(),
    _ => throw ArgumentError.value(request, 'request', 'unknown'),
  });
}

void main() {
  enableFlutterDriverExtension(handler: _answer);
  runApp(
    const Directionality(
      textDirection: TextDirection.ltr,
      child: ColoredBox(
        color: Color(0xFF0B1B2E),
        child: Center(child: Text('engine soak')),
      ),
    ),
  );
}
