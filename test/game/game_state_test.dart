import 'package:flutter_test/flutter_test.dart';
import 'package:honest_sudoku/engine/engine.dart';
import 'package:honest_sudoku/game/game.dart';

import 'fixtures.dart';

/// The first empty cell of [p].
int firstEmpty(Puzzle p) => p.givens.indexOf(false);

GameState at(Puzzle p, [GameSettings s = const GameSettings()]) =>
    GameState.start(p, s).select(firstEmpty(p));

void main() {
  for (final p in [mini, classic]) {
    group(p.shape.label, () {
      final cell = firstEmpty(p);
      final right = p.solution[cell];
      final wrong = wrongValue(p, cell);

      test('start fills the givens and nothing else', () {
        final s = GameState.start(p);
        expect(s.values, p.startingValues());
        expect(s.filledCount, p.givenCount);
        expect(s.selected, isNull);
        expect(s.notes.every((n) => n.isEmpty), isTrue);
      });

      test('place sets the value, clears its notes and the notice, counts a '
          'move', () {
        var s = at(p, const GameSettings(announce: AnnounceMode.now));
        s = s.place(wrong); // leaves a MISTAKE notice
        expect(s.notice, isNotNull);
        s = s.toggleNoteMode().place(right == 1 ? 2 : 1).toggleNoteMode();
        s = s.place(right);
        expect(s.values[cell], right);
        expect(s.notes[cell], isEmpty);
        expect(s.notice, isNull);
        expect(s.moves, 2);
      });

      test('a given cannot be changed', () {
        final s = GameState.start(p).select(0);
        expect(s.isGiven(0), isTrue);
        expect(identical(s.place(wrongValue(p, 0)), s), isTrue);
      });

      test('the same value again clears the cell without counting a move', () {
        final placed = at(p).place(right);
        final cleared = placed.place(right);
        expect(cleared.values[cell], 0);
        expect(cleared.moves, placed.moves);
      });

      test('nothing selected, won or lost: place is a no-op', () {
        final none = GameState.start(p);
        expect(identical(none.place(1), none), isTrue);
        final lost = at(p).copyWith(lost: true);
        expect(identical(lost.place(right), lost), isTrue);
        final won = at(p).copyWith(won: true);
        expect(identical(won.place(right), won), isTrue);
      });

      test('note mode toggles a sorted pencil mark on an empty cell', () {
        var s = at(p).toggleNoteMode();
        s = s.place(3).place(1);
        expect(s.notes[cell], [1, 3]);
        expect(s.values[cell], 0);
        s = s.place(3);
        expect(s.notes[cell], [1]);
      });

      test('note mode on a filled cell does nothing', () {
        final filled = at(p).place(right).toggleNoteMode();
        expect(identical(filled.place(1), filled), isTrue);
      });

      test('with auto-notes on, note mode places values', () {
        final s = at(p, const GameSettings(autoNotes: true)).toggleNoteMode();
        expect(s.noteMode, isTrue);
        expect(s.effectiveNoteMode, isFalse);
        expect(s.place(right).values[cell], right);
      });

      test('a wrong entry counts a mistake and announces it now', () {
        final s = at(p).place(wrong);
        expect(s.mistakes, 1);
        expect(
          s.notice,
          const Notice(
            BannerKind.error,
            'MISTAKE',
            'That number cannot go there. Strike 1 of 3.',
          ),
        );
      });

      test('a correct entry never counts a mistake', () {
        expect(at(p).place(right).mistakes, 0);
      });

      test('unlimited says no limit is set', () {
        final s = at(
          p,
          const GameSettings(strikeMode: StrikeMode.unlimited),
        ).place(wrong);
        expect(
          s.notice!.body,
          'That number cannot go there. 1 so far — no limit set.',
        );
      });

      test('announce at the end counts the mistake but shows no notice', () {
        final s = at(
          p,
          const GameSettings(announce: AnnounceMode.atEnd),
        ).place(wrong);
        expect(s.mistakes, 1);
        expect(s.notice, isNull);
      });

      test('Zen never counts or announces', () {
        final s = at(
          p,
          const GameSettings(strikeMode: StrikeMode.zen),
        ).place(wrong);
        expect(s.mistakes, 0);
        expect(s.notice, isNull);
      });

      test(
        'the third wrong entry loses at three strikes, the second does not',
        () {
          final empties = [
            for (var i = 0; i < p.shape.cellCount; i++)
              if (!p.givens[i]) i,
          ];
          var s = GameState.start(p);
          for (var k = 0; k < 3; k++) {
            s = s.select(empties[k]).place(wrongValue(p, empties[k]));
            expect(s.lost, k == 2, reason: 'after wrong entry ${k + 1}');
          }
        },
      );

      test('five strikes loses on the fifth; unlimited and Zen never lose', () {
        final empties = [
          for (var i = 0; i < p.shape.cellCount; i++)
            if (!p.givens[i]) i,
        ];
        for (final mode in StrikeMode.values) {
          var s = GameState.start(p, GameSettings(strikeMode: mode));
          for (var k = 0; k < 5; k++) {
            s = s.select(empties[k]).place(wrongValue(p, empties[k]));
          }
          expect(
            s.lost,
            mode == StrikeMode.three || mode == StrikeMode.five,
            reason: mode.name,
          );
        }
      });

      test('auto-clear removes the value from every peer, and only peers', () {
        final peers = unitsOf(p.shape, cell);
        final peer = peers.firstWhere((i) => !p.givens[i]);
        final far = [
          for (var i = 0; i < p.shape.cellCount; i++)
            if (!p.givens[i] && i != cell && !peers.contains(i)) i,
        ].first;
        GameState staged(GameSettings s) {
          final base = GameState.start(p, s);
          final notes = [...base.notes];
          notes[peer] = [right];
          notes[far] = [right];
          return base.copyWith(notes: notes).select(cell);
        }

        final on = staged(const GameSettings()).place(right);
        expect(on.notes[peer], isEmpty);
        expect(on.notes[far], [right], reason: 'not a peer');
        final off = staged(const GameSettings(autoClear: false)).place(right);
        expect(off.notes[peer], [right]);
      });

      test('auto-candidates fill empty cells at start and after a change', () {
        final s = GameState.start(p, const GameSettings(autoNotes: true));
        for (var i = 0; i < s.values.length; i++) {
          expect(
            s.notes[i],
            s.values[i] == 0 ? candidates(p.shape, s.values, i) : isEmpty,
          );
        }
        final after = s.select(cell).place(right);
        final peer = unitsOf(
          p.shape,
          cell,
        ).firstWhere((i) => after.values[i] == 0);
        expect(after.notes[peer], candidates(p.shape, after.values, peer));
        expect(after.notes[peer], isNot(contains(right)));
      });

      test('turning auto-notes on mid-game fills them; off keeps them', () {
        final plain = at(p);
        final on = plain.withSettings(const GameSettings(autoNotes: true));
        expect(on.notes[cell], candidates(p.shape, on.values, cell));
        final off = on.withSettings(const GameSettings());
        expect(off.notes, on.notes);
      });

      test('a full, correct grid is won without Check', () {
        var s = GameState.start(p);
        for (var i = 0; i < p.shape.cellCount; i++) {
          if (!p.givens[i]) s = s.select(i).place(p.solution[i]);
        }
        expect(s.won, isTrue);
        expect(s.notice, isNull);
      });

      test('a full grid with one wrong cell is not won: revealed and told, '
          'then fixing it wins', () {
        final empties = [
          for (var i = 0; i < p.shape.cellCount; i++)
            if (!p.givens[i]) i,
        ];
        var s = GameState.start(
          p,
          const GameSettings(strikeMode: StrikeMode.unlimited),
        );
        for (final i in empties.skip(1)) {
          s = s.select(i).place(p.solution[i]);
        }
        s = s.select(empties.first).place(wrongValue(p, empties.first));
        expect(s.won, isFalse);
        expect(s.revealed, isTrue);
        expect(
          s.notice,
          const Notice(
            BannerKind.error,
            'GRID FULL',
            'Some numbers are wrong — the ones in red. Fix them and the '
                'puzzle finishes itself.',
          ),
        );
        s = s.place(p.solution[empties.first]);
        expect(s.won, isTrue);
      });

      test('in Zen the grid-full message points at nothing red', () {
        final empties = [
          for (var i = 0; i < p.shape.cellCount; i++)
            if (!p.givens[i]) i,
        ];
        var s = GameState.start(
          p,
          const GameSettings(strikeMode: StrikeMode.zen),
        );
        for (final i in empties.skip(1)) {
          s = s.select(i).place(p.solution[i]);
        }
        s = s.select(empties.first).place(wrongValue(p, empties.first));
        expect(
          s.notice!.body,
          'Some numbers are wrong. Fix them and the puzzle finishes itself.',
        );
      });

      test('wrong tint: never in Zen; at once when announced now; after a '
          'reveal when announced at the end', () {
        expect(at(p).showWrong, isTrue);
        expect(
          at(p, const GameSettings(strikeMode: StrikeMode.zen)).showWrong,
          isFalse,
        );
        final atEnd = at(p, const GameSettings(announce: AnnounceMode.atEnd));
        expect(atEnd.showWrong, isFalse);
        expect(atEnd.copyWith(revealed: true).showWrong, isTrue);
        final s = at(p).place(wrong);
        expect([s.isWrong(cell), s.isWrong(0)], [true, false]);
      });

      test('conflicts: peers holding the selected value, only when on', () {
        final s = at(p).place(wrong);
        final expected = {
          for (final i in unitsOf(p.shape, cell))
            if (s.values[i] == wrong) i,
        };
        expect(
          expected,
          isNotEmpty,
          reason: 'fixture: the wrong value clashes',
        );
        expect(s.conflictCells, expected);
        expect(
          s.withSettings(const GameSettings(conflicts: false)).conflictCells,
          isEmpty,
        );
        expect(GameState.start(p).conflictCells, isEmpty);
      });

      test('select toggles and leaves the notice; helpers', () {
        final s = at(p).place(wrong);
        expect(s.select(cell).selected, isNull);
        expect(s.select(cell).notice, s.notice);
        expect(() => s.select(p.shape.cellCount), throwsRangeError);
        expect(s.peersOfSelected, unitsOf(p.shape, cell).toSet());
        expect(s.sameValueCells, {
          for (var i = 0; i < s.values.length; i++)
            if (i != cell && s.values[i] == wrong) i,
        });
        expect(s.countOf(wrong), s.values.where((v) => v == wrong).length);
        expect(s.boardTitle, '${p.shape.label} · Medium');
        expect(s.isFull, isFalse);
      });

      test('toggleNoteMode flips even with auto-notes on', () {
        final s = at(p, const GameSettings(autoNotes: true));
        expect(s.toggleNoteMode().noteMode, isTrue);
        expect(s.toggleNoteMode().effectiveNoteMode, isFalse);
      });
    });
  }

  test('an ungraded puzzle, a bad value or a bad length is refused', () {
    final ungraded = const Generator().carveToUniqueness(GridShape.mini, 1);
    expect(() => GameState.start(ungraded), throwsArgumentError);
    expect(() => at(mini).place(5), throwsArgumentError);
    expect(
      () => GameState(
        puzzle: mini,
        settings: const GameSettings(),
        values: List.filled(15, 0),
        notes: List.filled(16, const []),
      ),
      throwsArgumentError,
    );
  });

  test('value equality over every field', () {
    expect(at(mini), at(mini));
    expect(at(mini).hashCode, at(mini).hashCode);
    expect(at(mini).place(1), isNot(at(mini)));
  });
}
