import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:honest_sudoku/engine/engine.dart';
import 'package:honest_sudoku/game/game.dart';
import 'package:honest_sudoku/ui/board/board_grid.dart';
import 'package:honest_sudoku/ui/board/board_overlays.dart';
import 'package:honest_sudoku/ui/theme/board_theme.dart';

import '../../game/fixtures.dart';
import '../harness.dart';

final class _Streak implements StatsSource {
  const _Streak(this.n);
  final int n;
  @override
  int currentStreak({
    required GridShape shape,
    required Difficulty difficulty,
  }) => n;
}

void main() {
  late Map<String, int> calls;

  Future<void> pumpOverlays(
    WidgetTester tester,
    GameState state, {
    StatsSource stats = const NoStats(),
  }) {
    calls = {};
    void hit(String n) => calls[n] = (calls[n] ?? 0) + 1;
    return pumpFramed(
      tester,
      SizedBox(
        width: 390,
        height: 844,
        child: BoardOverlays(
          state: state,
          board: (_) => BoardGrid(
            state: state,
            theme: BoardTheme.navy,
            scale: 1,
            onTapCell: (_) {},
          ),
          stats: stats,
          scale: 1,
          onResume: () => hit('resume'),
          onRestart: () => hit('restart'),
          onNewDeal: () => hit('new-deal'),
          onRules: () => hit('rules'),
          onSettings: () => hit('settings'),
          onMainMenu: () => hit('main-menu'),
          onChangeSetup: () => hit('change-setup'),
        ),
      ),
    );
  }

  GameState won(GameSettings s) {
    var g = GameState.start(classic, s);
    for (var i = 0; i < 81; i++) {
      if (!classic.givens[i]) g = g.select(i).place(classic.solution[i]);
    }
    return g;
  }

  GameState lost() {
    var g = GameState.start(classic);
    var k = 0;
    for (var i = 0; i < 81 && k < 3; i++) {
      if (!classic.givens[i]) {
        g = g.select(i).place(wrongValue(classic, i));
        k++;
      }
    }
    return g;
  }

  testWidgets('playing: the board, no card', (tester) async {
    await pumpOverlays(tester, GameState.start(classic));
    expect(find.byType(BoardGrid), findsOneWidget);
    expect(find.byKey(const ValueKey('overlay-pause')), findsNothing);
  });

  testWidgets('paused: the card, and no board in the tree', (tester) async {
    await pumpOverlays(
      tester,
      GameState.start(classic).copyWith(moves: 3, elapsedSeconds: 65).pause(),
    );
    expect(find.byKey(const ValueKey('overlay-pause')), findsOneWidget);
    expect(find.byType(BoardGrid), findsNothing);
    expect(find.text('Paused'), findsOneWidget);
    expect(find.text('9×9 · MEDIUM · 1:05'), findsOneWidget);
    expect(find.text('BOARD HIDDEN WHILE PAUSED'), findsOneWidget);
    expect(
      find.text('41 of 81 cells filled · 3 entries · 0 mistakes'),
      findsOneWidget,
    );
    for (final label in [
      'Resume',
      'Restart this puzzle',
      'New puzzle, same settings',
      'Rules',
      'Settings',
      'Main menu',
    ]) {
      expect(find.text(label), findsOneWidget);
    }
  });

  testWidgets('each pause-card button calls back once', (tester) async {
    await pumpOverlays(tester, GameState.start(classic).pause());
    for (final name in [
      'resume',
      'restart',
      'new-deal',
      'rules',
      'settings',
      'main-menu',
    ]) {
      await tester.tap(find.byKey(ValueKey('btn-$name')));
    }
    expect(calls, {
      'resume': 1,
      'restart': 1,
      'new-deal': 1,
      'rules': 1,
      'settings': 1,
      'main-menu': 1,
    });
  });

  testWidgets('won: PUZZLE SOLVED, four tiles, the streak as recorded', (
    tester,
  ) async {
    await pumpOverlays(
      tester,
      won(const GameSettings()),
      stats: const _Streak(4),
    );
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.byType(BoardGrid), findsNothing);
    expect(find.text('PUZZLE SOLVED'), findsOneWidget);
    expect(find.text('Grid complete'), findsOneWidget);
    expect(
      find.text(
        'Every row, column and box checks out. Recorded under 9×9 '
        'Medium.',
      ),
      findsOneWidget,
    );
    for (final t in ['time', 'entries', 'mistakes', 'streak']) {
      expect(find.byKey(ValueKey('tile-$t')), findsOneWidget);
    }
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('tile-streak')),
        matching: find.text('4'),
      ),
      findsOneWidget,
    );
    expect(find.text('Next puzzle'), findsOneWidget);
    final opacity = tester.widget<Opacity>(
      find
          .descendant(
            of: find.byKey(const ValueKey('overlay-over')),
            matching: find.byType(Opacity),
          )
          .first,
    );
    expect(opacity.opacity, 1.0, reason: 'fully risen after 350 ms');
  });

  testWidgets('won in Zen: mistakes read —', (tester) async {
    await pumpOverlays(
      tester,
      won(const GameSettings(strikeMode: StrikeMode.zen)),
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('tile-mistakes')),
        matching: find.text('—'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('lost: OUT OF STRIKES with the limit in the body', (
    tester,
  ) async {
    await pumpOverlays(tester, lost());
    expect(find.text('OUT OF STRIKES'), findsOneWidget);
    expect(find.text('That was the last strike'), findsOneWidget);
    expect(
      find.text(
        'You set a limit of 3. The puzzle is still here if you undo — '
        'or take a fresh one.',
      ),
      findsOneWidget,
    );
    expect(find.text('New puzzle'), findsOneWidget);
    expect(find.text('Medium'), findsOneWidget, reason: 'DIFFICULTY tile');
    expect(find.text('44/81'), findsOneWidget, reason: 'FILLED tile');
  });

  testWidgets('paused and won shows the game-over card, not the pause card', (
    tester,
  ) async {
    await pumpOverlays(tester, won(const GameSettings()).pause());
    expect(find.byKey(const ValueKey('overlay-over')), findsOneWidget);
    expect(find.byKey(const ValueKey('overlay-pause')), findsNothing);
  });

  testWidgets('each game-over button calls back once', (tester) async {
    await pumpOverlays(tester, lost());
    for (final name in ['new-deal', 'change-setup', 'main-menu']) {
      await tester.tap(find.byKey(ValueKey('btn-$name')));
    }
    expect(calls, {'new-deal': 1, 'change-setup': 1, 'main-menu': 1});
  });
}
