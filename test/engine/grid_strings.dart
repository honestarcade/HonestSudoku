// Parses readable grid fixtures: newline-separated rows, `.` for an empty
// cell, and the design's symbols (1–9 then A–G) for values.

import 'package:honest_sudoku/engine/engine.dart';

/// Parses [text] into a row-major value list for [shape].
List<int> parseGrid(GridShape shape, String text) {
  final rows = text
      .split('\n')
      .map((r) => r.trim())
      .where((r) => r.isNotEmpty)
      .toList();
  if (rows.length != shape.n) {
    throw ArgumentError('expected ${shape.n} rows, got ${rows.length}');
  }
  final out = <int>[];
  for (final row in rows) {
    if (row.length != shape.n) {
      throw ArgumentError('row "$row" is not ${shape.n} wide');
    }
    for (final ch in row.split('')) {
      out.add(ch == '.' ? 0 : kSymbols.indexOf(ch) + 1);
    }
  }
  return out;
}

/// The design's base pattern for [shape]: a valid full grid.
List<int> basePattern(GridShape shape) => [
  for (var r = 0; r < shape.n; r++)
    for (var c = 0; c < shape.n; c++)
      (shape.boxW * (r % shape.boxH) + r ~/ shape.boxH + c) % shape.n + 1,
];
