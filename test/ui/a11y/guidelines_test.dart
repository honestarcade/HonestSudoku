// Flutter's accessibility guidelines over every route (#56): labelled tap
// targets, 48-dp tap targets (grid cells excepted, see the project
// guideline) and text contrast, in both board themes, on the smallest
// supported phone and the design's.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:honest_sudoku/engine/engine.dart';
import 'package:honest_sudoku/store/app_store.dart';
import 'package:honest_sudoku/ui/app.dart';
import 'package:honest_sudoku/ui/app_scope.dart';
import 'package:honest_sudoku/ui/board/board_grid.dart';
import 'package:honest_sudoku/ui/board/game_controller.dart';
import 'package:honest_sudoku/ui/routes.dart';

import '../helpers.dart';
import '../stub_generator.dart';
import 'honest_tap_target_guideline.dart';

const _sizes = [(360.0, 640.0), (390.0, 844.0)];
const _themes = ['navy', 'paper'];

GameController _controller(WidgetTester tester) =>
    AppScope.of(tester.element(find.byType(Navigator).first)).controller;

Future<void> _meetsAll(WidgetTester tester, {bool android = false}) async {
  await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
  await expectLater(tester, meetsGuideline(textContrastGuideline));
  await expectLater(tester, meetsGuideline(honestTapTargetGuideline));
  if (android) {
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
  }
}

/// Every scroll position of the route's first scrollable, top to bottom.
Future<void> _meetsAllScrolled(WidgetTester tester) async {
  await _meetsAll(tester, android: true);
  final scrollable = find.byType(Scrollable);
  if (scrollable.evaluate().isEmpty) return;
  final state = tester.state<ScrollableState>(scrollable.first);
  while (state.position.pixels < state.position.maxScrollExtent) {
    state.position.jumpTo(
      (state.position.pixels + state.position.viewportDimension * .8).clamp(
        0,
        state.position.maxScrollExtent,
      ),
    );
    await tester.pumpAndSettle();
    await _meetsAll(tester, android: true);
  }
}

void main() {
  for (final (w, h) in _sizes) {
    final size = '${w.toInt()}×${h.toInt()}';
    group(size, () {
      for (final route in [
        Routes.menu,
        Routes.setup,
        Routes.stats,
        Routes.howto,
        Routes.aboutApp,
        Routes.aboutStudio,
      ]) {
        testWidgets(route, (tester) async {
          final handle = tester.ensureSemantics();
          await pumpApp(tester, initialRoute: route, width: w, height: h);
          await _meetsAllScrolled(tester);
          handle.dispose();
        });
      }

      for (final theme in _themes) {
        testWidgets('/settings, $theme', (tester) async {
          final handle = tester.ensureSemantics();
          await pumpApp(tester, width: w, height: h);
          final c = _controller(tester);
          c.updateSettings(c.settings.copyWith(themeKey: theme));
          tester
              .state<NavigatorState>(find.byType(Navigator).first)
              .pushNamed(Routes.settings);
          await tester.pumpAndSettle();
          await _meetsAllScrolled(tester);
          handle.dispose();
        });

        for (final shape in [GridShape.classic, GridShape.monster]) {
          for (final (name, stage) in <(String, void Function(GameController))>[
            (
              'hint notice and note mode',
              (c) {
                c.hint();
                c.toggleNotes();
              },
            ),
            ('pause card', (c) => c.pause()),
            (
              'win card',
              (c) {
                final s = c.state!;
                for (var i = 0; i < s.values.length; i++) {
                  if (!s.isGiven(i)) {
                    c.select(i);
                    c.place(s.solution[i]);
                  }
                }
              },
            ),
            (
              'out-of-strikes card',
              (c) {
                for (var k = 0; k < 3; k++) {
                  final i = c.state!.values.indexOf(0);
                  c.select(i);
                  c.place(c.state!.solution[i] % c.state!.n + 1);
                }
              },
            ),
          ]) {
            testWidgets('/board ${shape.label}, $theme, $name', (tester) async {
              final handle = tester.ensureSemantics();
              await pumpApp(tester, width: w, height: h);
              final c = _controller(tester);
              c.updateSettings(
                c.settings.copyWith(
                  themeKey: theme,
                  lastSetup: c.settings.lastSetup.copyWith(
                    shapeLabel: shape.label,
                  ),
                ),
              );
              await startFromMenu(tester);
              expect(find.byType(BoardGrid), findsOneWidget);
              stage(c);
              await tester.pumpAndSettle();
              await _meetsAll(tester);
              handle.dispose();
            });
          }
        }
      }

      testWidgets('/loading, generating at 45 %', (tester) async {
        final handle = tester.ensureSemantics();
        setScreen(tester, w, h);
        final gen = ManualGenerator();
        await tester.pumpWidget(
          HonestSudokuApp(
            generator: gen.call,
            seeds: CountingSeeds(),
            store: () async => null,
            links: RecordingLinkOpener(),
            initialRoute: Routes.setup,
          ),
        );
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.byKey(const ValueKey('setup-start')));
        await tester.tap(find.byKey(const ValueKey('setup-start')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));
        gen.emit(GenerationProgress(.45));
        await tester.pump(const Duration(milliseconds: 300));
        await _meetsAll(tester, android: true);
        gen.finish();
        await tester.pumpAndSettle();
        handle.dispose();
      });

      testWidgets('/loading, the launch splash', (tester) async {
        final handle = tester.ensureSemantics();
        setScreen(tester, w, h);
        final never = Completer<AppStore?>();
        await tester.pumpWidget(
          HonestSudokuApp(
            generator: StubGenerator().call,
            seeds: CountingSeeds(),
            store: () => never.future,
            links: RecordingLinkOpener(),
          ),
        );
        await tester.pump(const Duration(seconds: 1));
        await _meetsAll(tester, android: true);
        await tester.pumpWidget(const SizedBox());
        handle.dispose();
      });
    });
  }
}
