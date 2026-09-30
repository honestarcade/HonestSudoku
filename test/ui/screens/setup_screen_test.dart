import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:honest_sudoku/engine/engine.dart';
import 'package:honest_sudoku/game/game.dart';
import 'package:honest_sudoku/ui/app_scope.dart';
import 'package:honest_sudoku/ui/board/board_grid.dart';
import 'package:honest_sudoku/ui/routes.dart';
import 'package:honest_sudoku/ui/screens/setup_screen.dart';

import '../helpers.dart';

Future<void> tapVisible(WidgetTester tester, String key) async {
  await tester.ensureVisible(find.byKey(ValueKey(key)));
  await tester.tap(find.byKey(ValueKey(key)));
  await tester.pumpAndSettle();
}

String meta(WidgetTester tester) =>
    tester.widget<Text>(find.byKey(const ValueKey('setup-meta'))).data!;

void main() {
  test('the meta line for each strike mode', () {
    expect(setupMeta(const LastSetup()), '9×9 · MEDIUM · 3 STRIKES');
    expect(
      setupMeta(const LastSetup(strikeMode: StrikeMode.five)),
      '9×9 · MEDIUM · 5 STRIKES',
    );
    expect(
      setupMeta(const LastSetup(strikeMode: StrikeMode.zen)),
      '9×9 · MEDIUM · ZEN',
    );
    expect(
      setupMeta(
        const LastSetup(
          shapeLabel: '16×16',
          difficultyKey: 'evil',
          strikeMode: StrikeMode.unlimited,
        ),
      ),
      '16×16 · EVIL · NO LIMIT',
    );
  });

  testWidgets('the design sections, and 9×9 givens from the engine table', (
    tester,
  ) async {
    await pumpApp(tester, initialRoute: Routes.setup);
    expect(meta(tester), '9×9 · MEDIUM · 3 STRIKES');
    expect(
      find.text('16×16 uses 1–9 then A–G. Boxes are 4×4.'),
      findsOneWidget,
    );
    for (final s in GridShape.all) {
      expect(find.byKey(ValueKey('setup-size-${s.label}')), findsOneWidget);
      expect(find.text(s.sub), findsOneWidget);
    }
    for (final (d, n) in [
      (Difficulty.easy, 45),
      (Difficulty.medium, 37),
      (Difficulty.hard, 31),
      (Difficulty.expert, 25),
      (Difficulty.evil, 20),
    ]) {
      expect(
        tester
            .widget<Text>(find.byKey(ValueKey('setup-diff-${d.key}-meta')))
            .data,
        '$n GIVENS',
      );
      expect(find.text(d.description), findsOneWidget);
    }
    expect(
      find.byKey(const ValueKey('setup-keep')),
      findsNothing,
      reason: 'no game to keep playing',
    );
  });

  testWidgets('4×4 greys what it cannot offer; taps on them change nothing; '
      'picking 4×4 from Evil moves to the hardest it offers', (tester) async {
    await pumpApp(tester, initialRoute: Routes.setup);
    await tapVisible(tester, 'setup-diff-evil');
    expect(meta(tester), '9×9 · EVIL · 3 STRIKES');
    await tapVisible(tester, 'setup-size-4×4');
    expect(meta(tester), '4×4 · EASY · 3 STRIKES');
    for (final d in [
      Difficulty.medium,
      Difficulty.hard,
      Difficulty.expert,
      Difficulty.evil,
    ]) {
      expect(
        tester
            .widget<Text>(find.byKey(ValueKey('setup-diff-${d.key}-meta')))
            .data,
        'NOT ON 4×4',
      );
      await tapVisible(tester, 'setup-diff-${d.key}');
      expect(meta(tester), '4×4 · EASY · 3 STRIKES', reason: d.label);
    }
  });

  testWidgets('choices are remembered; Start generates the chosen board with '
      'the chosen modes; Keep playing returns to it paused', (tester) async {
    final app = await pumpApp(tester, initialRoute: Routes.setup);
    await tapVisible(tester, 'setup-size-6×6');
    await tapVisible(tester, 'setup-diff-hard');
    await tapVisible(tester, 'setup-strike-zen');
    await tapVisible(tester, 'setup-announce-atEnd');
    expect(meta(tester), '6×6 · HARD · ZEN');
    await tapVisible(tester, 'setup-start');
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    final r = app.gen.requests.single;
    expect([r.shape, r.difficulty], [GridShape.short, Difficulty.hard]);
    expect(find.byType(BoardGrid), findsOneWidget);
    expect(find.text('ZEN'), findsOneWidget, reason: 'the board runs in Zen');
    final c = AppScope.of(tester.element(find.byType(BoardGrid))).controller;
    expect(
      [
        c.state!.shape,
        c.state!.settings.strikeMode,
        c.state!.settings.announce,
      ],
      [GridShape.short, StrikeMode.zen, AnnounceMode.atEnd],
      reason: 'the new game runs with the modes chosen on setup',
    );
    // Back on setup, the choices are still there, and Keep playing shows.
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('menu-new-card')));
    await tester.pumpAndSettle();
    expect(meta(tester), '6×6 · HARD · ZEN');
    await tapVisible(tester, 'setup-keep');
    expect(find.byType(SetupScreen), findsNothing);
    expect(
      find.text('Paused'),
      findsOneWidget,
      reason: 'Keep playing returns to the board, paused',
    );
    expect(c.state!.paused, isTrue);
  });

  testWidgets('choices made on setup during a game leave its modes alone', (
    tester,
  ) async {
    await pumpApp(tester);
    await startFromMenu(tester);
    await tester.tap(find.byKey(const ValueKey('pause-button')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('btn-main-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('menu-new-card')));
    await tester.pumpAndSettle();
    final c = AppScope.of(tester.element(find.byType(SetupScreen))).controller;
    final running = c.state!.settings;
    expect(
      [running.strikeMode, running.announce],
      [StrikeMode.three, AnnounceMode.now],
    );
    await tapVisible(tester, 'setup-strike-zen');
    await tapVisible(tester, 'setup-announce-atEnd');
    expect(meta(tester), '9×9 · MEDIUM · ZEN');
    expect(
      [c.settings.lastSetup.strikeMode, c.settings.lastSetup.announce],
      [StrikeMode.zen, AnnounceMode.atEnd],
    );
    expect(
      c.state!.settings,
      running,
      reason: "a choice on setup leaves the running game's modes alone",
    );
    expect(
      [c.settings.game.strikeMode, c.settings.game.announce],
      [StrikeMode.three, AnnounceMode.now],
      reason: "a choice on setup leaves the running game's modes alone",
    );
  });
}
