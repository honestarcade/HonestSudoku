// Statistics as the design's statistics screen defines them: per difficulty
// and grid size, puzzles started and solved, best and average solve time,
// time played, and per difficulty the current streak. Owner's call
// (2026-09-18): a loss or an abandoned puzzle ends the streak.

import 'package:honest_sudoku/engine/engine.dart';

import 'format.dart';

/// One (difficulty, size) pair's numbers.
final class ShapeStats {
  /// Creates the numbers; validates them.
  ShapeStats({
    this.started = 0,
    this.solved = 0,
    this.bestSeconds,
    this.solvedSecondsTotal = 0,
    this.timePlayedSeconds = 0,
  }) {
    if (started < 0 ||
        solved < 0 ||
        solvedSecondsTotal < 0 ||
        timePlayedSeconds < 0 ||
        (bestSeconds ?? 0) < 0) {
      throw ArgumentError('statistics cannot be negative');
    }
    if (solved > started) {
      throw ArgumentError.value(solved, 'solved', 'more than started');
    }
  }

  /// Puzzles generated.
  final int started;

  /// Puzzles won.
  final int solved;

  /// Fastest win, if any.
  final int? bestSeconds;

  /// All winning times added up, for the average.
  final int solvedSecondsTotal;

  /// All played time, won or not.
  final int timePlayedSeconds;

  /// True when every number is zero.
  bool get isZero =>
      started == 0 &&
      solved == 0 &&
      bestSeconds == null &&
      solvedSecondsTotal == 0 &&
      timePlayedSeconds == 0;

  ShapeStats _copy({
    int? started,
    int? solved,
    int? bestSeconds,
    int? solvedSecondsTotal,
    int? timePlayedSeconds,
  }) => ShapeStats(
    started: started ?? this.started,
    solved: solved ?? this.solved,
    bestSeconds: bestSeconds ?? this.bestSeconds,
    solvedSecondsTotal: solvedSecondsTotal ?? this.solvedSecondsTotal,
    timePlayedSeconds: timePlayedSeconds ?? this.timePlayedSeconds,
  );

  @override
  bool operator ==(Object other) =>
      other is ShapeStats &&
      other.started == started &&
      other.solved == solved &&
      other.bestSeconds == bestSeconds &&
      other.solvedSecondsTotal == solvedSecondsTotal &&
      other.timePlayedSeconds == timePlayedSeconds;

  @override
  int get hashCode => Object.hash(
    started,
    solved,
    bestSeconds,
    solvedSecondsTotal,
    timePlayedSeconds,
  );

  @override
  String toString() => 'ShapeStats($solved/$started)';
}

/// A difficulty's numbers as the statistics cards show them.
final class DifficultyStats {
  /// Creates the numbers.
  const DifficultyStats({
    required this.started,
    required this.solved,
    required this.bestSeconds,
    required this.averageSeconds,
    required this.streak,
    required this.timePlayedSeconds,
  });

  /// Puzzles started.
  final int started;

  /// Puzzles solved.
  final int solved;

  /// Fastest win, or null with no wins.
  final int? bestSeconds;

  /// Average win, rounded, or null with no wins.
  final int? averageSeconds;

  /// Wins in a row.
  final int streak;

  /// Time played.
  final int timePlayedSeconds;

  /// `round(solved / started × 100)`, 0 with nothing started.
  int get solveRatePct => started == 0 ? 0 : (solved / started * 100).round();

  /// Nothing started at this difficulty.
  bool get isEmpty => started == 0;

  /// `m:ss`, or `—`.
  String get bestText => bestSeconds == null ? '—' : fmt(bestSeconds!);

  /// `m:ss`, or `—`.
  String get averageText => averageSeconds == null ? '—' : fmt(averageSeconds!);

  /// `<h>h <mm>m`, rounded down: the design's `5h 06m`.
  String get timePlayedText {
    final minutes = timePlayedSeconds ~/ 60;
    return '${minutes ~/ 60}h ${(minutes % 60).toString().padLeft(2, '0')}m';
  }

  @override
  bool operator ==(Object other) =>
      other is DifficultyStats &&
      other.started == started &&
      other.solved == solved &&
      other.bestSeconds == bestSeconds &&
      other.averageSeconds == averageSeconds &&
      other.streak == streak &&
      other.timePlayedSeconds == timePlayedSeconds;

  @override
  int get hashCode => Object.hash(
    started,
    solved,
    bestSeconds,
    averageSeconds,
    streak,
    timePlayedSeconds,
  );
}

/// One row of the statistics breakdown.
final class BreakdownRow {
  /// Creates a row.
  const BreakdownRow(this.shape, this.text, this.pct);

  /// The size.
  final GridShape shape;

  /// `<solved> / <started> · <pct>%`.
  final String text;

  /// The bar's fill.
  final int pct;

  @override
  bool operator ==(Object other) =>
      other is BreakdownRow &&
      other.shape == shape &&
      other.text == text &&
      other.pct == pct;

  @override
  int get hashCode => Object.hash(shape, text, pct);

  @override
  String toString() => 'BreakdownRow(${shape.label}: $text)';
}

/// Everything recorded, as an immutable value.
final class StatsBook {
  /// A book from its parts. All-zero entries and zero streaks are dropped.
  StatsBook({
    Map<(Difficulty, GridShape), ShapeStats> shapes = const {},
    Map<Difficulty, int> streaks = const {},
  }) : _shapes = Map.unmodifiable({
         for (final e in shapes.entries)
           if (!e.value.isZero) e.key: e.value,
       }),
       _streaks = Map.unmodifiable({
         for (final e in streaks.entries)
           if (e.value != 0) e.key: e.value,
       }) {
    if (_streaks.values.any((s) => s < 0)) {
      throw ArgumentError('a streak cannot be negative');
    }
  }

