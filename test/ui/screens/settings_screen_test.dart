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

  testWidgets('Paper restyles the previews selection and is stored', (
    tester,
  ) async {
    await pumpApp(tester, initialRoute: Routes.settings);
    final c = controllerOf(tester, SettingsScreen);
    expect(c.themeKey, 'navy');
    await tapVisible(tester, 'settings-theme-paper');
    expect(c.themeKey, 'paper');
    expect(c.theme, BoardTheme.paper);
    final preview = tester.widget<Container>(
      find.byKey(const ValueKey('settings-preview-paper')),
    );
    expect(
      (preview.decoration! as BoxDecoration).color,
      BoardTheme.paper.gridBg,
    );
  });

  testWidgets('a strike change reaches the running game; with none running it '
      'also becomes the next board\'s', (tester) async {
    await pumpApp(tester, initialRoute: Routes.settings);
    final c = controllerOf(tester, SettingsScreen);
    await tapVisible(tester, 'settings-strike-five');
    expect(c.settings.game.strikeMode, StrikeMode.five);
    expect(
      c.settings.lastSetup.strikeMode,
      StrikeMode.five,
      reason: 'no game running',
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
