// A valid full grid from the seeded stream, exactly as the design's
// `fullGrid` builds one: the base pattern, then the band order and each
// band's rows, then the stack order and each stack's columns, then a
// relabelling of the values. The draws happen in that order, row draws
// interleaved per band, so the same seed gives the design's board.

import 'grid.dart';
import 'rng.dart';

List<int> _seq(int n) => List<int>.generate(n, (i) => i);

/// A full valid grid for [shape], row-major, drawn from [rng].
List<int> fullGrid(GridShape shape, Rng rng) {
  final n = shape.n;
  final bh = shape.boxH;
  final bw = shape.boxW;
  int base(int row, int col) => (bw * (row % bh) + row ~/ bh + col) % n + 1;

  final rowOrder = <int>[];
  for (final band in rng.shuffle(_seq(n ~/ bh))) {
    for (final i in rng.shuffle(_seq(bh))) {
      rowOrder.add(band * bh + i);
    }
  }
  final colOrder = <int>[];
  for (final stack in rng.shuffle(_seq(n ~/ bw))) {
    for (final i in rng.shuffle(_seq(bw))) {
      colOrder.add(stack * bw + i);
    }
  }
  final relabel = [0, ...rng.shuffle(_seq(n)).map((v) => v + 1)];

  return [
    for (var row = 0; row < n; row++)
      for (var col = 0; col < n; col++)
        relabel[base(rowOrder[row], colOrder[col])],
  ];
}
