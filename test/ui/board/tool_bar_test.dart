import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:honest_sudoku/game/game.dart';
import 'package:honest_sudoku/ui/board/tool_bar.dart';
import 'package:honest_sudoku/ui/theme/tokens.dart';
import 'package:honest_sudoku/ui/widgets/design_button.dart';

import '../../game/fixtures.dart';
import '../harness.dart';

void main() {
  late Map<String, int> calls;

  Future<void> pumpTools(WidgetTester tester, GameState state) {
    calls = {};
    void hit(String n) => calls[n] = (calls[n] ?? 0) + 1;
    return pumpFramed(
      tester,
      ToolBar(
        state: state,
        scale: 1,
        onUndo: () => hit('undo'),
        onRedo: () => hit('redo'),
        onToggleNotes: () => hit('notes'),
        onErase: () => hit('erase'),
        onHint: () => hit('hint'),
        onCheck: () => hit('check'),
      ),
    );
  }

  testWidgets('each tool calls its own callback exactly once', (tester) async {
    // Two entries and one undo: something to undo and something to redo.
    final s = GameState.start(classic)
        .select(1)
        .place(classic.solution[1])
        .select(3)
        .place(classic.solution[3])
        .undo();
    expect((s.canUndo, s.canRedo), (true, true));
    await pumpTools(tester, s);
    for (final name in ['undo', 'redo', 'notes', 'erase', 'hint', 'check']) {
      await tester.tap(find.byKey(ValueKey('tool-$name')));
    }
    expect(calls, {
      'undo': 1,
      'redo': 1,
      'notes': 1,
      'erase': 1,
      'hint': 1,
      'check': 1,
    });
  });

  testWidgets('undo and redo are inert with nothing to undo or redo', (
    tester,
  ) async {
    await pumpTools(tester, GameState.start(classic));
    await tester.tap(find.byKey(const ValueKey('tool-undo')));
    await tester.tap(find.byKey(const ValueKey('tool-redo')));
    expect(calls, isEmpty);
  });

  testWidgets('with auto-notes the notes tool reads AUTO and ignores taps', (
    tester,
  ) async {
    await pumpTools(
      tester,
      GameState.start(classic, const GameSettings(autoNotes: true)),
    );
    expect(find.text('AUTO'), findsOneWidget);
    expect(find.text('NOTES'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('tool-notes')));
    expect(calls['notes'], isNull);
  });

  testWidgets('notes is yellow only in effective note mode', (tester) async {
    DesignButton notes() =>
        tester.widget<DesignButton>(find.byKey(const ValueKey('tool-notes')));
    await pumpTools(tester, GameState.start(classic).toggleNoteMode());
    expect(notes().spec.fg, HsColors.hintYellow);
    await pumpTools(tester, GameState.start(classic));
    expect(notes().spec.fg, HsColors.toolFg);
    expect(
      tester
          .widget<DesignButton>(find.byKey(const ValueKey('tool-undo')))
          .spec
          .bg,
      HsColors.fill06,
    );
  });
}
