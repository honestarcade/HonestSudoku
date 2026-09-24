import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:honest_sudoku/engine/engine.dart';
import 'package:honest_sudoku/ui/theme/tokens.dart';
import 'package:honest_sudoku/ui/widgets/app_mark.dart';
import 'package:honest_sudoku/ui/widgets/app_mark_data.dart';

int _paint(AppMarkPainter painter, double size) {
  final recorder = ui.PictureRecorder();
  painter.paint(Canvas(recorder), Size.square(size));
  recorder.endRecording().dispose();
  return painter.paragraphsDrawn;
}

void main() {
  group('the digits', () {
    test('29 givens, symmetric under a half turn', () {
      expect(kMarkGivens, hasLength(29));
      final at = {for (final d in kMarkGivens) (d.row, d.col)};
      expect(at, hasLength(29), reason: 'no cell twice');
      for (final (r, c) in at) {
        expect(at, contains((8 - r, 8 - c)), reason: '($r, $c)');
      }
    });

    test('the three entries sit in empty cells', () {
      expect(kMarkEntries, hasLength(3));
      final givens = {for (final d in kMarkGivens) (d.row, d.col)};
      for (final d in kMarkEntries) {
        expect(givens, isNot(contains((d.row, d.col))));
      }
    });

    test('the 32 values break no row, column or box', () {
      final values = List.filled(81, 0);
      for (final d in [...kMarkGivens, ...kMarkEntries]) {
        expect(d.value, inInclusiveRange(1, 9));
        values[d.row * 9 + d.col] = d.value;
      }
      expect(isConsistent(GridShape.classic, values), isTrue);
    });
  });

  group('the painter', () {
    test('board draws 32 digits; none draws none', () {
      expect(_paint(AppMarkPainter(interior: MarkInterior.board), 132), 32);
      expect(_paint(AppMarkPainter(interior: MarkInterior.none), 132), 0);
    });

    test('a second paint at a new size lays out again and still draws 32', () {
      final p = AppMarkPainter(interior: MarkInterior.board);
      expect(_paint(p, 132), 32);
      expect(_paint(p, 52), 32);
      expect(_paint(p, 52), 32, reason: 'the counter resets each paint');
    });

    test('shouldRepaint only for a new interior or new colours', () {
      final a = AppMarkPainter(interior: MarkInterior.board);
      expect(
        a.shouldRepaint(AppMarkPainter(interior: MarkInterior.board)),
        isFalse,
      );
      expect(a.shouldRepaint(AppMarkPainter()), isTrue);
      expect(
        a.shouldRepaint(
          AppMarkPainter(
            interior: MarkInterior.board,
            cornerColors: const [
              HsColors.teal,
              HsColors.violet,
              HsColors.blue,
              HsColors.navy,
            ],
          ),
        ),
        isTrue,
      );
    });
  });

  testWidgets('the mark exposes no semantics nodes, either interior', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    for (final interior in MarkInterior.values) {
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Center(child: AppMark(size: 132, interior: interior)),
        ),
      );
      final node = tester.getSemantics(find.byType(AppMark));
      var count = 0;
      node.visitChildren((_) {
        count++;
        return true;
      });
      expect(count, 0, reason: '$interior');
      expect(node.label, isEmpty, reason: '$interior');
    }
    handle.dispose();
  });
}
