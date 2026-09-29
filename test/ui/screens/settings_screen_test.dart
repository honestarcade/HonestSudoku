import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:honest_sudoku/build_info.dart';
import 'package:honest_sudoku/game/game.dart';
import 'package:honest_sudoku/store/app_store.dart';
import 'package:honest_sudoku/ui/app_scope.dart';
import 'package:honest_sudoku/ui/board/board_grid.dart';
import 'package:honest_sudoku/ui/board/game_controller.dart';
import 'package:honest_sudoku/ui/routes.dart';
import 'package:honest_sudoku/ui/screens/menu_screen.dart';
import 'package:honest_sudoku/ui/screens/settings_screen.dart';
import 'package:honest_sudoku/ui/theme/board_theme.dart';
import 'package:honest_sudoku/ui/theme/tokens.dart';
import 'package:honest_sudoku/ui/widgets/design_button.dart';

import '../helpers.dart';

GameController controllerOf(WidgetTester tester, Type screen) =>
    AppScope.of(tester.element(find.byType(screen))).controller;

Future<void> tapVisible(WidgetTester tester, String key) async {
  await tester.ensureVisible(find.byKey(ValueKey(key)));
  await tester.tap(find.byKey(ValueKey(key)));
  await tester.pump();
}

void main() {
  testWidgets('every toggle flips', (tester) async {
    await pumpApp(tester, initialRoute: Routes.settings);
    final c = controllerOf(tester, SettingsScreen);
    for (final t in SettingToggle.values) {
      final before = t.read(c.settings.game);
      await tapVisible(tester, 'settings-toggle-${t.key}');
      expect(t.read(c.settings.game), !before, reason: t.key);
    }
    for (final t in SoundToggle.values) {
      await tapVisible(tester, 'settings-toggle-${t.key}');
      expect(t.read(c.settings), isFalse, reason: t.key);
    }
  });

  // The store's file I/O cannot finish inside the widget tester's fake clock,
  // so persistence is proven here, through the same updateSettings calls the
  // screen's toggles make.
  test('every toggle the screen flips is read back from the store', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final dir = Directory.systemTemp.createTempSync('hs-settings-');
    addTearDown(() => dir.deleteSync(recursive: true));
    final store = await AppStore.open(dir);
    final c = GameController(store: () async => store, log: (_) {});
    addTearDown(c.dispose);
    await c.load();
    for (final t in SettingToggle.values) {
      c.updateSettings(
        c.settings.copyWith(
          game: t.write(c.settings.game, !t.read(c.settings.game)),
        ),
      );
    }
    for (final t in SoundToggle.values) {
      c.updateSettings(t.write(c.settings, false));
    }
    c.updateSettings(c.settings.copyWith(themeKey: 'paper'));
    await Future<void>.delayed(const Duration(milliseconds: 100));
    final saved = (await store.readSettings()).valueOrNull;
    expect(saved, c.settings);
    for (final t in SettingToggle.values) {
      expect(t.read(saved!.game), !t.read(const GameSettings()), reason: t.key);
    }
    expect(
      [saved!.sfx, saved.haptics, saved.themeKey],
      [false, false, 'paper'],
    );
  });

  testWidgets('Paper moves the selection to its preview and becomes the '
      'board theme', (tester) async {
    await pumpApp(tester, initialRoute: Routes.settings);
    final c = controllerOf(tester, SettingsScreen);
    Color edge(BoardTheme t) => tester
        .widget<DesignButton>(find.byKey(ValueKey('settings-theme-${t.key}')))
        .spec
        .edge;
    Color? label(BoardTheme t) => tester
        .widget<Text>(
          find.descendant(
            of: find.byKey(ValueKey('settings-theme-${t.key}')),
            matching: find.text(t.label),
          ),
        )
        .style!
        .color;
    Color? previewBg(BoardTheme t) =>
        (tester
                    .widget<Container>(
                      find.byKey(ValueKey('settings-preview-${t.key}')),
                    )
                    .decoration!
                as BoxDecoration)
            .color;

    expect(c.themeKey, 'navy');
    expect(
      [edge(BoardTheme.navy), edge(BoardTheme.paper)],
      [HsColors.teal, HsColors.track],
      reason: 'the selected theme card has the teal edge',
    );
    await tapVisible(tester, 'settings-theme-paper');
    expect(c.themeKey, 'paper');
    expect(c.theme, BoardTheme.paper);
    expect(
      [edge(BoardTheme.navy), edge(BoardTheme.paper)],
      [HsColors.track, HsColors.teal],
      reason: 'picking Paper moves the teal edge to its card',
    );
    expect(
      [label(BoardTheme.navy), label(BoardTheme.paper)],
      [HsColors.desc, HsColors.teal],
      reason: 'picking Paper moves the teal label to its card',
    );
    for (final t in BoardTheme.all) {
      expect(
        previewBg(t),
        t.gridBg,
        reason: 'each preview shows its own theme, whichever is picked',
      );
    }
  });

  testWidgets('with no game running, a strike change becomes the next '
      "board's", (tester) async {
    await pumpApp(tester, initialRoute: Routes.settings);
    final c = controllerOf(tester, SettingsScreen);
    await tapVisible(tester, 'settings-strike-five');
    expect(c.settings.game.strikeMode, StrikeMode.five);
    expect(
      c.settings.lastSetup.strikeMode,
      StrikeMode.five,
      reason: "a strike change with no game running is the next board's",
    );
  });

  testWidgets('during a game, strike and announce changes reach it and '
      "become the next board's", (tester) async {
    await pumpApp(tester);
    await startFromMenu(tester);
    await tester.tap(find.byKey(const ValueKey('pause-button')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('btn-settings')));
    await tester.pumpAndSettle();
    final c = controllerOf(tester, SettingsScreen);
    expect(c.hasUnfinishedGame, isTrue);
    expect(
      [c.state!.settings.strikeMode, c.state!.settings.announce],
      [StrikeMode.three, AnnounceMode.now],
    );
    await tapVisible(tester, 'settings-strike-five');
    await tapVisible(tester, 'settings-announce-atEnd');
    expect(
      [c.state!.settings.strikeMode, c.state!.settings.announce],
      [StrikeMode.five, AnnounceMode.atEnd],
      reason: 'strike and announce changes reach the running game',
    );
    expect(
      [c.settings.game.strikeMode, c.settings.game.announce],
      [StrikeMode.five, AnnounceMode.atEnd],
    );
    expect(
      [c.settings.lastSetup.strikeMode, c.settings.lastSetup.announce],
      [StrikeMode.five, AnnounceMode.atEnd],
      reason:
          "strike and announce changes during a game are the next board's "
          'too',
    );
  });

  testWidgets('the version line, with the define and without', (tester) async {
    await pumpApp(tester, initialRoute: Routes.settings);
    await tester.ensureVisible(find.byKey(const ValueKey('settings-version')));
    expect(find.text('v1.2.3 · BUILD 45'), findsOneWidget);
    await pumpApp(
      tester,
      initialRoute: Routes.settings,
      buildInfo: BuildInfo.parse(''),
    );
    await tester.ensureVisible(find.byKey(const ValueKey('settings-version')));
    expect(find.text('v0.0.0 · BUILD 0'), findsOneWidget);
  });

  testWidgets('back goes to the board when opened from the pause card, and '
      'to the menu otherwise', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.byKey(const ValueKey('menu-settings')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('settings-back')));
    await tester.pumpAndSettle();
    expect(find.byType(MenuScreen), findsOneWidget);

    await startFromMenu(tester);
    await tester.tap(find.byKey(const ValueKey('pause-button')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('btn-settings')));
    await tester.pumpAndSettle();
    expect(find.byType(SettingsScreen), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Paused'), findsOneWidget);
    expect(find.byType(BoardGrid), findsNothing);
  });
}
