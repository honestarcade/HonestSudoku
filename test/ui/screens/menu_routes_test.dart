import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:honest_sudoku/ui/app.dart';
import 'package:honest_sudoku/ui/app_scope.dart';
import 'package:honest_sudoku/ui/board/board_grid.dart';
import 'package:honest_sudoku/ui/board/board_screen.dart';
import 'package:honest_sudoku/ui/routes.dart';
import 'package:honest_sudoku/ui/screens/about_app_screen.dart';
import 'package:honest_sudoku/ui/screens/about_studio_screen.dart';
import 'package:honest_sudoku/ui/screens/howto_screen.dart';
import 'package:honest_sudoku/ui/screens/loading_screen.dart';
import 'package:honest_sudoku/ui/screens/menu_screen.dart';
import 'package:honest_sudoku/ui/screens/settings_screen.dart';
import 'package:honest_sudoku/ui/screens/setup_screen.dart';
import 'package:honest_sudoku/ui/screens/stats_screen.dart';
import 'package:honest_sudoku/ui/widgets/app_mark.dart';

import '../helpers.dart';
import '../stub_generator.dart';

/// The screen on top, by name; the board says whether it is paused.
String onScreen(WidgetTester tester) {
  bool shows(Type t) => find.byType(t).evaluate().isNotEmpty;
  for (final (type, name) in [
    (MenuScreen, 'menu'),
    (SetupScreen, 'setup'),
    (StatsScreen, 'stats'),
    (SettingsScreen, 'settings'),
    (HowToScreen, 'howto'),
    (AboutAppScreen, 'about-app'),
    (AboutStudioScreen, 'about-studio'),
    (LoadingScreen, 'loading'),
  ]) {
    if (shows(type)) return name;
  }
  if (shows(BoardScreen)) {
    return find.text('Paused').evaluate().isEmpty ? 'board' : 'board, paused';
  }
  return 'nothing';
}