  const StatsBook._empty() : _shapes = const {}, _streaks = const {};

  /// Nothing recorded.
  static const StatsBook empty = StatsBook._empty();

  final Map<(Difficulty, GridShape), ShapeStats> _shapes;
  final Map<Difficulty, int> _streaks;

  /// Every recorded pair, for the codec.
  Iterable<MapEntry<(Difficulty, GridShape), ShapeStats>> get entries =>
      _shapes.entries;

  /// The numbers for one pair (zeros when nothing is recorded).
  ShapeStats shapeStats(Difficulty d, GridShape shape) =>
      _shapes[(d, shape)] ?? ShapeStats();

  /// The streak at [d].
  int streak(Difficulty d) => _streaks[d] ?? 0;

  /// Every non-zero streak, for the codec.
  Map<Difficulty, int> get streaks => _streaks;

  StatsBook _with(
    Difficulty d,
    GridShape shape,
    ShapeStats stats, {
    int? streak,
  }) => StatsBook(
    shapes: {..._shapes, (d, shape): stats},
    streaks: {..._streaks, d: ?streak},
  );

  static void _supported(GridShape shape, Difficulty d) {
    if (!supportedDifficulties(shape).contains(d)) {
      throw ArgumentError('${d.label} is not offered on ${shape.label}');
    }
  }

  static void _seconds(int seconds) {
    if (seconds < 0) {
      throw ArgumentError.value(seconds, 'seconds', 'cannot be negative');
    }
  }

  /// A board was generated.
  StatsBook recordStart(GridShape shape, Difficulty d) {
    _supported(shape, d);
    final s = shapeStats(d, shape);
    return _with(d, shape, s._copy(started: s.started + 1));
  }

  /// A puzzle was won in [seconds].
  StatsBook recordWin(GridShape shape, Difficulty d, int seconds) {
    _supported(shape, d);
    _seconds(seconds);
    final s = shapeStats(d, shape);
    if (s.solved >= s.started) {
      throw StateError('a win needs a start: ${s.solved}/${s.started}');
    }
    final best = s.bestSeconds;
    return _with(
      d,
      shape,
      s._copy(
        solved: s.solved + 1,
        bestSeconds: best == null || seconds < best ? seconds : best,
        solvedSecondsTotal: s.solvedSecondsTotal + seconds,
      ),
      streak: streak(d) + 1,
    );
  }

  /// A puzzle was lost: the streak at [d] ends.
  StatsBook recordLoss(GridShape shape, Difficulty d) => _endStreak(shape, d);

  /// A puzzle was left unfinished for another: the streak at [d] ends.
  StatsBook recordAbandon(GridShape shape, Difficulty d) =>
      _endStreak(shape, d);

  StatsBook _endStreak(GridShape shape, Difficulty d) {
    _supported(shape, d);
    if (shapeStats(d, shape).started == 0 || streak(d) == 0) return this;
    return StatsBook(shapes: _shapes, streaks: {..._streaks, d: 0});
  }

  /// [seconds] of play at (shape, d).
  StatsBook recordTime(GridShape shape, Difficulty d, int seconds) {
    _supported(shape, d);
    _seconds(seconds);
    final s = shapeStats(d, shape);
    if (s.started == 0 || seconds == 0) return this;
    return _with(
      d,
      shape,
      s._copy(timePlayedSeconds: s.timePlayedSeconds + seconds),
    );
  }

  /// Everything forgotten.
  StatsBook reset() => empty;

  /// A difficulty's totals across sizes.
  DifficultyStats forDifficulty(Difficulty d) {
    var started = 0;
    var solved = 0;
    int? best;
    var total = 0;
    var time = 0;
    for (final shape in GridShape.all) {
      final s = shapeStats(d, shape);
      started += s.started;
      solved += s.solved;
      total += s.solvedSecondsTotal;
      time += s.timePlayedSeconds;
      final b = s.bestSeconds;
      if (b != null && (best == null || b < best)) best = b;
    }
    return DifficultyStats(
      started: started,
      solved: solved,
      bestSeconds: best,
      averageSeconds: solved == 0 ? null : (total / solved).round(),
      streak: streak(d),
      timePlayedSeconds: time,
    );
  }

  /// The breakdown rows at [d], one per size with anything started.
  List<BreakdownRow> breakdown(Difficulty d) => [
    for (final shape in GridShape.all)
      if (shapeStats(d, shape).started > 0) _row(shape, shapeStats(d, shape)),
  ];

  static BreakdownRow _row(GridShape shape, ShapeStats s) {
    final pct = (s.solved / s.started * 100).round();
    return BreakdownRow(shape, '${s.solved} / ${s.started} · $pct%', pct);
  }

  @override
  bool operator ==(Object other) =>
      other is StatsBook &&
      mapEquals(other._shapes, _shapes) &&
      mapEquals(other._streaks, _streaks);

  @override
  int get hashCode => Object.hash(
    Object.hashAllUnordered(
      _shapes.entries.map((e) => Object.hash(e.key, e.value)),
    ),
    Object.hashAllUnordered(
      _streaks.entries.map((e) => Object.hash(e.key, e.value)),
    ),
  );

  @override
  String toString() => 'StatsBook(${_shapes.length} pairs)';
}
