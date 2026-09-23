// The five difficulty bands, with the design's DIFFS keys, labels,
// descriptions and keep ratios, and which bands each shape supports.
//
// A band is decided by the hardest technique a board needs (see
// techniques/technique.dart, `Technique.band`), never by its givens count.
// The keep ratio only sets the count generation aims for, so the setup
// screen's "N GIVENS" matches the design.

import 'grid.dart';

/// A difficulty band.
enum Difficulty {
  easy(
    'easy',
    'Easy',
    'Every step is a plain single. A calm ten minutes.',
    0.55,
  ),
  medium(
    'medium',
    'Medium',
    'Scanning rows and boxes carries you through.',
    0.46,
  ),
  hard('hard', 'Hard', 'Pencil marks start earning their keep.', 0.38),
  expert('expert', 'Expert', 'Pairs, triples and a lot of patience.', 0.31),
  evil('evil', 'Evil', 'Chains and long deductions. Bring notes.', 0.25);

  const Difficulty(this.key, this.label, this.description, this.keep);

  /// The design's key, e.g. `medium`.
  final String key;

  /// The design's label, e.g. `Medium`.
  final String label;

  /// The design's one-line description.
  final String description;

  /// The design's share of cells kept as givens.
  final double keep;

  /// Looks a band up by its key.
  static Difficulty byKey(String key) => values.firstWhere(
    (d) => d.key == key,
    orElse: () => throw ArgumentError.value(key, 'key', 'no such difficulty'),
  );
}

/// The bands [shape] offers, easiest first.
///
/// The design's statistics breakdown shows 4×4 Easy–Hard and 6×6
/// Easy–Expert. A band is only offered where the grader can prove it, and
/// three of those pairs it cannot: every unique 4×4 board with at least the
/// design's floor of givens falls to naked singles, and no 6×6 board in
/// 20 000 minimal carves needed a triple or an X-wing. So 4×4 is Easy only
/// and 6×6 stops at Hard — the owner's "unsupported pairs are unavailable"
/// rule, applied to what the measurements found. The evidence is in
/// `test/engine/difficulty_test.dart` and the decision log.
List<Difficulty> supportedDifficulties(GridShape shape) => switch (shape.n) {
  4 => const [Difficulty.easy],
  6 => const [Difficulty.easy, Difficulty.medium, Difficulty.hard],
  _ => Difficulty.values,
};

/// The design's givens target, `max(n + n ~/ 2, round(n² × keep))`.
///
/// Defined for every pair, supported or not, so a greyed setup card can
/// still show its count.
int targetGivens(GridShape shape, Difficulty difficulty) {
  final floor = shape.n + shape.n ~/ 2;
  final ratio = (shape.cellCount * difficulty.keep).round();
  return ratio > floor ? ratio : floor;
}

/// A size and difficulty the design never offers.
final class UnsupportedDifficulty implements Exception {
  /// Creates the exception.
  const UnsupportedDifficulty(this.shape, this.difficulty, [this.seed]);

  /// The shape asked for.
  final GridShape shape;

  /// The band asked for.
  final Difficulty difficulty;

  /// The seed asked for, if any.
  final int? seed;

  @override
  String toString() =>
      'UnsupportedDifficulty: ${difficulty.label} is not offered on '
      '${shape.label}';
}

/// Generation gave up after every attempt it was allowed.
final class GenerationFailed implements Exception {
  /// Creates the exception.
  const GenerationFailed(this.shape, this.difficulty, this.seed, this.attempts);

  /// The shape asked for.
  final GridShape shape;

  /// The band asked for.
  final Difficulty difficulty;

  /// The seed asked for.
  final int seed;

  /// How many attempts were made.
  final int attempts;

  @override
  String toString() =>
      'GenerationFailed: no ${difficulty.label} ${shape.label} board from '
      'seed $seed in $attempts attempts';

  @override
  bool operator ==(Object other) =>
      other is GenerationFailed &&
      other.shape == shape &&
      other.difficulty == difficulty &&
      other.seed == seed &&
      other.attempts == attempts;

  @override
  int get hashCode => Object.hash(shape, difficulty, seed, attempts);
}
