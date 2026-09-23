import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:honest_sudoku/engine/engine.dart';
import 'package:honest_sudoku/game/game.dart';
import 'package:honest_sudoku/ui/board/board_grid.dart';
import 'package:honest_sudoku/ui/theme/board_theme.dart';
import 'package:honest_sudoku/ui/theme/tokens.dart';

import '../../game/fixtures.dart';
import '../harness.dart';

Future<void> pumpGrid(
  WidgetTester tester,
  GameState state, {
  BoardTheme theme = BoardTheme.navy,
  ValueChanged<int>? onTap,
}) => pumpFramed(
  tester,
  BoardGrid(state: state, theme: theme, scale: 1, onTapCell: onTap ?? (_) {}),
);

GridLinesPainter painter(WidgetTester tester) => tester
    .widgetList<CustomPaint>(find.byType(CustomPaint))
    .map((c) => c.painter)
    .whereType<GridLinesPainter>()
    .single;

void main() {
  final p = fixturePuzzle(GridShape.classic);
  const navy = BoardTheme.navy;

  for (final shape in GridShape.all) {
    testWidgets('${shape.label}: n² cells and 2(n + 1) lines', (tester) async {
      await pumpGrid(tester, GameState.start(fixturePuzzle(shape)));
      expect(
        find.byWidgetPredicate(
          (w) =>
              w.key is ValueKey<String> &&
              (w.key! as ValueKey<String>).value.startsWith('cell-'),
        ),
        findsNWidgets(shape.cellCount),
      );
      expect(painter(tester).lines, hasLength((shape.n + 1) * 2));
    });
  }

  testWidgets('givens and entries render their symbols; empty cells no text', (
    tester,
  ) async {
    final s = GameState.start(p).select(1).place(p.solution[1]);
    await pumpGrid(tester, s);
    final cell1 = find.descendant(
      of: find.byKey(const ValueKey('cell-1')),
      matching: find.byType(Text),
    );
    expect(tester.widget<Text>(cell1).data, '${p.solution[1]}');
    expect(tester.widget<Text>(cell1).style!.color, navy.userFg);
    expect(tester.widget<Text>(cell1).style!.fontWeight, FontWeight.w500);
    final cell0 = find.descendant(
      of: find.byKey(const ValueKey('cell-0')),
      matching: find.byType(Text),
    );
    expect(tester.widget<Text>(cell0).style!.color, navy.givenFg);
    expect(tester.widget<Text>(cell0).style!.fontWeight, FontWeight.w600);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('cell-3')),
        matching: find.byType(Text),
      ),
      findsNothing,
    );
  });

  testWidgets('16×16 shows A–G', (tester) async {
    await pumpGrid(tester, GameState.start(fixturePuzzle(GridShape.monster)));
    expect(find.text('G'), findsWidgets);
  });

  group('highlights', () {
    // An anchor given whose value appears again, as a given, outside its
    // peers; one of its empty peers; and a cell far from it.
    final base = GameState.start(p);
    final (anchor, same) = [
      for (var a = 0; a < 81; a++)
        if (p.givens[a])
          for (var j = 0; j < 81; j++)
            if (j != a &&
                p.givens[j] &&
                base.values[j] == base.values[a] &&
                !unitsOf(GridShape.classic, a).contains(j))
              (a, j),
    ].first;
    final peers = unitsOf(GridShape.classic, anchor);
    final plainPeer = peers.firstWhere((i) => base.values[i] == 0);
    final far = [
      for (var i = 0; i < 81; i++)
        if (i != anchor &&
            !peers.contains(i) &&
            base.values[i] != base.values[anchor])
          i,
    ].first;

    testWidgets('selected cell takes selBg; peers peerBg with hlUnit on', (
      tester,
    ) async {
      await pumpGrid(tester, base.select(anchor));
      expect(boxColor(tester, 'cell-$anchor'), navy.selBg);
      expect(boxColor(tester, 'cell-$plainPeer'), navy.peerBg);
      expect(boxColor(tester, 'cell-$far'), navy.cellBg);
    });

    testWidgets('hlUnit off: peers keep cellBg', (tester) async {
      await pumpGrid(
        tester,
        base.withSettings(const GameSettings(hlUnit: false)).select(anchor),
      );
      expect(boxColor(tester, 'cell-$plainPeer'), navy.cellBg);
    });

    testWidgets('hlSame on: other cells holding the value take sameBg; off: '
        'they keep cellBg', (tester) async {
      await pumpGrid(tester, base.select(anchor));
      expect(boxColor(tester, 'cell-$same'), navy.sameBg);
      await pumpGrid(
        tester,
        base.withSettings(const GameSettings(hlSame: false)).select(anchor),
      );
      expect(boxColor(tester, 'cell-$same'), navy.cellBg);
    });

    testWidgets('conflicts on: a peer holding the selected value takes '
        'wrongBg; off: it does not', (tester) async {
      // Put the selected cell's value into an empty peer.
      final clash = base
          .withSettings(const GameSettings(strikeMode: StrikeMode.zen))
          .select(plainPeer)
          .place(base.values[anchor])
          .select(anchor);
      await pumpGrid(tester, clash);
      expect(boxColor(tester, 'cell-$plainPeer'), navy.wrongBg);
      await pumpGrid(
        tester,
        clash.withSettings(
          const GameSettings(strikeMode: StrikeMode.zen, conflicts: false),
        ),
      );
      expect(boxColor(tester, 'cell-$plainPeer'), isNot(navy.wrongBg));
    });

    testWidgets('a wrong entry is tinted only when showWrong', (tester) async {
      final cell = 1;
      final wrongV = wrongValue(p, cell);
      final shown = base.select(cell).place(wrongV).select(cell);
      await pumpGrid(tester, shown.select(far));
      expect(boxColor(tester, 'cell-$cell'), navy.wrongBg);
      Text digit() => tester.widget<Text>(
        find.descendant(
          of: find.byKey(ValueKey('cell-$cell')),
          matching: find.byType(Text),
        ),
      );
      expect(digit().style!.color, navy.wrongFg);

      final hidden = GameState.start(
        p,
        const GameSettings(announce: AnnounceMode.atEnd),
      ).select(cell).place(wrongV).select(far);
      await pumpGrid(tester, hidden);
      expect(boxColor(tester, 'cell-$cell'), isNot(navy.wrongBg));
      expect(digit().style!.color, navy.userFg);
    });
  });

  testWidgets('the hinted cell ring and notes are yellow; another selected '
      'cell ring is the theme ring', (tester) async {
    final hinted = GameState.start(p).hint();
    final cell = hinted.hintedCell!;
    final notes = [...hinted.notes]..[cell] = const [1, 2];
    await pumpGrid(tester, hinted.copyWith(notes: notes));
    expect(painter(tester).ringColor, HsColors.hintYellow);
    final note = tester.widget<Text>(
      find.descendant(
        of: find.byKey(ValueKey('cell-$cell')),
        matching: find.text('1'),
      ),
    );
    expect(note.style!.color, HsColors.hintYellow);

    await pumpGrid(tester, GameState.start(p).select(1));
    expect(painter(tester).ringColor, navy.ring);
    expect(painter(tester).ringRect, isNotNull);

    await pumpGrid(tester, GameState.start(p));
    expect(painter(tester).ringRect, isNull, reason: 'no ring, no selection');
  });

  testWidgets('pencil marks sit in fixed slots and hide under a value', (
    tester,
  ) async {
    final s = GameState.start(p).select(1).toggleNoteMode().place(9).place(2);
    await pumpGrid(tester, s);
    final nine = tester.getCenter(
      find.descendant(
        of: find.byKey(const ValueKey('cell-1')),
        matching: find.text('9'),
      ),
    );
    final two = tester.getCenter(
      find.descendant(
        of: find.byKey(const ValueKey('cell-1')),
        matching: find.text('2'),
      ),
    );
    expect(nine.dy, greaterThan(two.dy), reason: '9 is in the bottom row');
    expect(nine.dx, greaterThan(two.dx), reason: '9 is in the right column');
  });

  testWidgets('both themes produce their own grid background', (tester) async {
    for (final theme in BoardTheme.all) {
      await pumpGrid(tester, GameState.start(p), theme: theme);
      final c = tester.widget<Container>(
        find
            .ancestor(
              of: find.byType(ClipRRect),
              matching: find.byType(Container),
            )
            .first,
      );
      expect((c.decoration! as BoxDecoration).color, theme.gridBg);
    }
    expect(BoardTheme.paper.gridBg, const Color(0xFFF7F5EF));
    expect(BoardTheme.navy.label, 'NAVY FELT');
  });

  testWidgets('tapping a cell reports its index', (tester) async {
    int? tapped;
    await pumpGrid(tester, GameState.start(p), onTap: (i) => tapped = i);
    await tester.tap(find.byKey(const ValueKey('cell-40')));
    expect(tapped, 40);
  });
}
