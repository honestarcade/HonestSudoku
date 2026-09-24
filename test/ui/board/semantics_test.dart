import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:honest_sudoku/engine/engine.dart';
import 'package:honest_sudoku/game/game.dart';
import 'package:honest_sudoku/ui/board/board_screen.dart';
import 'package:honest_sudoku/ui/board/game_controller.dart';

import '../helpers.dart';
import '../stub_generator.dart';

/// A board over the fixture (givens on even cells) with semantics on.
Future<void> board(
  WidgetTester tester,
  Future<void> Function(GameController c) body, {
  GridShape shape = GridShape.classic,
  AppSettings settings = const AppSettings(),
}) async {
  final handle = tester.ensureSemantics();
  setScreen(tester, 390, 844);
  final c = GameController(
    generator: StubGenerator().call,
    seeds: CountingSeeds(),
    settings: settings,
  );
  final routes = RouteObserver<ModalRoute<void>>();
  await tester.pumpWidget(
    MaterialApp(
      navigatorObservers: [routes],
      home: BoardScreen(controller: c, routeObserver: routes),
    ),
  );
  c.startNew(shape, Difficulty.medium);
  await tester.pump();
  await tester.pump();
  await body(c);
  await tester.pumpWidget(const SizedBox());
  c.dispose();
  handle.dispose();
}

SemanticsNode cell(WidgetTester tester, int i) =>
    tester.getSemantics(find.byKey(ValueKey('cell-$i')));

String label(WidgetTester tester, String key) =>
    tester.getSemantics(find.byKey(ValueKey(key))).label;

int wrongFor(GameController c, int i) => c.state!.solution[i] % c.state!.n + 1;

/// Every labelled node under [node], in traversal order.
List<String> traversal(SemanticsNode node) => [
  for (final child in node.debugListChildrenInOrder(
    DebugSemanticsDumpOrder.traversalOrder,
  )) ...[if (child.label.isNotEmpty) child.label, ...traversal(child)],
];

