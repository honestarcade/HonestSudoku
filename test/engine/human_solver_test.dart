import 'package:flutter_test/flutter_test.dart';
import 'package:honest_sudoku/engine/engine.dart';

import 'grid_strings.dart';

// Arto Inkala's "AI Escargot" (2006), published as among the hardest 9×9
// puzzles; nothing on this ladder cracks it.
const _escargot = '''
  1....7.9.
  .3..2...8
  ..96..5..
  ..53..9..
  .1..8...2
  6....4...
  3......1.
  .4......7
  ..7...3..
''';

// Found by adding givens back to a generated Hard board while it stayed
// Hard: 45 givens, the Easy target count, yet it needs a naked pair.
const _hardAt45 = '''
  4..3.7951
  7...9.684
  1.9.6423.
  ..12...9.
  39.......
  824973165
  6457..319
  91.......
  2.8..9.46
''';

void main() {
  test('a fully given board is Easy with no steps', () {
    final g = grade(GridShape.classic, basePattern(GridShape.classic));
    expect(
      [g.technique, g.band, g.steps],
      [Technique.none, Difficulty.easy, <Step>[]],
    );
  });

  test('AI Escargot is beyond the ladder, so Evil', () {
    final g = grade(GridShape.classic, parseGrid(GridShape.classic, _escargot));
    expect(g.technique, Technique.beyond);
    expect(g.band, Difficulty.evil);
  });

  test('the band comes from the technique, not the givens count', () {
    final values = parseGrid(GridShape.classic, _hardAt45);
    expect(values.where((v) => v != 0).length, 45);
    expect(targetGivens(GridShape.classic, Difficulty.easy), 45);
    expect(countSolutions(GridShape.classic, values), 1);
    final g = grade(GridShape.classic, values);
    expect(g.technique, Technique.nakedPair);
    expect(g.band, Difficulty.hard);
  });

  test('each technique maps to its band at every boundary', () {
    expect(
      {for (final t in Technique.values) t.name: t.band.key},
      {
        'none': 'easy',
        'nakedSingle': 'easy',
        'hiddenSingle': 'easy',
        'pointing': 'medium',
        'claiming': 'medium',
        'nakedPair': 'hard',
        'hiddenPair': 'hard',
        'nakedTriple': 'expert',
        'hiddenTriple': 'expert',
        'xWing': 'expert',
        'beyond': 'evil',
      },
    );
  });

  test('the ladder is ordered easiest first', () {
    expect(kLadder.map((r) => r.technique), [
      Technique.nakedSingle,
      Technique.hiddenSingle,
      Technique.pointing,
      Technique.claiming,
      Technique.nakedPair,
      Technique.hiddenPair,
      Technique.nakedTriple,
      Technique.hiddenTriple,
      Technique.xWing,
    ]);
  });

  test('a ceiling stops grading once the board needs a harder band', () {
    final values = parseGrid(GridShape.classic, _hardAt45);
    final capped = const HumanSolver().grade(
      GridShape.classic,
      values,
      ceiling: Difficulty.medium,
    );
    expect(capped.band.index, greaterThan(Difficulty.medium.index));
    final escargot = const HumanSolver().grade(
      GridShape.classic,
      parseGrid(GridShape.classic, _escargot),
      ceiling: Difficulty.expert,
    );
    expect(escargot.band, Difficulty.evil);
  });

  test('a clash or a dead cell is an InvalidBoard', () {
    final dup = parseGrid(GridShape.classic, _escargot)..[1] = 1;
    expect(() => grade(GridShape.classic, dup), throwsA(isA<InvalidBoard>()));
    final dead = parseGrid(GridShape.mini, '''
      .12.
      3...
      4...
      ....
    ''');
    expect(
      () => grade(GridShape.mini, dead),
      throwsA(isA<InvalidBoard>().having((e) => e.cell, 'cell', 0)),
    );
  });

  test('onStep reports the share of cells filled, rising to 1', () {
    final seen = <double>[];
    const HumanSolver().grade(
      GridShape.classic,
      parseGrid(GridShape.classic, _hardAt45),
      onStep: seen.add,
    );
    expect(seen.last, 1.0);
    for (var i = 1; i < seen.length; i++) {
      expect(seen[i], greaterThan(seen[i - 1]));
    }
  });
}
