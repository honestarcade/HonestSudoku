// Drives test_driver/app_flow.dart (#66): the installed app, end to end,
// with nothing stubbed. tools/e2e.sh runs it twice with a process death
// between: E2E_PHASE=play plays a whole game to a win, applies settings and
// leaves a second game part-played; the script then force-stops the app;
// E2E_PHASE=restore relaunches the same installed binary, with its data, and
// asserts what came back.
//
// A plain program under `flutter drive`, not a test suite: package:test is
// not a dependency, so each phase of the flow is a named step with its own
// expectation, run in order. The first failing step stops the run, is named
// in the output, and makes the exit non-zero.
//
// Environment, set by tools/e2e.sh: E2E_PHASE (play | restore),
// E2E_GENERATION_TIMEOUT (seconds to wait for a board), E2E_SAVED (the
// file the play phase leaves its part-played game in for the restore phase),
// E2E_REPORT (where the step list and timings are written as JSON).

import 'dart:convert';
import 'dart:io';

import 'package:flutter_driver/flutter_driver.dart';

/// A step's expectation did not hold.
final class StepFailed implements Exception {
  StepFailed(this.message);
  final String message;
  @override
  String toString() => message;
}

void expect(bool ok, String what) {
  if (!ok) throw StepFailed(what);
}

