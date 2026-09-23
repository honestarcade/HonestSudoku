/// The Sudoku engine's public API.
///
/// Plain Dart with no Flutter import, so it runs in an isolate and in tests
/// without a device.
library;

export 'candidates.dart';
export 'full_grid.dart';
export 'generator.dart';
export 'grid.dart';
export 'list_equality.dart';
export 'puzzle.dart';
export 'rng.dart';
export 'solver.dart' show countSolutions, isConsistent, solve;
export 'units.dart' show Unit, UnitKind, unitList, unitsOf;
