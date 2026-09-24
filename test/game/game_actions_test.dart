import 'package:flutter_test/flutter_test.dart';
import 'package:honest_sudoku/engine/engine.dart';
import 'package:honest_sudoku/game/game.dart';

import 'fixtures.dart';
import 'sequence_seed_source.dart';

List<int> empties(Puzzle p) => [
  for (var i = 0; i < p.shape.cellCount; i++)
    if (!p.givens[i]) i,
];

void main() {
  final cell = empties(classic).first;
  final wrong = wrongValue(classic, cell);

  group('check', () {
    test('a wrong entry: error notice, revealed', () {
      final s = GameState.start(
        classic,
        const GameSettings(announce: AnnounceMode.atEnd),
      ).select(cell).place(wrong).check();
      expect(s.revealed, isTrue);
      expect(
        s.notice,
        const Notice(
          BannerKind.error,
          'CHECK',
          '1 number is wrong — marked in red. They stay marked until you '
              'clear them.',
        ),
      );
      expect(s.showWrong, isTrue);
    });

    test('nothing wrong: ok notice with the cells to go', () {
      final s = GameState.start(classic).check();
      expect(
        s.notice,
        Notice(
          BannerKind.ok,
          'CHECK',
          'Everything on the board so far is correct. '
              '${empties(classic).length} cells to go.',
        ),
      );
    });

    test('a no-op when over or paused', () {
      final won = GameState.start(classic).copyWith(won: true);
      expect(identical(won.check(), won), isTrue);
      final lost = GameState.start(classic).copyWith(lost: true);
      expect(identical(lost.check(), lost), isTrue);
      final paused = GameState.start(classic).pause();
      expect(identical(paused.check(), paused), isTrue);
    });
  });

  group('hint', () {
    // Every other cell given: each empty cell is a naked single.
    test('selects the engine hint cell, marks it hinted, explains it', () {
      final start = GameState.start(classic).select(80);
      final expected = nextHint(classic.shape, start.values, classic.solution)!;
      final s = start.hint();
      expect(s.selected, expected.cellIndex);
      expect(s.selected, isNot(80), reason: 'the old selection is gone');
      expect(s.hintedCell, expected.cellIndex);
      expect(s.notice, Notice(BannerKind.hint, expected.tag, expected.body));
      expect(s.select(0).hintedCell, isNull);
    });

    test('with explanations off it only names the cell', () {
      final s = GameState.start(
        classic,
        const GameSettings(hintWhy: false),
      ).hint();
      expect(s.notice!.body, startsWith('Try R'));
    });

    test('note mode is untouched', () {
      final s = GameState.start(classic).toggleNoteMode().hint();
      expect(s.noteMode, isTrue);
    });

    test('a no-op when over, paused or full', () {
      final won = GameState.start(classic).copyWith(won: true);
      expect(identical(won.hint(), won), isTrue);
      final paused = GameState.start(classic).pause();
      expect(identical(paused.hint(), paused), isTrue);
      final full = GameState.start(classic).copyWith(values: classic.solution);
      expect(identical(full.hint(), full), isTrue);
    });
  });

  group('restart', () {
    test('the same board, entries and counters gone, unpaused', () {
      final played = GameState.start(classic)
          .select(cell)
          .place(wrong)
          .tick()
          .toggleNoteMode()
          .check()
          .pause();
      final s = played.restart();
      expect(s.values, classic.startingValues());
      expect(s.puzzle.seed, classic.seed);
      expect([s.mistakes, s.moves, s.elapsedSeconds], [0, 0, 0]);
      expect([s.paused, s.revealed, s.noteMode], [false, false, false]);
      expect([s.notice, s.selected], [null, null]);
      expect(s.history, isEmpty);
      expect(s.settings, played.settings);
    });

    test('re-applies auto-notes', () {
      final s = GameState.start(
        classic,
        const GameSettings(autoNotes: true),
      ).restart();
      expect(s.notes[cell], candidates(classic.shape, s.values, cell));
    });
  });

  group('new deal', () {
    test('same size and band, a fresh seed; unpaused, notice cleared', () {
      final seeds = SequenceSeedSource([4242]);
      final (state, request) = GameState.start(classic)
          .check()
          .pause()
          .newDeal(seeds);
      expect(request.shape, classic.shape);
      expect(request.difficulty, classic.difficulty);
      expect(request.seed, 4242);
      expect(state.paused, isFalse);
      expect(state.notice, isNull);
    });

    test('a seed equal to the current one is redrawn', () {
      final seeds = SequenceSeedSource([classic.seed, classic.seed, 777]);
      final (_, request) = GameState.start(classic).newDeal(seeds);
      expect(request.seed, 777);
      expect(seeds.drawn, 3);
    });

    test('after ten redraws the last draw is kept', () {
      final seeds = SequenceSeedSource([classic.seed]);
      final (_, request) = GameState.start(classic).newDeal(seeds);
      expect(request.seed, classic.seed);
    });

    test('the design seed range', () {
      expect([kSeedMin, kSeedMax], [1000, 900999]);
    });
  });
}
