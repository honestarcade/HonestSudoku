// Pad keys reach 48 dp even where the design paints them smaller (#56).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:honest_sudoku/engine/engine.dart';
import 'package:honest_sudoku/ui/app_scope.dart';
import 'package:honest_sudoku/ui/board/board_screen.dart';
import 'package:honest_sudoku/ui/board/game_controller.dart';
import 'package:honest_sudoku/ui/routes.dart';

import '../helpers.dart';
import '../stub_generator.dart';

Future<GameController> _board(WidgetTester tester) async {
  setScreen(tester, 360, 640);
  final c = GameController(
    generator: StubGenerator().call,
    seeds: CountingSeeds(),
  );
  final routes = RouteObserver<ModalRoute<void>>();
  await tester.pumpWidget(
    MaterialApp(
      navigatorObservers: [routes],
      home: BoardScreen(controller: c, routeObserver: routes),
    ),
  );
  c.startNew(GridShape.monster, Difficulty.medium);
  await tester.pump();
  await tester.pump();
  // A selected empty cell, so a key tap places (and the model shows which).
  c.select(c.state!.values.indexOf(0));
  await tester.pump();
  return c;
}

Rect _painted(WidgetTester tester, int v) =>
    tester.getRect(find.byKey(ValueKey('pad-$v')));

void main() {
  testWidgets('a 16×16 key paints under 48 but reads and hits as 48', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    final c = await _board(tester);
    final box = _painted(tester, 1);
    expect(box.height, lessThan(48), reason: 'the premise: 40 × 360/390');
    final node = tester.getSemantics(find.byKey(const ValueKey('pad-1')));
    expect(node.rect.width, greaterThanOrEqualTo(48));
    expect(node.rect.height, greaterThanOrEqualTo(48));

    // Just above the top row, outside the key and the pad's own box.
    final cell = c.state!.selected!;
    await tester.tapAt(Offset(box.center.dx, box.top - 3));
    await tester.pump();
    expect(c.state!.values[cell], 1);
    await tester.pumpWidget(const SizedBox());
    c.dispose();
    handle.dispose();
  });

  testWidgets('a tap in the gap between rows goes to one key, '
      'deterministically: the lower row; wide keys leave their side gap '
      'alone', (tester) async {
    final c = await _board(tester);
    final one = _painted(tester, 1);
    final two = _painted(tester, 2);
    final five = _painted(tester, 5);
    Future<int> valueAfterTap(Offset at) async {
      final cell = c.state!.values.indexOf(0);
      c.select(cell);
      await tester.pump();
      await tester.tapAt(at);
      await tester.pump();
      return c.state!.values[cell];
    }

    expect(
      await valueAfterTap(Offset((one.right + two.left) / 2, one.center.dy)),
      0,
      reason: 'a key wider than 48 grows no side margin: the gap is dead',
    );
    expect(
      await valueAfterTap(Offset(one.center.dx, (one.bottom + five.top) / 2)),
      5,
      reason: 'vertically the row below wins',
    );
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });

  testWidgets('screens: a stats tab\'s grown margin selects it, through the '
      'app\'s root group', (tester) async {
    await pumpApp(tester, initialRoute: Routes.stats);
    final c = AppScope.of(tester.element(find.byType(Navigator).first))
        .controller;
    final hard = tester.getRect(find.byKey(const ValueKey('stats-tab-hard')));
    expect(hard.height, lessThan(48), reason: 'the premise');
    await tester.tapAt(Offset(hard.center.dx, hard.top - 4));
    await tester.pump();
    expect(c.statsTab, Difficulty.hard);
  });

  testWidgets('a margin never reaches through a scrim in front of it', (
    tester,
  ) async {
    await pumpApp(tester, initialRoute: Routes.stats);
    final c = AppScope.of(tester.element(find.byType(Navigator).first))
        .controller;
    final hard = tester.getRect(find.byKey(const ValueKey('stats-tab-hard')));
    await tester.ensureVisible(find.text('Reset statistics'));
    await tester.tap(find.text('Reset statistics'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('stats-confirm-card')), findsOneWidget);
    await tester.tapAt(Offset(hard.center.dx, hard.top - 4));
    await tester.pump();
    expect(c.statsTab, Difficulty.medium, reason: 'the scrim took the tap');
  });
}
