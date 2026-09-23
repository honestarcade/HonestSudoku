import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:honest_sudoku/game/game.dart';
import 'package:honest_sudoku/ui/board/board_styles.dart';
import 'package:honest_sudoku/ui/board/top_bar.dart';
import 'package:honest_sudoku/ui/theme/tokens.dart';

import '../../game/fixtures.dart';
import '../harness.dart';

Future<void> pumpBar(
  WidgetTester tester,
  GameState s, {
  VoidCallback? onPause,
}) => pumpFramed(
  tester,
  TopBar(
    title: s.boardTitle,
    elapsedSeconds: s.elapsedSeconds,
    mistakes: s.mistakes,
    strikeMode: s.settings.strikeMode,
    showTimer: s.settings.showTimer,
    isOver: s.won || s.lost,
    scale: 1,
    onPause: onPause ?? () {},
  ),
);

ChipStyle chipStyle(WidgetTester tester, String key) =>
    tester.widget<ReadoutChip>(find.byKey(ValueKey(key))).style;

GameState withMistakes(GameState s, int k) {
  final empties = [
    for (var i = 0; i < 81; i++)
      if (!classic.givens[i]) i,
  ];
  for (var j = 0; j < k; j++) {
    s = s.select(empties[j]).place(wrongValue(classic, empties[j]));
  }
  return s;
}

void main() {
  testWidgets('the pause button reads the size and difficulty and pauses', (
    tester,
  ) async {
    var paused = 0;
    await pumpBar(tester, GameState.start(classic), onPause: () => paused++);
    expect(find.text('❚❚ 9×9 · Medium'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('pause-button')));
    expect(paused, 1);
  });

  testWidgets('the pause button is inert once the game is over', (
    tester,
  ) async {
    var paused = 0;
    await pumpBar(
      tester,
      GameState.start(classic).copyWith(won: true),
      onPause: () => paused++,
    );
    await tester.tap(find.byKey(const ValueKey('pause-button')));
    expect(paused, 0);
  });

  testWidgets('timer m:ss when shown, absent when not', (tester) async {
    await pumpBar(
      tester,
      GameState.start(classic).copyWith(elapsedSeconds: 75),
    );
    expect(find.text('1:15'), findsOneWidget);
    await pumpBar(
      tester,
      GameState.start(classic, const GameSettings(showTimer: false)),
    );
    expect(find.byKey(const ValueKey('chip-timer')), findsNothing);
  });

  testWidgets('Zen shows the ZEN chip and no strike chip', (tester) async {
    await pumpBar(
      tester,
      GameState.start(classic, const GameSettings(strikeMode: StrikeMode.zen)),
    );
    expect(find.text('ZEN'), findsOneWidget);
    expect(find.byKey(const ValueKey('chip-strike')), findsNothing);
  });

  testWidgets('strike chip: grey at 0, red with the limit, no suffix when '
      'unlimited', (tester) async {
    await pumpBar(tester, GameState.start(classic));
    expect(find.text('✕ 0/3'), findsOneWidget);
    expect(chipStyle(tester, 'chip-strike').fg, HsColors.chipFg);
    await pumpBar(tester, withMistakes(GameState.start(classic), 2));
    expect(find.text('✕ 2/3'), findsOneWidget);
    expect(chipStyle(tester, 'chip-strike').fg, HsColors.wrongRed);
    await pumpBar(
      tester,
      withMistakes(
        GameState.start(
          classic,
          const GameSettings(strikeMode: StrikeMode.unlimited),
        ),
        2,
      ),
    );
    expect(find.text('✕ 2'), findsOneWidget);
  });

  testWidgets('announced at the end, the chip still counts at once', (
    tester,
  ) async {
    await pumpBar(
      tester,
      withMistakes(
        GameState.start(
          classic,
          const GameSettings(announce: AnnounceMode.atEnd),
        ),
        1,
      ),
    );
    expect(find.text('✕ 1/3'), findsOneWidget);
  });

  testWidgets('the clock advances with ticks and freezes while paused', (
    tester,
  ) async {
    final notifier = ValueNotifier(GameState.start(classic));
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: ValueListenableBuilder<GameState>(
          valueListenable: notifier,
          builder: (_, s, _) => TopBar(
            title: s.boardTitle,
            elapsedSeconds: s.elapsedSeconds,
            mistakes: s.mistakes,
            strikeMode: s.settings.strikeMode,
            showTimer: true,
            isOver: false,
            scale: 1,
            onPause: () {},
          ),
        ),
      ),
    );
    notifier.value = notifier.value.tick().tick();
    await tester.pump();
    expect(find.text('0:02'), findsOneWidget);
    notifier.value = notifier.value.pause().tick().tick();
    await tester.pump();
    expect(find.text('0:02'), findsOneWidget);
  });
}