Future<void> main() async {
  final env = Platform.environment;
  final phase = env['E2E_PHASE'] ?? 'play';
  final genTimeout = int.tryParse(env['E2E_GENERATION_TIMEOUT'] ?? '') ?? 60;
  final saved = File(env['E2E_SAVED'] ?? 'build/e2e/saved.json');
  final report = File(env['E2E_REPORT'] ?? 'build/e2e/$phase.json');
  const wait = Duration(seconds: 10);

  final driver = await FlutterDriver.connect();
  final steps = <Map<String, Object?>>[];
  var failed = false;

  /// Runs [body] as the step [name], unless an earlier step failed.
  Future<void> step(String name, Future<void> Function() body) async {
    if (failed) {
      steps.add({'step': name, 'result': 'skipped'});
      return;
    }
    final clock = Stopwatch()..start();
    try {
      await body();
      steps.add({
        'step': name,
        'result': 'ok',
        'ms': clock.elapsedMilliseconds,
      });
      stdout.writeln('STEP ok    $name (${clock.elapsedMilliseconds} ms)');
    } on Object catch (e) {
      failed = true;
      steps.add({'step': name, 'result': 'failed', 'error': '$e'});
      stderr.writeln('STEP FAIL  $name: $e');
      try {
        final shot = File('${report.parent.path}/$phase-failed.png');
        shot.writeAsBytesSync(await driver.screenshot());
        stderr.writeln('  the screen at the failure: ${shot.path}');
      } on Object catch (_) {
        // A screenshot is a courtesy; the failure is already recorded.
      }
    }
  }

  Future<Map<String, Object?>> ask(String request) async =>
      jsonDecode(await driver.requestData(request, timeout: wait))
          as Map<String, Object?>;

  Future<Map<String, Object?>> state() => ask('state');

  Future<List<String>> texts(String key) async => (jsonDecode(
    await driver.requestData('texts:$key', timeout: wait),
  ) as List).cast<String>();

  Future<void> tap(String key) async {
    final f = find.byValueKey(key);
    try {
      await driver.scrollIntoView(f, timeout: wait);
      await driver.tap(f, timeout: wait);
      await driver.waitUntilNoTransientCallbacks(timeout: wait);
    } on DriverError catch (e) {
      throw StepFailed('tapping $key: ${e.message}');
    }
  }

  /// Taps [key] without waiting for animations to stop: the loading screen
  /// animates until the board arrives.
  Future<void> tapAndGo(String key) async {
    final f = find.byValueKey(key);
    try {
      await driver.scrollIntoView(f, timeout: wait);
      await driver.tap(f, timeout: wait);
    } on DriverError catch (e) {
      throw StepFailed('tapping $key: ${e.message}');
    }
  }

  Future<void> present(String key) =>
      driver.waitFor(find.byValueKey(key), timeout: wait);

  Future<void> absent(String key) =>
      driver.waitForAbsent(find.byValueKey(key), timeout: wait);

  List<int> ints(Object? list) => (list! as List).cast<int>();

  Future<void> waitForBoard() async {
    final g = await driver.requestData(
      'generated:$genTimeout',
      timeout: Duration(seconds: genTimeout + 10),
    );
    final r = jsonDecode(g) as Map<String, Object?>;
    expect(r['ok'] == true, 'generation: ${r['error']}');
    await present('board-frame');
  }

  /// Places [value] in cell [i]: select, then the pad.
  Future<void> place(int i, int value) async {
    await tap('cell-$i');
    await tap('pad-$value');
  }

  /// Fills every cell that is not already right with the solution, in index
  /// order, and expects the win.
  Future<void> playToWin() async {
    final s = await state();
    final values = ints(s['values']);
    final solution = ints(s['solution']);
    for (var i = 0; i < values.length; i++) {
      if (values[i] != solution[i]) await place(i, solution[i]);
    }
    final after = await state();
    expect(after['won'] == true, 'the board is full and right but not won');
    await present('overlay-over');
  }

  Future<void> expectStreak(int n) async {
    final t = await texts('tile-streak');
    expect(t.contains('$n'), 'the win card streak reads $t, not $n');
  }

  Future<void> expectStats(int solved, int started) async {
    await tap('menu-stats');
    final card = await texts('stats-card-solved');
    expect(
      card.contains('$solved') && card.contains('$started started'),
      'the Solved card reads $card, not $solved of $started started',
    );
    final pct = (solved * 100 / started).round();
    final row = await texts('stats-row-9×9');
    expect(
      row.contains('$solved / $started · $pct%'),
      'the 9×9 breakdown row reads $row',
    );
    await tap('stats-back');
    await present('menu-new-card');
  }

  /// Until the app has called runApp: a debug build is attached to before
  /// it has, and a finder then asserts rather than waits.
  Future<void> launched() async {
    final clock = Stopwatch()..start();
    while ((await state())['ready'] != true) {
      expect(clock.elapsed.inSeconds < 60, 'the app never started');
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
  }

  try {
    await launched();
    if (phase == 'play') {
      await step(
        'launch lands on the menu, with no game to continue',
        () async {
          await driver.waitFor(
            find.byValueKey('menu-new-card'),
            timeout: const Duration(seconds: 60),
          );
          await absent('menu-continue');
        },
      );

      await step('New puzzle opens setup; pick 9×9 Medium', () async {
        await tap('menu-new-card');
        await present('setup-start');
        await tap('setup-size-9×9');
        await tap('setup-diff-medium');
      });

      await step('Start waits for a real 9×9 Medium board', () async {
        await tapAndGo('setup-start');
        await waitForBoard();
        final s = await state();
        expect(
          s['shape'] == '9×9' && s['difficulty'] == 'medium',
          'the board is ${s['shape']} ${s['difficulty']}',
        );
        final values = ints(s['values']);
        expect(
          values.contains(0) && !ints(s['solution']).contains(0),
          'the board has no empty cell or its solution is not full',
        );
      });

      await step('entries from the solution win the game', playToWin);

      await step('the win card shows a streak of 1', () => expectStreak(1));

      await step('Main menu: Continue is gone', () async {
        await tap('btn-main-menu');
        await present('menu-new');
        await absent('menu-continue');
        final s = await state();
        expect(
          s['unfinished'] == false,
          'the controller holds an unfinished game',
        );
      });

      await step('Statistics shows the solve', () => expectStats(1, 1));

      await step('Settings: Paper, and row/column/box highlight off', () async {
        await tap('menu-settings');
        await tap('settings-theme-paper');
        await tap('settings-toggle-hlUnit');
        final s = await state();
        expect(
          s['themeKey'] == 'paper' && s['hlUnit'] == false,
          'settings read theme ${s['themeKey']}, hlUnit ${s['hlUnit']}',
        );
        await tap('settings-back');
        await present('menu-new-card');
      });

      await step('a new board renders Paper with no unit shading', () async {
        await tap('menu-new-card');
        await tapAndGo('setup-start');
        await waitForBoard();
        final s = await state();
        final n = s['n']! as int;
        final values = ints(s['values']);
        final i = values.indexOf(0);
        await tap('cell-$i');
        final (r, c) = (i ~/ n, i % n);
        final box = switch (n) {
          9 => 3,
          _ => throw StepFailed('the board is ${n}x$n, not 9×9'),
        };
        final peers = [
          for (var j = 0; j < n * n; j++)
            if (j != i &&
                (j ~/ n == r ||
                    j % n == c ||
                    (j ~/ n ~/ box == r ~/ box && j % n ~/ box == c ~/ box)))
              j,
        ];
        final themes = await ask('themes');
        final paper = themes['paper']! as Map<String, Object?>;
        final navy = themes['navy']! as Map<String, Object?>;
        final colours = await ask('cells:$i,${peers.join(',')}');
        expect(
          colours['$i'] == paper['selBg'],
          'the selected cell is ${colours['$i']}, not Paper selected '
          '${paper['selBg']}',
        );
        final shaded = [
          for (final j in peers)
            if (colours['$j'] != paper['cellBg']) '$j=${colours['$j']}',
        ];
        expect(
          shaded.isEmpty && paper['cellBg'] != navy['cellBg'],
          'with the highlight off, peers of $i are not the plain Paper cell '
          '${paper['cellBg']}: $shaded',
        );
      });

      await step(
        'a second game: six entries, one mistake, two notes',
        () async {
          final s = await state();
          final values = ints(s['values']);
          final solution = ints(s['solution']);
          final n = s['n']! as int;
          final empty = [
            for (var i = 0; i < values.length; i++)
              if (values[i] == 0) i,
          ];
          for (final i in empty.take(6)) {
            await place(i, solution[i]);
          }
          final wrongAt = empty[6];
          await place(wrongAt, solution[wrongAt] % n + 1);
          // The clock counts only while the board shows; the notes come after
          // five seconds so the save they cause carries a non-zero time.
          final clock = Stopwatch()..start();
          while ((await state())['elapsed']! as int < 6) {
            expect(clock.elapsed.inSeconds < 20, 'the clock is not running');
            await Future<void>.delayed(const Duration(milliseconds: 500));
          }
          final noteAt = empty[7];
          await tap('tool-notes');
          await tap('cell-$noteAt');
          final marks = [
            for (var v = 1; v <= n; v++)
              if (v != solution[noteAt]) v,
          ].take(2).toList();
          for (final v in marks) {
            await tap('pad-$v');
          }
          await tap('tool-notes');
          // Past the save's quarter-second debounce, so the disk holds it.
          await Future<void>.delayed(const Duration(seconds: 2));
          final after = await state();
          final notes = (after['notes']! as List).cast<List<Object?>>();
          expect(
            (after['mistakes']! as int) == 1 &&
                notes[noteAt].length == 2 &&
                ints(after['values'])[wrongAt] != solution[wrongAt] &&
                after['paused'] == false,
            'the part-played game is not as placed: mistakes '
            '${after['mistakes']}, notes ${notes[noteAt]}',
          );
          saved
            ..createSync(recursive: true)
            ..writeAsStringSync(jsonEncode(after));
        },
      );
    } else {
      final before =
          jsonDecode(saved.readAsStringSync()) as Map<String, Object?>;

      await step('relaunch after the kill offers Continue', () async {
        await driver.waitFor(
          find.byValueKey('menu-new-card'),
          timeout: const Duration(seconds: 60),
        );
        await present('menu-continue');
      });

      await step('settings survived the relaunch', () async {
        final s = await state();
        expect(
          s['themeKey'] == 'paper' && s['hlUnit'] == false,
          'after the relaunch the theme is ${s['themeKey']} and hlUnit '
          '${s['hlUnit']}',
        );
      });

      await step(
        'Continue restores board, notes, time and mistakes, paused',
        () async {
          await tap('menu-continue');
          // Paused hides the board, so the pause card is what shows.
          await present('overlay-pause');
          final s = await state();
          expect(s['seed'] == before['seed'], 'a different puzzle came back');
          expect(
            jsonEncode(s['values']) == jsonEncode(before['values']),
            'the entries did not come back',
          );
          expect(
            jsonEncode(s['notes']) == jsonEncode(before['notes']),
            'the pencil marks did not come back',
          );
          expect(
            s['mistakes'] == before['mistakes'],
            'mistakes came back as ${s['mistakes']}, not ${before['mistakes']}',
          );
          final restored = s['elapsed']! as int;
          final was = before['elapsed']! as int;
          expect(
            restored >= 5 && restored <= was + 1,
            'the clock came back at $restored s; it was $was s at the kill',
          );
          expect(
            s['paused'] == true,
            'the restored board is running, not paused',
          );
        },
      );

      await step('the restored game plays on to a win', () async {
        await tap('btn-resume');
        await absent('overlay-pause');
        await present('board-frame');
        await playToWin();
      });

      await step('the win card shows a streak of 2', () => expectStreak(2));

      await step('Statistics counts both solves', () async {
        await tap('btn-main-menu');
        await present('menu-new');
        await expectStats(2, 2);
      });
    }
  } finally {
    await driver.close();
    report
      ..createSync(recursive: true)
      ..writeAsStringSync(
        const JsonEncoder.withIndent('  ')
            .convert({'phase': phase, 'steps': steps}),
      );
  }
  stdout.writeln(failed ? 'e2e $phase: FAILED' : 'e2e $phase: PASSED');
  exit(failed ? 1 : 0);
}
