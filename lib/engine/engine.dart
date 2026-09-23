/// The Sudoku engine's public API.
///
/// Plain Dart with no Flutter import, so it runs in an isolate and in tests
/// without a device.
library;

export 'candidate_grid.dart';
export 'candidates.dart';
export 'check.dart';
export 'difficulty.dart';
export 'full_grid.dart';
export 'generator.dart';
export 'grid.dart';
export 'hint.dart';
export 'human_solver.dart';
export 'list_equality.dart';
export 'puzzle.dart';
export 'rng.dart';
export 'solver.dart' show countSolutions, isConsistent, solve;
export 'strings.dart';
export 'techniques/hidden_single.dart';
export 'techniques/hidden_subset.dart';
export 'techniques/locked_candidates.dart';
export 'techniques/naked_single.dart';
export 'techniques/naked_subset.dart';
export 'techniques/subsets.dart' show combinations;
export 'techniques/technique.dart';
export 'techniques/x_wing.dart';
export 'units.dart' show Unit, UnitKind, unitList, unitsOf;