void main() {
  testWidgets('a given reads given; a player\'s entry does not', (
    tester,
  ) async {
    await board(tester, (c) async {
      expect(cell(tester, 0).label, endsWith(', given'));
      expect(cell(tester, 0).label, startsWith('Row 1, column 1, '));
      c.select(1);
      c.place(c.state!.solution[1]);
      await tester.pump();
      expect(cell(tester, 1).label, 'Row 1, column 2, ${c.state!.solution[1]}');
    });
  });

  testWidgets('an empty cell with notes 1 4 7 reads them', (tester) async {
    await board(tester, (c) async {
      c.toggleNotes();
      c.select(3);
      for (final v in [1, 4, 7]) {
        c.place(v);
      }
      await tester.pump();
      expect(cell(tester, 3).label, 'Row 1, column 4, empty, notes 1 4 7');
    });
  });

  testWidgets('only the selected cell carries the selected flag', (
    tester,
  ) async {
    await board(tester, (c) async {
      await tester.tap(find.byKey(const ValueKey('cell-5')));
      await tester.pump();
      expect(cell(tester, 5), isSemantics(isSelected: true));
      for (final i in [3, 7, 13]) {
        expect(cell(tester, i), isSemantics(isSelected: false));
      }
    });
  });

  testWidgets('a cell node\'s tap selects it', (tester) async {
    await board(tester, (c) async {
      tester.semantics.tap(
        find.semantics.byLabel(RegExp(r'^Row 1, column 8,')),
      );
      await tester.pump();
      expect(c.state!.selected, 7);
    });
  });

  for (final announce in AnnounceMode.values) {
    testWidgets(
      'a wrong entry ${announce == AnnounceMode.now ? 'reads' : 'does not read'} '
      'wrong (${announce.name})',
      (tester) async {
        await board(
          tester,
          settings: AppSettings(lastSetup: LastSetup(announce: announce)),
          (c) async {
            c.select(1);
            c.place(wrongFor(c, 1));
            await tester.pump();
            expect(
              cell(tester, 1).label.contains('wrong'),
              announce == AnnounceMode.now,
            );
          },
        );
      },
    );
  }

  testWidgets('the hinted cell reads hint', (tester) async {
    await board(tester, (c) async {
      c.hint();
      await tester.pump();
      final hinted = c.state!.hintedCell!;
      expect(cell(tester, hinted).label, endsWith(', hint'));
    });
  });

  testWidgets('a 16×16 cell holding 12 reads C', (tester) async {
    await board(tester, shape: GridShape.monster, (c) async {
      final s = c.state!;
      final i = [
        for (var j = 0; j < 256; j++)
          if (s.isGiven(j) && s.values[j] == 12) j,
      ].first;
      expect(cell(tester, i).label, endsWith(', C, given'));
    });
  });

  testWidgets('pad keys read Place, then Note in note mode', (tester) async {
    await board(tester, (c) async {
      expect(label(tester, 'pad-3'), 'Place 3');
      expect(label(tester, 'pad-erase'), 'Erase');
      c.toggleNotes();
      await tester.pump();
      expect(label(tester, 'pad-3'), 'Note 3');
      expect(label(tester, 'tool-notes'), 'Notes, on');
      expect(
        tester.getSemantics(find.byKey(const ValueKey('tool-notes'))),
        isSemantics(isToggled: true),
      );
    });
  });

  testWidgets('a finished number\'s key reads all placed', (tester) async {
    await board(tester, (c) async {
      final s = c.state!;
      for (var i = 0; i < 81; i++) {
        if (!s.isGiven(i) && s.solution[i] == 1) {
          c.select(i);
          c.place(1);
        }
      }
      await tester.pump();
      expect(label(tester, 'pad-1'), 'Place 1, all placed');
      expect(label(tester, 'pad-2'), 'Place 2');
    });
  });

  testWidgets('tools and chips speak, and inert ones say so', (tester) async {
    await board(tester, (c) async {
      expect(label(tester, 'tool-undo'), 'Undo');
      expect(
        tester.getSemantics(find.byKey(const ValueKey('tool-undo'))),
        isSemantics(isEnabled: false, hasTapAction: false),
      );
      expect(label(tester, 'tool-hint'), 'Hint');
      expect(label(tester, 'chip-timer'), startsWith('Time '));
      expect(label(tester, 'chip-strike'), '0 of 3 mistakes');
      expect(label(tester, 'pause-button'), 'Pause, 9 by 9, Medium');
      expect(
        tester.getSemantics(find.byKey(const ValueKey('chip-strike'))),
        isSemantics(isLiveRegion: true, isButton: false),
      );
    });
  });

  testWidgets('the banner is one live region whose label follows the notice', (
    tester,
  ) async {
    await board(tester, (c) async {
      SemanticsNode live() =>
          tester.getSemantics(find.byKey(const ValueKey('notice-live')));
      expect(live(), isSemantics(isLiveRegion: true, label: ''));
      c.select(1);
      c.place(wrongFor(c, 1));
      await tester.pump();
      expect(live(), isSemantics(isLiveRegion: true));
      expect(live().label, startsWith('Mistake. '));
      c.erase();
      c.hint();
      await tester.pump();
      expect(live().label, isNot(startsWith('Mistake')));
      expect(live().label, isNotEmpty);
    });
  });

  testWidgets('the win title is announced by a live region', (tester) async {
    await board(tester, (c) async {
      SemanticsNode live() =>
          tester.getSemantics(find.byKey(const ValueKey('overlay-live')));
      expect(live().label, '');
      final s = c.state!;
      for (var i = 0; i < 81; i++) {
        if (!s.isGiven(i)) {
          c.select(i);
          c.place(s.solution[i]);
        }
      }
      await tester.pump();
      expect(
        live(),
        isSemantics(isLiveRegion: true, label: 'Puzzle solved. Grid complete.'),
      );
      // On the card's first frame, before it has risen: the tiles are
      // already reachable, and a time is spoken, never read as 0:00.
      expect(
        find.bySemanticsLabel(RegExp(r'^Time, \d+ seconds?$')),
        findsOneWidget,
      );
    });
  });

  testWidgets('while paused there is no cell to reach, and the title is '
      'announced', (tester) async {
    await board(tester, (c) async {
      expect(find.bySemanticsLabel(RegExp('^Row ')), findsNWidgets(81));
      c.pause();
      await tester.pump();
      expect(find.bySemanticsLabel(RegExp('^Row ')), findsNothing);
      expect(label(tester, 'overlay-live'), 'Paused');
      expect(
        find.bySemanticsLabel(RegExp(r'^9 by 9, Medium, ')),
        findsOneWidget,
      );
    });
  });

  testWidgets('traversal: top bar, then cells in row order, then banner, pad '
      'and tools', (tester) async {
    await board(tester, (c) async {
      c.select(1);
      c.place(wrongFor(c, 1));
      await tester.pump();
      final order = traversal(
        tester.getSemantics(find.byKey(const ValueKey('overlay-live'))),
      );
      int at(bool Function(String) test) => order.indexWhere(test);
      final pause = at((l) => l.startsWith('Pause, '));
      final firstCell = at((l) => l.startsWith('Row '));
      final banner = at((l) => l.startsWith('Mistake. '));
      final pad = at((l) => l == 'Place 1');
      final tools = at((l) => l == 'Undo');
      expect(
        [pause, firstCell, banner, pad, tools].every((i) => i >= 0),
        isTrue,
        reason: '$order',
      );
      expect(pause < firstCell, isTrue, reason: '$order');
      expect(firstCell < banner && banner < pad && pad < tools, isTrue);
      final cells = order.where((l) => l.startsWith('Row ')).take(9).toList();
      expect(cells, [
        for (var col = 1; col <= 9; col++)
          predicate<String>((l) => l.startsWith('Row 1, column $col,')),
      ]);
    });
  });
}
