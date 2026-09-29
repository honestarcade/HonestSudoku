import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:honest_sudoku/engine/engine.dart';
import 'package:honest_sudoku/game/game.dart';
import 'package:honest_sudoku/ui/board/board_styles.dart';
import 'package:honest_sudoku/ui/board/number_pad.dart';
import 'package:honest_sudoku/ui/theme/tokens.dart';
import 'package:honest_sudoku/ui/widgets/design_button.dart';

import '../../game/fixtures.dart';
import '../harness.dart';

Future<void> pumpPad(
  WidgetTester tester,
  GameState state, {
  double scale = 1,
  ValueChanged<int>? onPlace,
  VoidCallback? onErase,
}) => pumpFramed(
  tester,
  NumberPad(
    state: state,
    scale: scale,
    onPlace: onPlace ?? (_) {},
    onErase: onErase ?? () {},
  ),
);

ButtonStyleSpec spec(WidgetTester tester, String key) =>
    tester.widget<DesignButton>(find.byKey(ValueKey(key))).spec;

Text keyText(WidgetTester tester, String key) => tester.widget<Text>(
  find.descendant(of: find.byKey(ValueKey(key)), matching: find.byType(Text)),
);

void main() {
  // The design's pad per size: columns, key height and key font size.
  const design = {
    4: (cols: 4, height: 52.0, font: 19.0),
    6: (cols: 6, height: 52.0, font: 19.0),
    9: (cols: 5, height: 52.0, font: 19.0),
    16: (cols: 4, height: 40.0, font: 15.0),
  };

  for (final shape in GridShape.all) {
    for (final scale in [1.0, .9]) {
      testWidgets('${shape.label} at $scale: n keys in the design columns, '
          'height and font', (tester) async {
        await pumpPad(
          tester,
          GameState.start(fixturePuzzle(shape)),
          scale: scale,
        );
        final want = design[shape.n]!;
        final xs = <double>{};
        for (var v = 1; v <= shape.n; v++) {
          xs.add(tester.getTopLeft(find.byKey(ValueKey('pad-$v'))).dx);
        }
        expect(xs, hasLength(want.cols), reason: 'design columns');
        expect(
          tester.getSize(find.byKey(const ValueKey('pad-1'))).height,
          want.height * scale,
          reason: 'design key height',
        );
        expect(
          keyText(tester, 'pad-1').style!.fontSize,
          want.font * scale,
          reason: 'design key font size',
        );
        expect(
          find.byKey(const ValueKey('pad-erase')),
          shape.n == 9 ? findsOneWidget : findsNothing,
        );
      });
    }
  }

  testWidgets('the 9×9 erase key: its font and colours', (tester) async {
    await pumpPad(tester, GameState.start(classic));
    expect(keyText(tester, 'pad-erase').data, '⌫');
    expect(
      keyText(tester, 'pad-erase').style!.fontSize,
      17,
      reason: 'erase key font 17',
    );
    final erase = spec(tester, 'pad-erase');
    expect(erase.edge, const Color.fromRGBO(255, 255, 255, .14));
    expect(erase.bg, const Color.fromRGBO(255, 255, 255, .04));
    expect(erase.fg, const Color(0xFF9FC3EE));
  });

  testWidgets('tapping 7 places 7; the erase key erases', (tester) async {
    int? placed;
    var erased = 0;
    await pumpPad(
      tester,
      GameState.start(classic),
      onPlace: (v) => placed = v,
      onErase: () => erased++,
    );
    await tester.tap(find.byKey(const ValueKey('pad-7')));
    expect(placed, 7);
    await tester.tap(find.byKey(const ValueKey('pad-erase')));
    expect(erased, 1);
  });

  testWidgets('16×16 shows A for 10', (tester) async {
    await pumpPad(tester, GameState.start(fixturePuzzle(GridShape.monster)));
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('pad-10')),
        matching: find.text('A'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('note mode turns keys yellow; leaving it restores them', (
    tester,
  ) async {
    final s = GameState.start(classic);
    await pumpPad(tester, s.toggleNoteMode());
    expect(spec(tester, 'pad-1').fg, HsColors.hintYellow);
    expect(spec(tester, 'pad-1').edge, HsColors.noteKeyEdge);
    await pumpPad(tester, s);
    expect(spec(tester, 'pad-1').fg, HsColors.textBright);
    await pumpPad(
      tester,
      s.withSettings(const GameSettings(autoNotes: true)).toggleNoteMode(),
    );
    expect(
      spec(tester, 'pad-1').fg,
      HsColors.textBright,
      reason: 'auto-notes: the pad still places values',
    );
  });

  testWidgets('a finished number fades only with dimDone on, and stays '
      'tappable', (tester) async {
    // Fill every 1 on the board.
    var s = GameState.start(classic);
    for (var i = 0; i < 81; i++) {
      if (classic.solution[i] == 1 && !classic.givens[i]) {
        s = s.select(i).place(1);
      }
    }
    expect(s.countOf(1), 9);
    int? placed;
    await pumpPad(tester, s, onPlace: (v) => placed = v);
    expect(spec(tester, 'pad-1').opacity, .32);
    expect(spec(tester, 'pad-2').opacity, 1);
    await tester.tap(find.byKey(const ValueKey('pad-1')));
    expect(placed, 1, reason: 'a dimmed key stays tappable');
    await pumpPad(tester, s.withSettings(const GameSettings(dimDone: false)));
    expect(spec(tester, 'pad-1').opacity, 1);
  });
}
