// Drives test_driver/engine_soak.dart (#65): soaks every supported pair,
// then asserts. A plain program, not a test suite: the host runs it under
// `flutter drive`, and it exits non-zero when any assertion fails — after
// every pair has run, because the whole table is the artifact.
//
// The assertions: every board has exactly one solution (more than one and
// fewer than one both fail) and grades to the band requested; every
// generation produced a board; each pair's worst wall-clock time is within
// the ceiling unless tools/soak.sh lists the pair as an accepted exceedance;
// and the golden fingerprints computed on the device equal the committed
// host values in test/fixtures/golden_boards.json.
//
// Environment, set by tools/soak.sh: SOAK_SEEDS (default 20), SOAK_EXCEED
// (comma-separated `<shape>:<band>` pairs accepted over the ceiling),
// SOAK_OUT (where the verdicts are written as JSON).

import 'dart:convert';
import 'dart:io';

import 'package:flutter_driver/flutter_driver.dart';

Future<void> main() async {
  final env = Platform.environment;
  final seeds = int.tryParse(env['SOAK_SEEDS'] ?? '') ?? 20;
  final exceed = {
    for (final p in (env['SOAK_EXCEED'] ?? '').split(','))
      if (p.trim().isNotEmpty) p.trim(),
  };
  final out = File(env['SOAK_OUT'] ?? 'build/soak-last.json');
  final failures = <String>[];
  final notes = <String>[];
  final pairs = <Map<String, Object?>>[];
  Map<String, Object?>? goldens;

  final driver = await FlutterDriver.connect();
  try {
    final names = (jsonDecode(await driver.requestData('pairs')) as List)
        .cast<String>();
    stdout.writeln('soak: ${names.length} pairs, seeds 1..$seeds');
    for (final name in names) {
      final clock = Stopwatch()..start();
      final p = jsonDecode(
        await driver.requestData(
          'pair:$name:$seeds',
          timeout: const Duration(hours: 2),
        ),
      ) as Map<String, Object?>;
      pairs.add(p);
      stdout.writeln(
        '  $name  median ${p['medianMs']} ms  worst ${p['worstMs']} ms '
        '(seed ${p['worstSeed']})  best ${p['bestMs']} ms  attempts '
        '${p['attemptsMedian']}/${p['attemptsWorst']}  carving '
        '${p['carvingPct']}%  [${clock.elapsed.inSeconds} s]',
      );
      for (final problem in (p['problems']! as List).cast<String>()) {
        failures.add('soak-board: $problem');
      }
      final worst = p['worstMs']! as int;
      final ceiling = p['ceilingMs']! as int;
      if (worst > ceiling) {
        final line =
            'soak-ceiling: $name worst ${worst}ms (seed ${p['worstSeed']}) '
            'is over the ${ceiling}ms ceiling';
        exceed.contains(name)
            ? notes.add('$line — accepted by tools/soak.sh')
            : failures.add(line);
      }
      if ((p['carvingPct']! as int) > 50) {
        notes.add(
          'soak-phase: $name spends ${p['carvingPct']}% of its wall clock '
          'in CARVING GIVENS, over the half #65 set as the point the '
          "loading screen's labels mislead",
        );
      }
    }

    stdout.writeln('soak: golden fingerprints');
    goldens = jsonDecode(
      await driver.requestData('goldens', timeout: const Duration(hours: 1)),
    ) as Map<String, Object?>;
    final committed = jsonDecode(
      File('test/fixtures/golden_boards.json').readAsStringSync(),
    ) as Map<String, Object?>;
    for (final section in ['boards', 'graded']) {
      final want = (committed[section]! as List).map(jsonEncode).toList();
      final got = (goldens[section]! as List).map(jsonEncode).toList();
      if (want.length != got.length) {
        failures.add(
          'soak-golden: $section has ${got.length} entries on the device, '
          '${want.length} committed',
        );
      }
      for (final entry in got) {
        if (!want.contains(entry)) {
          failures.add(
            'soak-golden: the device computed $entry, which is not the '
            'committed host value (reproduce on the host with that seed, '
            'shape and difficulty)',
          );
        }
      }
    }
    stdout.writeln(
      '  ${failures.where((f) => f.startsWith('soak-golden')).isEmpty ? 'all equal the host' : 'MISMATCH'}',
    );
  } on Object catch (e) {
    failures.add('soak-driver: $e');
  } finally {
    await driver.close();
  }

  out
    ..createSync(recursive: true)
    ..writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert({
        'seeds': seeds,
        'pairs': pairs,
        'goldensEqual':
            goldens != null &&
            !failures.any((f) => f.startsWith('soak-golden')),
        'failures': failures,
        'notes': notes,
      }),
    );
  for (final n in notes) {
    stdout.writeln('NOTE $n');
  }
  for (final f in failures) {
    stderr.writeln('FAIL $f');
  }
  stdout.writeln(failures.isEmpty ? 'soak: PASSED' : 'soak: FAILED');
  exit(failures.isEmpty ? 0 : 1);
}
