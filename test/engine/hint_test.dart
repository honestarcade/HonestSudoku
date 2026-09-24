import 'package:flutter_test/flutter_test.dart';
import 'package:honest_sudoku/engine/engine.dart';

import 'design_strings.dart';
import 'grid_strings.dart';

const _euler01 = '''
  ..3.2.6..
  9..3.5..1
  ..18.64..
  ..81.29..
  7.......8
  ..67.82..
  ..26.95..
  8..2.3..9
  ..5.1.3..
''';
final _eulerSolution = parseGrid(GridShape.classic, '''
  483921657
  967345821
  251876493
  548132976
  729564138
  136798245
  372689514
  814253769
  695417382
''');

// A board where the only single is a hidden one in a box (found by search,
// its hint confirmed by the design's own hint() in node).
const _boxBoard = '''
  4...9.3..
  .1.7.2...
  .6.......
  .46981...
  .574..1..
  ..1..76.4
  .....4.62
  .3...9.18
  .2.8...7.
''';
final _boxSolution = parseGrid(GridShape.classic, '''
  472698351
  513742896
  968153247
  246981735
  357426189
  891537624
  185374962
  734269518
  629815473
''');

List<int> _with(List<int> base, Map<int, int> cells) {
  final out = List.of(base);
  cells.forEach((i, v) => out[i] = v);
  return out;
}

void main() {
  group('naked single', () {
    test('4×4: the one empty cell', () {
      final solution = basePattern(GridShape.mini);
      final h = nextHint(GridShape.mini, _with(solution, {0: 0}), solution)!;
      expect(h.kind, HintKind.nakedSingle);
      expect(h.tag, 'NAKED SINGLE');
      expect(h.body, nakedR1C1is1);
      expect([h.cellIndex, h.value], [0, 1]);
      expect(h.banner, BannerKind.hint);
    });

    test('6×6: box of two rows by three columns', () {
      final solution = basePattern(GridShape.short);
      final h = nextHint(GridShape.short, _with(solution, {7: 0}), solution)!;
      expect(h.body, nakedR2C2is5);
    });

    test('9×9: a later single, not the first empty cell', () {
      final values = parseGrid(GridShape.classic, _euler01);
      expect(candidates(GridShape.classic, values, 0).length, greaterThan(1));
      final h = nextHint(GridShape.classic, values, _eulerSolution)!;
      expect(h.kind, HintKind.nakedSingle);
      expect(h.body, nakedR5C6is4);
      expect(h.cellIndex, isNot(0));
    });

    test('16×16 speaks A–G, and says only "Try" with explanations off', () {
      final solution = basePattern(GridShape.monster);
      final values = _with(solution, {9: 0});
      expect(
        nextHint(GridShape.monster, values, solution)!.body,
        nakedR1C10isA,
      );
      expect(
        nextHint(GridShape.monster, values, solution, explain: false)!.body,
        tryR1C10,
      );
    });

    test('preferred over a hidden single earlier in unit order', () {
      // Row 1 holds a hidden single for 1 at R1C1 (the fixture below), and
      // row 9 is full but for R9C9, a naked single. Naked singles are
      // searched first, so R9C9 wins although R1C1 comes first.
      final values = List.filled(81, 0);
      for (final i in [12, 24, 28, 56]) {
        values[i] = 1;
      }
      values.setRange(72, 80, [6, 9, 5, 4, 1, 7, 3, 8]);
      final h = nextHint(GridShape.classic, values, _eulerSolution)!;
      expect(h.kind, HintKind.nakedSingle);
      expect(h.body, nakedR9C9is2);
    });
  });

  group('hidden single', () {
    test('9×9: named by its row', () {
      final values = List.filled(81, 0);
      for (final i in [12, 24, 28, 56]) {
        values[i] = 1; // R2C4, R3C7, R4C2, R7C3
      }
      final h = nextHint(GridShape.classic, values, _eulerSolution)!;
      expect(h.kind, HintKind.hiddenSingle);
      expect(h.tag, 'HIDDEN SINGLE');
      expect(h.body, hidden1Row1);
      expect(h.unitName, 'row 1');
      expect([h.cellIndex, h.value], [0, 1]);
    });

    test('9×9: named "this box"', () {
      final values = parseGrid(GridShape.classic, _boxBoard);
      final h = nextHint(GridShape.classic, values, _boxSolution)!;
      expect(h.body, hidden3Box);
      expect(h.unitName, 'this box');
      expect(
        nextHint(GridShape.classic, values, _boxSolution, explain: false)!.body,
        tryR9C9,
      );
    });

    test('16×16: A fits in only one cell of row 1', () {
      final values = List.filled(256, 0);
      for (final (r, c) in [(4, 1), (8, 2), (12, 3), (1, 4), (2, 8), (3, 12)]) {
        values[r * 16 + c] = 10;
      }
      final h = nextHint(
        GridShape.monster,
        values,
        basePattern(GridShape.monster),
      )!;
      expect(h.body, hiddenARow1);
    });
  });

  group('harder step', () {
    test('9×9: an empty board reveals the first cell from the solution', () {
      final h = nextHint(
        GridShape.classic,
        List.filled(81, 0),
        _eulerSolution,
      )!;
      expect(h.kind, HintKind.harderStep);
      expect(h.tag, 'HARDER STEP');
      expect(h.body, harderR1C1is4);
      expect(
        nextHint(
          GridShape.classic,
          List.filled(81, 0),
          _eulerSolution,
          explain: false,
        )!.body,
        harderR1C1is4,
        reason: 'a harder step always explains',
      );
    });

    test('16×16: reveals G', () {
      final solution = [
        for (final v in basePattern(GridShape.monster)) (v + 14) % 16 + 1,
      ];
      expect(
        nextHint(GridShape.monster, List.filled(256, 0), solution)!.body,
        harderR1C1isG,
      );
    });

    test('4×4 explanations off still name a single with Try', () {
      final solution = basePattern(GridShape.mini);
      expect(
        nextHint(
          GridShape.mini,
          _with(solution, {0: 0}),
          solution,
          explain: false,
        )!.body,
        tryR1C1,
      );
    });
  });

  test('a full board has no hint', () {
    final solution = basePattern(GridShape.mini);
    expect(nextHint(GridShape.mini, solution, solution), isNull);
  });

  test('a wrong entry counts as placed and shrinks its peers', () {
    // R1C2 holds a wrong 1. R1C1's true value is 1, but the wrong entry
    // removes 1 from its candidates, as in the prototype.
    final solution = basePattern(GridShape.mini);
    final values = _with(solution, {0: 0, 1: 1});
    expect(candidates(GridShape.mini, values, 0), isNot(contains(1)));
    expect(check(GridShape.mini, values, solution).wrongCells, [1]);
  });

  test('the value follows the candidate, not the solution', () {
    // R1C2 holds a wrong 1 and R3C1 is empty, so R1C1's only candidate is 2
    // although its solution is 1 — the prototype says 2 as well.
    final solution = basePattern(GridShape.mini);
    final values = _with(solution, {0: 0, 1: 1, 8: 0});
    final h = nextHint(GridShape.mini, values, solution)!;
    expect(h.kind, HintKind.nakedSingle);
    expect([h.cellIndex, h.value, solution[0]], [0, 2, 1]);
  });

  test('both lists are validated', () {
    expect(
      () => nextHint(GridShape.mini, List.filled(16, 0), List.filled(15, 1)),
      throwsArgumentError,
    );
  });
}
