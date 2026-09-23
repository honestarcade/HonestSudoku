import 'package:flutter_test/flutter_test.dart';
import 'package:honest_sudoku/engine/engine.dart';
import 'package:honest_sudoku/game/game.dart';

import 'fixtures.dart';

List<int> empties(Puzzle p) => [
  for (var i = 0; i < p.shape.cellCount; i++)
    if (!p.givens[i]) i,
];

void main() {
  final cell = empties(classic).first;
  final right = classic.solution[cell];
  final wrong = wrongValue(classic, cell);
  GameState fresh([GameSettings s = const GameSettings()]) =>
      GameState.start(classic, s).select(cell);

  group('erase', () {
    test('clears value and marks, clears the notice, snapshots, no move', () {
      final placed = fresh().place(wrong);
      final erased = placed.erase();
      expect(erased.values[cell], 0);
      expect(erased.notes[cell], isEmpty);
      expect(erased.notice, isNull);
      expect(erased.moves, placed.moves);
      expect(erased.history.length, placed.history.length + 1);
    });

    test('recomputes auto-notes', () {
      final erased = fresh(const GameSettings(autoNotes: true))
          .place(right)
          .erase();
      expect(
        erased.notes[cell],
        candidates(classic.shape, erased.values, cell),
      );
    });

    test('a no-op on a given, with nothing selected, or when over', () {
      final given = GameState.start(classic).select(0);
      expect(identical(given.erase(), given), isTrue);
      final none = GameState.start(classic);
      expect(identical(none.erase(), none), isTrue);
      final over = fresh().place(right).copyWith(won: true);
      expect(identical(over.erase(), over), isTrue);
    });
  });

  group('undo and redo', () {
    test('undo after a wrong entry takes the mistake back and clears lost', () {
      var s = GameState.start(classic);
      final e = empties(classic);
      for (var k = 0; k < 3; k++) {
        s = s.select(e[k]).place(wrongValue(classic, e[k]));
      }
      expect([s.mistakes, s.lost], [3, true]);
      final back = s.undo();
      expect([back.mistakes, back.lost], [2, false]);
      expect(back.notice, isNull);
      expect(back.values[e[2]], 0);
      final again = back.redo();
      expect(
        [again.mistakes, again.lost],
        [3, true],
        reason: 'redoing the fatal entry loses again',
      );
      expect(again.values[e[2]], wrongValue(classic, e[2]));
    });

    test('redo re-derives won and revealed', () {
      var s = GameState.start(classic);
      for (final i in empties(classic)) {
        s = s.select(i).place(classic.solution[i]);
      }
      expect(s.won, isTrue);
      final back = s.undo();
      expect(back.won, isFalse);
      expect(back.redo().won, isTrue);
    });

    test('a new action after undo empties the redo stack', () {
      final s = fresh().place(wrong).undo();
      expect(s.canRedo, isTrue);
      expect(s.place(right).canRedo, isFalse);
    });

    test('no-ops on empty stacks', () {
      final s = fresh();
      expect(identical(s.undo(), s), isTrue);
      expect(identical(s.redo(), s), isTrue);
      expect([s.canUndo, s.canRedo], [false, false]);
    });

    test('the history keeps 120 steps and drops the oldest', () {
      final c = empties(mini).first;
      var s = GameState.start(mini).select(c).toggleNoteMode();
      for (var k = 0; k < 121; k++) {
        s = s.place(k % 4 + 1);
      }
      expect(s.history.length, kHistoryCap);
      for (var k = 0; k < 120; k++) {
        s = s.undo();
      }
      expect(
        s.notes[c],
        [1],
        reason:
            'the state after the first action: '
            'the one before it was dropped',
      );
      expect(identical(s.undo(), s), isTrue);
    });

    test('the stacks are unmodifiable', () {
      final s = fresh().place(wrong);
      expect(() => s.history.clear(), throwsUnsupportedError);
      expect(() => s.future.clear(), throwsUnsupportedError);
    });
  });

  group('pause', () {
    test('play verbs do nothing while paused; resume restores play', () {
      final paused = fresh().pause();
      expect(paused.paused, isTrue);
      for (final verb in <GameState Function(GameState)>[
        (s) => s.place(right),
        (s) => s.select(0),
        (s) => s.erase(),
        (s) => s.undo(),
        (s) => s.redo(),
        (s) => s.toggleNoteMode(),
      ]) {
        expect(identical(verb(paused), paused), isTrue);
      }
      expect(paused.resume().place(right).values[cell], right);
    });

    test('settings and tick still apply while paused', () {
      final paused = fresh().pause();
      expect(
        paused
            .withSettings(const GameSettings(bigDigits: true))
            .settings
            .bigDigits,
        isTrue,
      );
      expect(identical(paused.tick(), paused), isTrue);
    });

    test('a finished game can be paused', () {
      expect(fresh().copyWith(won: true).pause().paused, isTrue);
    });
  });

  group('timer', () {
    test('ticks only while playing', () {
      expect(fresh().tick().elapsedSeconds, 1);
      expect(fresh().pause().tick().elapsedSeconds, 0);
      expect(fresh().copyWith(won: true).tick().elapsedSeconds, 0);
      expect(fresh().copyWith(lost: true).tick().elapsedSeconds, 0);
    });
  });

  group('hinted cell', () {
    test('cleared by a change of selection or of notice, kept otherwise', () {
      final hinted = fresh().copyWith(hintedCell: cell);
      expect(hinted.hintedCell, cell);
      expect(hinted.tick().hintedCell, cell);
      expect(hinted.select(0).hintedCell, isNull);
      expect(hinted.place(wrong).hintedCell, isNull);
    });
  });
}
