import 'package:flutter_test/flutter_test.dart';
import 'package:honest_sudoku/engine/engine.dart';
import 'package:honest_sudoku/game/game.dart';

import 'fixtures.dart';

const c9 = GridShape.classic;
const c16 = GridShape.monster;
const easy = Difficulty.easy;
const medium = Difficulty.medium;
const hard = Difficulty.hard;

void main() {
  test('abandoning zeroes the streak and does not count a second start', () {
    final b = StatsBook.empty
        .recordStart(c9, medium)
        .recordWin(c9, medium, 100)
        .recordStart(c9, medium)
        .recordAbandon(c9, medium);
    expect(b.streak(medium), 0);
    expect(b.shapeStats(medium, c9).started, 2);
  });

  test('a win after a loss starts the streak at 1', () {
    final b = StatsBook.empty
        .recordStart(c9, medium)
        .recordLoss(c9, medium)
        .recordStart(c9, medium)
        .recordWin(c9, medium, 90);
    expect(b.streak(medium), 1);
  });

  test('a loss at Hard does not touch the Medium streak', () {
    final b = StatsBook.empty
        .recordStart(c9, medium)
        .recordWin(c9, medium, 90)
        .recordStart(c9, hard)
        .recordLoss(c9, hard);
    expect(b.streak(medium), 1);
    expect(b.streak(hard), 0);
  });

  test('best time never increases; average uses solved puzzles only', () {
    var b = StatsBook.empty;
    for (final t in [200, 100, 300]) {
      b = b.recordStart(c9, easy).recordWin(c9, easy, t);
    }
    b = b.recordStart(c9, easy).recordLoss(c9, easy);
    final d = b.forDifficulty(easy);
    expect(d.bestSeconds, 100);
    expect(d.averageSeconds, 200);
    expect([d.started, d.solved, d.solveRatePct], [4, 3, 75]);
  });

  test('solve rate with nothing started is 0, not an error', () {
    final d = StatsBook.empty.forDifficulty(Difficulty.evil);
    expect(d.solveRatePct, 0);
    expect(d.isEmpty, isTrue);
    expect([d.bestText, d.averageText], ['—', '—']);
  });

  test('the design sample reads as the design cards do', () {
    final d = sampleStatsBook.forDifficulty(easy);
    expect([d.solved, d.started, d.solveRatePct], [64, 66, 97]);
    expect(
      [d.bestText, d.averageText, d.timePlayedText, d.streak],
      ['2:14', '4:38', '5h 06m', 12],
    );
  });

  test('time played is <h>h <mm>m, rounded down, hours unpadded', () {
    final b = StatsBook.empty
        .recordStart(c9, easy)
        .recordTime(c9, easy, 42 * 60 + 59);
    expect(b.forDifficulty(easy).timePlayedText, '0h 42m');
  });

  test('the breakdown omits sizes with nothing started', () {
    final b = StatsBook.empty
        .recordStart(c9, medium)
        .recordStart(c9, medium)
        .recordWin(c9, medium, 60)
        .recordStart(c16, medium);
    expect(b.breakdown(medium), [
      const BreakdownRow(c9, '1 / 2 · 50%', 50),
      const BreakdownRow(c16, '0 / 1 · 0%', 0),
    ]);
    expect(b.breakdown(easy), isEmpty);
  });

  test('refusals and no-ops', () {
    expect(
      () => StatsBook.empty.recordStart(GridShape.mini, hard),
      throwsArgumentError,
      reason: 'an unsupported pair',
    );
    expect(() => StatsBook.empty.recordWin(c9, easy, 10), throwsStateError);
    expect(
      () => StatsBook.empty.recordStart(c9, easy).recordTime(c9, easy, -1),
      throwsArgumentError,
    );
    const b = StatsBook.empty;
    expect(identical(b.recordLoss(c9, easy), b), isTrue);
    expect(identical(b.recordTime(c9, easy, 10), b), isTrue);
    expect(identical(b.reset(), StatsBook.empty), isTrue);
    expect(sampleStatsBook.reset(), StatsBook.empty);
  });

  test('value equality; zero entries are normalised away', () {
    expect(
      StatsBook(shapes: {(easy, c9): ShapeStats()}, streaks: {easy: 0}),
      StatsBook.empty,
    );
    expect(
      StatsBook.empty.recordStart(c9, easy),
      StatsBook.empty.recordStart(c9, easy),
    );
    expect(() => ShapeStats(started: 1, solved: 2), throwsArgumentError);
  });

  test('RealStatsSource reads the streak as recorded', () {
    var book = sampleStatsBook;
    final source = RealStatsSource(() => book);
    expect(source.currentStreak(shape: c9, difficulty: easy), 12);
    book = book.recordStart(c9, easy).recordWin(c9, easy, 60);
    expect(source.currentStreak(shape: c9, difficulty: easy), 13);
    expect(source.currentStreak(shape: GridShape.mini, difficulty: hard), 0);
  });
}
