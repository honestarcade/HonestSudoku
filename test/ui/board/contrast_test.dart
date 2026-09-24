// Flutter's text-contrast guideline over the board screen, in both themes,
// in the states that put the most colours on screen (#52).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:honest_sudoku/engine/engine.dart';
import 'package:honest_sudoku/game/game.dart';
import 'package:honest_sudoku/ui/board/board_screen.dart';
import 'package:honest_sudoku/ui/board/game_controller.dart';

import '../stub_generator.dart';

Future<void> onBoard(
  WidgetTester tester,
  String theme,
  void Function(GameController c) stage, {
  GameSettings game = const GameSettings(),
}) async {
  final handle = tester.ensureSemantics();
  tester.view.physicalSize = const Size(390 * 3, 844 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final c = GameController(
    generator: StubGenerator().call,
    seeds: CountingSeeds(),
    settings: AppSettings(themeKey: theme, game: game),
  );
  final routes = RouteObserver<ModalRoute<void>>();
  await tester.pumpWidget(
    MediaQuery(
      data: const MediaQueryData(disableAnimations: true),
      child: MaterialApp(
        navigatorObservers: [routes],
        home: BoardScreen(controller: c, routeObserver: routes),
      ),
    ),
  );
  c.startNew(GridShape.classic, Difficulty.medium);
  await tester.pump();
  await tester.pump();
  stage(c);
  await tester.pump();
  await expectLater(tester, meetsGuideline(textContrastGuideline));
  await tester.pumpWidget(const SizedBox());
  c.dispose();
  handle.dispose();
}

int wrongFor(GameController c, int i) => c.state!.solution[i] % 9 + 1;

void main() {
  for (final theme in ['navy', 'paper']) {
    group(theme, () {
      testWidgets('a wrong entry, a hint notice and note mode', (tester) async {
        await onBoard(tester, theme, (c) {
          c.select(1);
          c.place(wrongFor(c, 1));
          c.select(5);
          c.place(c.state!.solution[5]);
          c.toggleNotes();
          c.select(3);
          c.place(2);
          c.place(6);
          c.hint();
        });
      });

      testWidgets('auto-candidates with a hinted cell', (tester) async {
        await onBoard(
          tester,
          theme,
          game: const GameSettings(autoNotes: true),
          (c) => c.hint(),
        );
      });

      testWidgets('the pause card', (tester) async {
        await onBoard(tester, theme, (c) => c.pause());
      });

      testWidgets('the win card', (tester) async {
        await onBoard(tester, theme, (c) {
          final s = c.state!;
          for (var i = 0; i < 81; i++) {
            if (!s.isGiven(i)) {
              c.select(i);
              c.place(s.solution[i]);
            }
          }
        });
      });

      testWidgets('the out-of-strikes card', (tester) async {
        await onBoard(tester, theme, (c) {
          for (final i in [1, 3, 5]) {
            c.select(i);
            c.place(wrongFor(c, i));
          }
        });
      });
    });
  }
}
