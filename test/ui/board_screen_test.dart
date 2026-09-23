import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:honest_sudoku/engine/engine.dart';
import 'package:honest_sudoku/game/game.dart';
import 'package:honest_sudoku/ui/app.dart';
import 'package:honest_sudoku/ui/board/board_grid.dart';
import 'package:honest_sudoku/ui/board/board_screen.dart';
import 'package:honest_sudoku/ui/board/game_controller.dart';

import 'stub_generator.dart';

void setScreen(WidgetTester tester, double w, double h) {
  tester.view.physicalSize = Size(w, h);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

/// Pumps a BoardScreen over [c], starts [shape], and returns once the board
/// shows. Unmounts and disposes at the end of the test body via [run].
Future<void> screenTest(
  WidgetTester tester,
  Future<void> Function(GameController c, StubGenerator gen) body, {
  AppSettings settings = const AppSettings(),
  GridShape shape = GridShape.classic,
  double width = 390,
  double height = 844,
}) async {
  setScreen(tester, width, height);
  final gen = StubGenerator();
  final c = GameController(
    generator: gen.call,
    seeds: CountingSeeds(),
    settings: settings,
  );
  final routes = RouteObserver<ModalRoute<void>>();
  await tester.pumpWidget(
    MaterialApp(
      navigatorObservers: [routes],
      home: BoardScreen(controller: c, routeObserver: routes),
    ),
  );
  c.startNew(shape, Difficulty.medium);
  await tester.pump();
  await tester.pump();
  await body(c, gen);
  await tester.pumpWidget(const SizedBox());
  c.dispose();
}

/// The first empty cell and a wrong value for it.
(int, int) emptyAndWrong(GameState s) {
  final i = s.values.indexOf(0);
  return (i, s.solution[i] % s.n + 1);
}

Future<void> tapCellAndKey(WidgetTester tester, int cell, int value) async {
  await tester.tap(find.byKey(ValueKey('cell-$cell')));
  await tester.pump();
  await tester.tap(find.byKey(ValueKey('pad-$value')));
  await tester.pump();
}

void main() {
  group('through the app root', () {
    testWidgets('launch, place, tick, pause, resume, back, background', (
      tester,
    ) async {
      setScreen(tester, 390, 844);
      final gen = StubGenerator();
      await tester.pumpWidget(
        HonestSudokuApp(generator: gen.call, seeds: CountingSeeds()),
      );
      await tester.pump();
      expect(find.byType(BoardGrid), findsOneWidget);
      expect(find.text('❚❚ 9×9 · Medium'), findsOneWidget);

      // Place a number.
      await tester.tap(find.byKey(const ValueKey('cell-1')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('pad-2')));
      await tester.pump();
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('cell-1')),
          matching: find.text('2'),
        ),
        findsOneWidget,
      );

      // The clock runs only while unpaused.
      await tester.pump(const Duration(seconds: 2));
      expect(find.text('0:02'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('pause-button')));
      await tester.pump();
      expect(find.text('Paused'), findsOneWidget);
      expect(find.byType(BoardGrid), findsNothing);
      await tester.pump(const Duration(seconds: 3));
      await tester.tap(find.text('Resume'));
      await tester.pump();
      expect(find.text('0:02'), findsOneWidget);

      // Back pauses.
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(find.text('Paused'), findsOneWidget);
      await tester.tap(find.text('Resume'));
      await tester.pump();

      // Leaving the app pauses; coming back does not resume.
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(find.text('Paused'), findsOneWidget);

      // Back while paused goes to the main menu placeholder.
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('placeholder-destination')),
        findsOneWidget,
      );
      expect(find.text('Main menu'), findsOneWidget);
    });

    testWidgets('a failed first launch shows the failure with a retry that '
        're-requests', (tester) async {
      setScreen(tester, 390, 844);
      final gen = StubGenerator()..failWith = timeoutFailure;
      await tester.pumpWidget(
        HonestSudokuApp(generator: gen.call, seeds: CountingSeeds()),
      );
      await tester.pump();
      expect(find.text('GENERATION FAILED'), findsOneWidget);
      gen.failWith = null;
      await tester.tap(find.text('TRY AGAIN'));
      await tester.pump();
      await tester.pump();
      expect(gen.requests, hasLength(2));
      expect(find.byType(BoardGrid), findsOneWidget);
    });
  });

  group('every strike and announce mode', () {
    for (final strike in StrikeMode.values) {
      for (final announce in AnnounceMode.values) {
        testWidgets('${strike.name} × ${announce.name}', (tester) async {
          await screenTest(
            tester,
            settings: AppSettings(
              lastSetup: LastSetup(strikeMode: strike, announce: announce),
            ),
            (c, _) async {
              final limit = strike.limit;
              final entries = limit ?? 1;
              for (var k = 0; k < entries; k++) {
                final (cell, wrong) = emptyAndWrong(c.state!);
                await tapCellAndKey(tester, cell, wrong);
                if (k == 0) {
                  final showsBanner =
                      strike.countsMistakes && announce == AnnounceMode.now;
                  expect(
                    find.text('MISTAKE'),
                    showsBanner ? findsOneWidget : findsNothing,
                  );
                  if (strike == StrikeMode.zen) {
                    expect(find.text('ZEN'), findsOneWidget);
                  } else {
                    expect(
                      find.text('✕ 1${limit == null ? '' : '/$limit'}'),
                      findsOneWidget,
                    );
                  }
                }
              }
              expect(
                find.text('OUT OF STRIKES'),
                limit == null ? findsNothing : findsOneWidget,
              );
            },
          );
        });
      }
    }
  });

  testWidgets('manual notes: NOTES then a key leaves a pencil mark', (
    tester,
  ) async {
    await screenTest(tester, (c, _) async {
      final (cell, _) = emptyAndWrong(c.state!);
      await tester.tap(find.byKey(const ValueKey('tool-notes')));
      await tester.pump();
      await tapCellAndKey(tester, cell, 3);
      expect(c.state!.notes[cell], [3]);
      expect(c.state!.values[cell], 0);
    });
  });

  testWidgets('auto notes: candidates are there, the tool reads AUTO', (
    tester,
  ) async {
    await screenTest(
      tester,
      settings: const AppSettings(game: GameSettings(autoNotes: true)),
      (c, _) async {
        final (cell, _) = emptyAndWrong(c.state!);
        expect(find.text('AUTO'), findsOneWidget);
        expect(c.state!.notes[cell], isNotEmpty);
        await tester.tap(find.byKey(const ValueKey('tool-notes')));
        await tester.pump();
        expect(c.state!.noteMode, isFalse, reason: 'AUTO ignores taps');
      },
    );
  });

  testWidgets('undo then redo through the tools', (tester) async {
    await screenTest(tester, (c, _) async {
      final (cell, _) = emptyAndWrong(c.state!);
      final right = c.state!.solution[cell];
      await tapCellAndKey(tester, cell, right);
      await tester.tap(find.byKey(const ValueKey('tool-undo')));
      await tester.pump();
      expect(c.state!.values[cell], 0);
      await tester.tap(find.byKey(const ValueKey('tool-redo')));
      await tester.pump();
      expect(c.state!.values[cell], right);
    });
  });

  testWidgets('the pad drops 76 while a banner shows, and returns after', (
    tester,
  ) async {
    await screenTest(tester, (c, _) async {
      final before = tester.getTopLeft(find.byKey(const ValueKey('pad'))).dy;
      final (cell, wrong) = emptyAndWrong(c.state!);
      await tapCellAndKey(tester, cell, wrong);
      expect(find.byKey(const ValueKey('notice')), findsOneWidget);
      final during = tester.getTopLeft(find.byKey(const ValueKey('pad'))).dy;
      expect(during - before, 76);
      await tester.tap(find.byKey(const ValueKey('tool-erase')));
      await tester.pump();
      expect(find.byKey(const ValueKey('notice')), findsNothing);
      expect(tester.getTopLeft(find.byKey(const ValueKey('pad'))).dy, before);
    });
  });

  group('nothing overflows', () {
    for (final (w, h) in [(360.0, 640.0), (430.0, 932.0)]) {
      for (final shape in [GridShape.classic, GridShape.monster]) {
        for (final notice in [false, true]) {
          testWidgets('${shape.label} on ${w.toInt()}×${h.toInt()}'
              '${notice ? ' with a notice' : ''}', (tester) async {
            await screenTest(tester, shape: shape, width: w, height: h, (
              c,
              _,
            ) async {
              if (notice) {
                await tester.tap(find.byKey(const ValueKey('tool-check')));
                await tester.pump();
                expect(find.byKey(const ValueKey('notice')), findsOneWidget);
              }
              final screen = Offset.zero & Size(w, h);
              for (final key in [
                'pad',
                'tools',
                'cell-0',
                'cell-${shape.cellCount - 1}',
              ]) {
                // Half a pixel of slack for floating-point noise: at the
                // 430-wide cap the frame's left edge computes to -2.8e-14.
                final r = tester.getRect(find.byKey(ValueKey(key)));
                expect(
                  r.left >= -.5 &&
                      r.top >= -.5 &&
                      r.right <= w + .5 &&
                      r.bottom <= h + .5,
                  isTrue,
                  reason: '$key $r is off the $screen',
                );
              }
              final pad = tester.getRect(find.byKey(const ValueKey('pad')));
              final tools = tester.getRect(find.byKey(const ValueKey('tools')));
              expect(
                pad.bottom,
                lessThanOrEqualTo(tools.top),
                reason: 'the pad runs into the tools',
              );
              expect(tester.takeException(), isNull);
            });
          });
        }
      }
    }
  });

  test('the frame geometry: width-bound, height-bound, capped, and shifted '
      'under a tall inset', () {
    expect(frameGeometry(const Size(390, 844), 0).scale, 1);
    expect(frameGeometry(const Size(360, 844), 0).scale, 360 / 390);
    expect(frameGeometry(const Size(390, 640), 0).scale, 640 / 844);
    expect(frameGeometry(const Size(600, 1200), 0).scale, 430 / 390);
    final tall = frameGeometry(const Size(390, 844), 60);
    expect(tall.top, greaterThan(0));
    expect(tall.top + 844 * tall.scale, closeTo(844, 1e-9));
    expect(tall.top, closeTo(60 - 44 * tall.scale, 1e-9));
  });
}
