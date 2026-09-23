import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:honest_sudoku/engine/engine.dart';
import 'package:honest_sudoku/game/game.dart';
import 'package:honest_sudoku/store/app_store.dart';

import '../game/fixtures.dart';

// Reads the frozen v1 documents (test/fixtures/store_v1/) through the store,
// from a copy, and asserts what they hold. If a format change breaks this,
// the change needs a migration, not a new fixture.
void main() {
  late Directory dir;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('hs-fixture-');
    for (final name in ['settings.json', 'game.json', 'stats.json']) {
      File('test/fixtures/store_v1/$name').copySync('${dir.path}/$name');
    }
  });
  tearDown(() => dir.deleteSync(recursive: true));

  test('v1 settings', () async {
    final s = (await AppStore(dir).readSettings()).valueOrNull!;
    expect(s.game.autoNotes, isTrue);
    expect(s.game.hlSame, isFalse);
    expect(s.game.bigDigits, isTrue);
    expect(s.game.strikeMode, StrikeMode.zen);
    expect(s.game.announce, AnnounceMode.atEnd);
    expect([s.themeKey, s.sfx, s.haptics], ['paper', false, true]);
    expect(
      s.lastSetup,
      const LastSetup(
        shapeLabel: '16×16',
        difficultyKey: 'expert',
        strikeMode: StrikeMode.unlimited,
        announce: AnnounceMode.atEnd,
      ),
    );
  });

  test('v1 game', () async {
    final g = (await AppStore(dir).readGame()).valueOrNull!;
    expect(g.shape, GridShape.classic);
    expect(g.difficulty, Difficulty.medium);
    expect(g.seed, 1);
    expect(g.solution, classic.solution);
    expect(g.givens, classic.givens);
    expect([g.mistakes, g.moves, g.elapsedSeconds], [1, 2, 3]);
    expect([g.history.length, g.future.length], [4, 1]);
    expect(g.notes[5], [4, 7]);
    expect(g.selected, 5);
    expect([g.strikeMode, g.announce], [StrikeMode.five, AnnounceMode.atEnd]);
    expect(g.values[1], classic.solution[1]);
    expect(g.values[3], wrongValue(classic, 3));
    final state = g.toState(const GameSettings());
    expect(state.paused, isTrue);
  });

  test('v1 statistics', () async {
    final b = (await AppStore(dir).readStats()).valueOrNull!;
    expect(b, sampleStatsBook);
  });
}
