import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:honest_sudoku/engine/engine.dart';
import 'package:honest_sudoku/game/game.dart';
import 'package:honest_sudoku/store/app_store.dart';
import 'package:honest_sudoku/ui/app_scope.dart';
import 'package:honest_sudoku/ui/board/game_controller.dart';
import 'package:honest_sudoku/ui/routes.dart';
import 'package:honest_sudoku/ui/screens/stats_screen.dart';

import '../../game/fixtures.dart';
import '../helpers.dart';

String cardValue(WidgetTester tester, String name) => tester
    .widgetList<Text>(
      find.descendant(
        of: find.byKey(ValueKey('stats-card-$name')),
        matching: find.byType(Text),
      ),
    )
    .elementAt(1)
    .data!;

/// Opens statistics over a store holding [book], loaded for real.
Future<GameController> pumpStats(WidgetTester tester, StatsBook book) async {
  final dir = Directory.systemTemp.createTempSync('hs-stats-');
  addTearDown(() => dir.deleteSync(recursive: true));
  late AppStore store;
  await tester.runAsync(() async {
    store = await AppStore.open(dir);
    await store.writeStats(book);
  });
  await pumpApp(tester, initialRoute: Routes.stats, store: () async => store);
  final c = AppScope.of(tester.element(find.byType(StatsScreen))).controller;
  await tester.runAsync(c.load);
  await tester.pump();
  return c;
}

void main() {
  testWidgets('a populated difficulty reads in the design formats', (
    tester,
  ) async {
    final c = await pumpStats(tester, sampleStatsBook);
    await tester.tap(find.byKey(const ValueKey('stats-tab-easy')));
    await tester.pump();
    expect(c.statsTab, Difficulty.easy);
    expect(cardValue(tester, 'solved'), '64');
    expect(cardValue(tester, 'rate'), '97%');
    expect(cardValue(tester, 'best'), '2:14');
    expect(cardValue(tester, 'average'), '4:38');
    expect(cardValue(tester, 'streak'), '12');
    expect(cardValue(tester, 'time'), '5h 06m');
    expect(find.text('66 started'), findsOneWidget);
    expect(find.byKey(const ValueKey('stats-row-9×9')), findsOneWidget);
    expect(find.text('64 / 66 · 97%'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('stats-row-4×4')),
      findsNothing,
      reason: 'nothing started at 4×4',
    );
  });

  testWidgets('an empty difficulty shows dashes and no rows', (tester) async {
    await pumpStats(tester, sampleStatsBook);
    // Medium, the first tab, is empty in the sample.
    for (final name in [
      'solved',
      'rate',
      'best',
      'average',
      'streak',
      'time',
    ]) {
      expect(cardValue(tester, name), '—', reason: name);
    }
    expect(find.text('— started'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (w) =>
            w.key is ValueKey<String> &&
            (w.key! as ValueKey<String>).value.startsWith('stats-row-'),
      ),
      findsNothing,
    );
  });

  testWidgets('Reset then Cancel keeps the numbers; Reset then Reset wipes '
      'them', (tester) async {
    final c = await pumpStats(tester, sampleStatsBook);
    await tester.tap(find.byKey(const ValueKey('stats-tab-easy')));
    await tester.pump();
    await tester.ensureVisible(find.byKey(const ValueKey('stats-reset')));
    await tester.tap(find.byKey(const ValueKey('stats-reset')));
    await tester.pump();
    expect(find.text('Reset statistics?'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('stats-cancel')));
    await tester.pump();
    expect(find.text('Reset statistics?'), findsNothing);
    expect(cardValue(tester, 'solved'), '64');

    await tester.tap(find.byKey(const ValueKey('stats-reset')));
    await tester.pump();
    // The phone's back button dismisses the card, and only the card.
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(find.text('Reset statistics?'), findsNothing);
    expect(find.byType(StatsScreen), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('stats-reset')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('stats-confirm')));
    await tester.pump();
    expect(c.book, StatsBook.empty);
    expect(cardValue(tester, 'solved'), '—');
  });

  test('a reset reaches the store', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final dir = Directory.systemTemp.createTempSync('hs-reset-');
    addTearDown(() => dir.deleteSync(recursive: true));
    final store = await AppStore.open(dir);
    await store.writeStats(sampleStatsBook);
    final c = GameController(store: () async => store, log: (_) {});
    addTearDown(c.dispose);
    await c.load();
    expect(c.book, sampleStatsBook);
    await c.resetStats();
    expect((await store.readStats()).valueOrNull, StatsBook.empty);
  });

  test('size colours are the design breakdown colours', () {
    expect(
      [for (final s in GridShape.all) sizeColor(s).toARGB32()],
      [0xFF00D6B4, 0xFF0076F1, 0xFF8448FC, 0xFFFFC94A],
    );
  });
}
