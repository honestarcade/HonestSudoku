import 'package:flutter_test/flutter_test.dart';
import 'package:honest_sudoku/engine/engine.dart';

import 'staging.dart';

void main() {
  test('naked pair: two cells holding the same two values', () {
    final g = openGrid();
    g.cands[0] = bits([1, 2]);
    g.cands[1] = bits([1, 2]);
    expect(easierFindNothing(g, Technique.nakedPair), isTrue);
    final step = const NakedSubset.pair().apply(g)!;
    expect(step.technique, Technique.nakedPair);
    expect(step.cells, [0, 1]);
    // Row 1 and box 1 both lose 1 and 2, in one step.
    expect(g.cands[rc(0, 8)] & bits([1, 2]), 0);
    expect(g.cands[rc(2, 2)] & bits([1, 2]), 0);
    expect(
      g.cands[rc(8, 0)] & bits([1, 2]),
      bits([1, 2]),
      reason:
          'not a '
          'shared unit',
    );
  });

  test('naked triple: three cells spanning three values, two each', () {
    final g = openGrid();
    g.cands[0] = bits([1, 2]);
    g.cands[1] = bits([2, 3]);
    g.cands[2] = bits([1, 3]);
    expect(easierFindNothing(g, Technique.nakedTriple), isTrue);
    final step = const NakedSubset.triple().apply(g)!;
    expect(step.technique, Technique.nakedTriple);
    expect(step.cells, [0, 1, 2]);
    expect(g.cands[rc(0, 5)] & bits([1, 2, 3]), 0);
  });

  test('triples are skipped on 4×4, where they are degenerate', () {
    final g = openGrid(GridShape.mini);
    g.cands[0] = bits([1, 2]);
    g.cands[1] = bits([2, 3]);
    g.cands[2] = bits([1, 3]);
    expect(const NakedSubset.triple().apply(g), isNull);
    expect(subsetsApply(GridShape.mini), [true, false]);
  });

  test('find nothing on an open grid', () {
    expect(const NakedSubset.pair().apply(openGrid()), isNull);
    expect(const NakedSubset.triple().apply(openGrid()), isNull);
  });
}

List<bool> subsetsApply(GridShape s) => [
  const NakedSubset.pair().apply(_pairGrid(s)) != null,
  const NakedSubset.triple().apply(_tripleGrid(s)) != null,
];

CandidateGrid _pairGrid(GridShape s) {
  final g = openGrid(s);
  g.cands[0] = bits([1, 2]);
  g.cands[1] = bits([1, 2]);
  return g;
}

CandidateGrid _tripleGrid(GridShape s) {
  final g = openGrid(s);
  g.cands[0] = bits([1, 2]);
  g.cands[1] = bits([2, 3]);
  g.cands[2] = bits([1, 3]);
  return g;
}