void main() {
  testWidgets('without a game: New puzzle, no meta, to setup', (tester) async {
    await pumpApp(tester);
    expectMark(tester, 52, MarkInterior.board);
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

  for (final won in [true, false]) {
    testWidgets('after a ${won ? 'won' : 'lost'} game: New puzzle, no meta', (
      tester,
    ) async {
      await pumpApp(tester);
      await startFromMenu(tester);
      final c = AppScope.of(tester.element(find.byType(BoardScreen)))
          .controller;
      final s = c.state!;
      var wrong = 0;
      for (var i = 0; i < s.values.length && wrong < 3; i++) {
        if (s.isGiven(i)) continue;
        c.select(i);
        c.place(won ? s.solution[i] : s.solution[i] % s.n + 1);
        if (!won) wrong++;
      }
      await tester.pumpAndSettle();
      expect(won ? c.state!.won : c.state!.lost, isTrue);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(MenuScreen), findsOneWidget);
      expect(
        find.byKey(const ValueKey('menu-new')),
        findsOneWidget,
        reason: 'a finished game offers New puzzle, not Continue',
      );
      expect(find.byKey(const ValueKey('menu-continue')), findsNothing);
      expect(
        find.byKey(const ValueKey('menu-meta')),
        findsNothing,
        reason: 'a finished game shows no meta line',
      );
    });
  }

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

  group('the phone back lands where ‹ does', () {
    Future<void> push(WidgetTester tester, Type over, String route) async {
      Navigator.of(tester.element(find.byType(over))).pushNamed(route);
      await tester.pumpAndSettle();
    }

    Future<void> fromMenu(WidgetTester tester, String route) async {
      await pumpApp(tester);
      await push(tester, MenuScreen, route);
    }

    Future<void> pausedGame(WidgetTester tester) async {
      await pumpApp(tester);
      await startFromMenu(tester);
      await tester.tap(find.byKey(const ValueKey('pause-button')));
      await tester.pump();
    }

    Future<void> fromPauseCard(WidgetTester tester, String button) async {
      await pausedGame(tester);
      await tester.tap(find.byKey(ValueKey('btn-$button')));
      await tester.pumpAndSettle();
    }

    // (screen, where it was opened from, how, its ‹ key prefix, where both
    // backs land; null where only their agreement is asserted)
    for (final (screen, origin, open, prefix, lands)
        in <
          (String, String, Future<void> Function(WidgetTester), String, String?)
        >[
          (
            'setup',
            'the menu',
            (t) => fromMenu(t, Routes.setup),
            'setup',
            'menu',
          ),
          (
            'setup',
            'the board',
            (t) async {
              await pausedGame(t);
              await push(t, BoardScreen, Routes.setup);
            },
            'setup',
            'menu',
          ),
          (
            'stats',
            'the menu',
            (t) => fromMenu(t, Routes.stats),
            'stats',
            'menu',
          ),
          (
            'settings',
            'the menu',
            (t) => fromMenu(t, Routes.settings),
            'settings',
            'menu',
          ),
          (
            'settings',
            'the pause card',
            (t) => fromPauseCard(t, 'settings'),
            'settings',
            'board, paused',
          ),
          (
            'howto',
            'the menu',
            (t) => fromMenu(t, Routes.howto),
            'howto',
            'menu',
          ),
          (
            'howto',
            'the pause card',
            (t) => fromPauseCard(t, 'rules'),
            'howto',
            'board, paused',
          ),
          (
            'about-app',
            'the menu',
            (t) => fromMenu(t, Routes.aboutApp),
            'about',
            'menu',
          ),
          (
            'about-studio',
            'the menu',
            (t) => fromMenu(t, Routes.aboutStudio),
            'studio',
            'menu',
          ),
          (
            'about-studio',
            'About the App',
            (t) async {
              await fromMenu(t, Routes.aboutApp);
              await t.ensureVisible(
                find.byKey(const ValueKey('about-promises')),
              );
              await t.tap(find.byKey(const ValueKey('about-promises')));
              await t.pumpAndSettle();
            },
            'studio',
            null,
          ),
        ]) {
      testWidgets('$screen, opened from $origin', (tester) async {
        final landed = <String, String>{};
        for (final (how, back) in <(String, Future<void> Function())>[
          ('‹', () => tester.tap(find.byKey(ValueKey('$prefix-back')))),
          ('the phone back', () => tester.binding.handlePopRoute()),
        ]) {
          await open(tester);
          expect(onScreen(tester), screen, reason: 'opened $screen');
          await back();
          await tester.pumpAndSettle();
          landed[how] = onScreen(tester);
        }
        expect(
          landed['the phone back'],
          landed['‹'],
          reason: 'the phone back on $screen lands where its ‹ does',
        );
        if (lands != null) {
          expect(landed['‹'], lands, reason: '‹ on $screen lands on $lands');
        }
      });
    }

    testWidgets('board: the phone back pauses a running game, then goes to '
        'the menu', (tester) async {
      await pumpApp(tester);
      await startFromMenu(tester);
      expect(onScreen(tester), 'board');
      expect(await tester.binding.handlePopRoute(), isTrue);
      await tester.pumpAndSettle();
      expect(onScreen(tester), 'board, paused');
      expect(await tester.binding.handlePopRoute(), isTrue);
      await tester.pumpAndSettle();
      expect(onScreen(tester), 'menu');
    });

    testWidgets('loading a board: the phone back cancels it and returns to '
        'setup', (tester) async {
      await pumpApp(tester, gen: StubGenerator()..hang = true);
      await tester.tap(find.byKey(const ValueKey('menu-new-card')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const ValueKey('setup-start')));
      await tester.tap(find.byKey(const ValueKey('setup-start')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(onScreen(tester), 'loading');
      expect(await tester.binding.handlePopRoute(), isTrue);
      await tester.pumpAndSettle();
      expect(onScreen(tester), 'setup');
    });

    testWidgets('the launch splash: the phone back leaves the app', (
      tester,
    ) async {
      setScreen(tester, 390, 844);
      await tester.pumpWidget(
        HonestSudokuApp(
          generator: StubGenerator().call,
          seeds: CountingSeeds(),
          store: () async => null,
          links: RecordingLinkOpener(),
        ),
      );
      await tester.pump();
      expect(onScreen(tester), 'loading');
      expect(
        await tester.binding.handlePopRoute(),
        isFalse,
        reason: 'the phone back on the launch splash leaves the app',
      );
      await tester.pumpAndSettle(const Duration(seconds: 1));
    });
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
    // Laid out in the fonts the app ships, as a phone lays it out.
    setUpAll(loadAppFonts);

    Future<void> pumpLarge(
      WidgetTester tester,
      String route, {
      StubGenerator? gen,
    }) => pumpApp(
      tester,
      initialRoute: route,
      gen: gen,
      width: 360,
      height: 640,
      textScale: 1.3,
    );

    for (final (route, screen) in [
      (Routes.menu, 'menu'),
      (Routes.setup, 'setup'),
      (Routes.stats, 'stats'),
      (Routes.settings, 'settings'),
      (Routes.howto, 'howto'),
      (Routes.aboutApp, 'about-app'),
      (Routes.aboutStudio, 'about-studio'),
    ]) {
      testWidgets(route, (tester) async {
        await pumpLarge(tester, route);
        expect(onScreen(tester), screen, reason: '$route renders $screen');
        expect(
          MediaQuery.textScalerOf(tester.element(find.byType(Navigator)))
              .scale(10),
          closeTo(13, 1e-9),
          reason: 'the scale reaches the app',
        );
        expect(tester.takeException(), isNull, reason: route);
      });
    }

    testWidgets('/board, playing and paused', (tester) async {
      await pumpLarge(tester, Routes.menu);
      await startFromMenu(tester);
      expect(onScreen(tester), 'board', reason: '/board renders a game');
      expect(tester.takeException(), isNull, reason: 'the board, playing');
      await tester.tap(find.byKey(const ValueKey('pause-button')));
      await tester.pump();
      expect(onScreen(tester), 'board, paused');
      expect(tester.takeException(), isNull, reason: 'the board, paused');
    });

    testWidgets('/loading, generating', (tester) async {
      await pumpLarge(tester, Routes.setup, gen: StubGenerator()..hang = true);
      await tester.ensureVisible(find.byKey(const ValueKey('setup-start')));
      await tester.tap(find.byKey(const ValueKey('setup-start')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(onScreen(tester), 'loading');
      expect(tester.takeException(), isNull, reason: '/loading, generating');
    });

    testWidgets('/loading, the launch splash', (tester) async {
      setScreen(tester, 360, 640);
      tester.platformDispatcher.textScaleFactorTestValue = 1.3;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpWidget(
        HonestSudokuApp(
          generator: StubGenerator().call,
          seeds: CountingSeeds(),
          store: () async => null,
          links: RecordingLinkOpener(),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
      expect(onScreen(tester), 'loading');
      expect(tester.takeException(), isNull, reason: 'the launch splash');
      await tester.pumpAndSettle(const Duration(seconds: 1));
    });

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

  // No screen pushing /board or /menu itself is route_push_guard_test.dart.
  test('the M3 placeholder is gone', () {
    expect(File('lib/ui/placeholder_screen.dart').existsSync(), isFalse);
    expect(File('lib/ui/loading_placeholder.dart').existsSync(), isFalse);
    expect(
      File('lib/main.dart').readAsStringSync(),
      isNot(contains('HS_LAUNCH_SIZE')),
    );
  });
}
