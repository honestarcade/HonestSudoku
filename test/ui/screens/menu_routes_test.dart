import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:honest_sudoku/ui/board/board_grid.dart';
import 'package:honest_sudoku/ui/routes.dart';
import 'package:honest_sudoku/ui/screens/menu_screen.dart';
import 'package:honest_sudoku/ui/screens/setup_screen.dart';
import 'package:honest_sudoku/ui/screens/stats_screen.dart';

import '../helpers.dart';

void main() {
  testWidgets('without a game: New puzzle, no meta, to setup', (tester) async {
    await pumpApp(tester);
    expect(find.byKey(const ValueKey('menu-new')), findsOneWidget);
    expect(find.byKey(const ValueKey('menu-meta')), findsNothing);
    expect(
      find.text('BY HONEST ARCADE · NO ADS'),
      findsOneWidget,
      reason: 'the CSS-uppercased byline is rendered upper case',
    );
    await tester.tap(find.byKey(const ValueKey('menu-new')));
    await tester.pumpAndSettle();
    expect(find.byType(SetupScreen), findsOneWidget);
  });

  testWidgets('each menu entry reaches its screen', (tester) async {
    for (final (key, title) in [
      ('menu-stats', 'Statistics'),
      ('menu-howto', 'How to play'),
      ('menu-settings', 'Settings'),
      ('menu-about-app', 'About the App'),
      ('menu-about-studio', 'About Honest Arcade'),
      ('menu-new-card', 'New puzzle'),
    ]) {
      await pumpApp(tester);
      await tester.ensureVisible(find.byKey(ValueKey(key)));
      await tester.tap(find.byKey(ValueKey(key)));
      await tester.pumpAndSettle();
      expect(find.byType(MenuScreen), findsNothing, reason: key);
      expect(find.text(title), findsWidgets, reason: key);
    }
  });

  testWidgets('Main menu from the pause card keeps the game; Continue returns '
      'to the same board, paused', (tester) async {
    await pumpApp(tester);
    await startFromMenu(tester);
    await tester.tap(find.byKey(const ValueKey('cell-1')));
    await tester.tap(find.byKey(const ValueKey('pad-2')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('pause-button')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('btn-main-menu')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('menu-continue')), findsOneWidget);
    expect(find.byKey(const ValueKey('menu-meta')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('menu-continue')));
    await tester.pumpAndSettle();
    expect(find.text('Paused'), findsOneWidget);
    await tester.tap(find.text('Resume'));
    await tester.pump();
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('cell-1')),
        matching: find.text('2'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('setup opened from the board: ‹ lands on the menu', (
    tester,
  ) async {
    await pumpApp(tester);
    await startFromMenu(tester);
    // Finish nothing; open setup from the pause card's neighbour: the
    // game-over card is not needed, the route is the same.
    Navigator.of(tester.element(find.byType(BoardGrid)))
        .pushNamed(Routes.setup);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('setup-back')));
    await tester.pumpAndSettle();
    expect(find.byType(MenuScreen), findsOneWidget);
  });

  testWidgets('the phone back matches ‹ on every route', (tester) async {
    for (final (route, lands) in [
      (Routes.setup, MenuScreen),
      (Routes.stats, MenuScreen),
      (Routes.aboutApp, MenuScreen),
      (Routes.aboutStudio, MenuScreen),
    ]) {
      await pumpApp(tester);
      Navigator.of(tester.element(find.byType(MenuScreen))).pushNamed(route);
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(lands), findsOneWidget, reason: route);
    }
    for (final route in [Routes.settings, Routes.howto]) {
      await pumpApp(tester);
      Navigator.of(tester.element(find.byType(MenuScreen))).pushNamed(route);
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(MenuScreen), findsOneWidget, reason: route);
    }
  });

  testWidgets('back on the menu leaves the app; elsewhere it does not', (
    tester,
  ) async {
    await pumpApp(tester);
    expect(
      await tester.binding.handlePopRoute(),
      isFalse,
      reason: 'nothing left to pop: the system closes the app',
    );
    for (final route in [Routes.stats, Routes.setup, Routes.aboutApp]) {
      await pumpApp(tester);
      Navigator.of(tester.element(find.byType(MenuScreen))).pushNamed(route);
      await tester.pumpAndSettle();
      expect(await tester.binding.handlePopRoute(), isTrue, reason: route);
      await tester.pumpAndSettle();
    }
  });

  testWidgets('/board with no game opens setup instead', (tester) async {
    await pumpApp(tester, initialRoute: Routes.board);
    expect(find.byType(SetupScreen), findsOneWidget);
  });

  group('large text: nothing overflows at 360×640 with 1.3× text', () {
    for (final route in Routes.all.where((r) => r != Routes.loading)) {
      testWidgets(route, (tester) async {
        await pumpApp(
          tester,
          initialRoute: route,
          width: 360,
          height: 640,
          textScale: 1.3,
        );
        expect(
          MediaQuery.textScalerOf(tester.element(find.byType(Navigator)))
              .scale(10),
          closeTo(13, 1e-9),
          reason: 'the scale reaches the app',
        );
        expect(tester.takeException(), isNull, reason: route);
      });
    }
    testWidgets('/stats with the reset card open', (tester) async {
      await pumpApp(
        tester,
        initialRoute: Routes.stats,
        width: 360,
        height: 640,
        textScale: 1.3,
      );
      await tester.ensureVisible(find.byKey(const ValueKey('stats-reset')));
      await tester.tap(find.byKey(const ValueKey('stats-reset')));
      await tester.pump();
      expect(find.byType(StatsScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  test('no screen pushes /board or /menu itself, and the M3 placeholder is '
      'gone', () {
    final offenders = <String>[];
    for (final f in Directory('lib/ui').listSync(recursive: true)) {
      if (f is! File || !f.path.endsWith('.dart')) continue;
      if (f.path.endsWith('routes.dart')) continue;
      final src = f.readAsStringSync();
      final push = RegExp(r'push\w*\(\s*Routes\.(board|menu)\b');
      if (push.hasMatch(src)) offenders.add(f.path);
    }
    expect(offenders, isEmpty);
    expect(File('lib/ui/placeholder_screen.dart').existsSync(), isFalse);
    expect(File('lib/ui/loading_placeholder.dart').existsSync(), isFalse);
    expect(
      File('lib/main.dart').readAsStringSync(),
      isNot(contains('HS_LAUNCH_SIZE')),
    );
  });
}
