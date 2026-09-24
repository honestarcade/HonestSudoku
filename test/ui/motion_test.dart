import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:honest_sudoku/ui/app_scope.dart';
import 'package:honest_sudoku/ui/board/board_grid.dart';
import 'package:honest_sudoku/ui/board/game_over_overlay.dart';
import 'package:honest_sudoku/ui/board/pause_overlay.dart';
import 'package:honest_sudoku/ui/routes.dart';
import 'package:honest_sudoku/ui/screens/settings_screen.dart';

import 'helpers.dart';

/// The phone's "Remove animations" setting, for this test.
void removeAnimations(WidgetTester tester) {
  tester.platformDispatcher.accessibilityFeaturesTestValue =
      const FakeAccessibilityFeatures(disableAnimations: true);
  addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
}

/// The route on top of the app's navigator.
Route<dynamic> topRoute(WidgetTester tester) {
  late Route<dynamic> top;
  tester.state<NavigatorState>(find.byType(Navigator).first).popUntil((route) {
    top = route;
    return true;
  });
  return top;
}

/// The opacity the route fade gives [screen].
double routeOpacity(WidgetTester tester, Finder screen) => tester
    .widget<FadeTransition>(
      find.ancestor(of: screen, matching: find.byType(FadeTransition)).first,
    )
    .opacity
    .value;

/// The game-over card's opacity.
double cardOpacity(WidgetTester tester) => tester
    .widget<Opacity>(
      find
          .descendant(
            of: find.byType(GameOverOverlay),
            matching: find.byType(Opacity),
          )
          .first,
    )
    .opacity;

/// Plays the board on screen to a win, then pumps one frame.
Future<void> win(WidgetTester tester) async {
  final c = AppScope.of(tester.element(find.byType(BoardGrid))).controller;
  final s = c.state!;
  for (var i = 0; i < s.values.length; i++) {
    if (!s.isGiven(i) && c.state!.values[i] == 0) {
      c.select(i);
      c.place(s.solution[i]);
    }
  }
  expect(c.state!.won, isTrue);
  await tester.pump();
}

void main() {
  group('every route is the one fade', () {
    for (final name in [...Routes.all, '/nowhere']) {
      testWidgets(name, (tester) async {
        await pumpApp(tester);
        if (name == Routes.board) {
          // With a game: the real board route.
          await startFromMenu(tester);
          expect(find.byType(BoardGrid), findsOneWidget);
        } else {
          tester
              .state<NavigatorState>(find.byType(Navigator).first)
              .pushNamed(name);
          await tester.pump();
        }
        expect(topRoute(tester), isA<FadeRouteTransition<void>>());
      });
    }

    testWidgets('/board with no game (redirected to setup)', (tester) async {
      await pumpApp(tester);
      tester
          .state<NavigatorState>(find.byType(Navigator).first)
          .pushNamed(Routes.board);
      await tester.pump();
      final top = topRoute(tester);
      expect(top.settings.name, Routes.setup);
      expect(top, isA<FadeRouteTransition<void>>());
    });
  });

  group('with animations', () {
    testWidgets('a pushed screen fades in', (tester) async {
      await pumpApp(tester);
      tester
          .state<NavigatorState>(find.byType(Navigator).first)
          .pushNamed(Routes.settings);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(routeOpacity(tester, find.byType(SettingsScreen)), lessThan(1));
      await tester.pumpAndSettle();
      expect(routeOpacity(tester, find.byType(SettingsScreen)), 1);
    });

    testWidgets('the win card rises in', (tester) async {
      await pumpApp(tester);
      await startFromMenu(tester);
      await win(tester);
      expect(cardOpacity(tester), lessThan(1));
      await tester.pumpAndSettle();
      expect(cardOpacity(tester), 1);
    });
  });

  group('with animations removed', () {
    testWidgets('a pushed screen is fully there after one frame', (
      tester,
    ) async {
      removeAnimations(tester);
      await pumpApp(tester);
      tester
          .state<NavigatorState>(find.byType(Navigator).first)
          .pushNamed(Routes.settings);
      await tester.pump();
      await tester.pump();
      expect(routeOpacity(tester, find.byType(SettingsScreen)), 1);
      expect(tester.hasRunningAnimations, isFalse);
    });

    testWidgets('a pop is instant too', (tester) async {
      removeAnimations(tester);
      await pumpApp(tester);
      final nav = tester.state<NavigatorState>(find.byType(Navigator).first);
      nav.pushNamed(Routes.settings);
      await tester.pump();
      await tester.pump();
      nav.pop();
      await tester.pump();
      await tester.pump();
      expect(find.byType(SettingsScreen), findsNothing);
    });

    testWidgets('the win card is fully there on its first frame', (
      tester,
    ) async {
      removeAnimations(tester);
      await pumpApp(tester);
      await startFromMenu(tester);
      await win(tester);
      expect(cardOpacity(tester), 1);
    });
  });

  for (final reduced in [false, true]) {
    testWidgets('the pause card appears at once, never faded '
        '(${reduced ? 'animations removed' : 'animations on'})', (
      tester,
    ) async {
      if (reduced) removeAnimations(tester);
      await pumpApp(tester);
      await startFromMenu(tester);
      await tester.tap(find.byKey(const ValueKey('pause-button')));
      await tester.pump();
      final paused = find.text('Paused');
      expect(paused, findsOneWidget);
      for (final type in [FadeTransition, Opacity, AnimatedOpacity]) {
        expect(
          find.descendant(
            of: find.byType(PauseOverlay),
            matching: find.ancestor(of: paused, matching: find.byType(type)),
          ),
          findsNothing,
          reason: 'a $type between the pause overlay and its card',
        );
      }
    });
  }
}
