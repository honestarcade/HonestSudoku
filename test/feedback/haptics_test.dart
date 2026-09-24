import 'package:flutter_test/flutter_test.dart';
import 'package:honest_sudoku/engine/engine.dart';
import 'package:honest_sudoku/feedback/game_feedback.dart';
import 'package:honest_sudoku/game/game.dart';
import 'package:honest_sudoku/ui/board/game_controller.dart';

import '../ui/stub_generator.dart';
import 'fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final controllers = <GameController>[];
  tearDown(() {
    for (final c in controllers) {
      c.dispose();
    }
    controllers.clear();
  });

  /// The 9×9 fixture (givens on even cells) with feedback attached.
  Future<(GameController, RecordingPlayer, RecordingHaptics)> playing({
    AnnounceMode announce = AnnounceMode.now,
    bool conflicts = true,
    bool sfx = true,
    bool haptics = true,
  }) async {
    final c = GameController(
      generator: StubGenerator().call,
      seeds: CountingSeeds(),
      settings: AppSettings(
        sfx: sfx,
        haptics: haptics,
        game: GameSettings(conflicts: conflicts),
        lastSetup: LastSetup(announce: announce),
      ),
      log: (_) {},
    );
    controllers.add(c);
    final player = RecordingPlayer();
    final ticks = RecordingHaptics();
    await GameFeedback(player: player, haptics: ticks, log: (_) {}).attach(c);
    c.startNew(GridShape.classic, Difficulty.medium);
    await c.generationDone;
    return (c, player, ticks);
  }

  void enter(GameController c, int cell, int value) {
    if (c.state!.selected != cell) c.select(cell);
    c.place(value);
  }

  /// A wrong value for [cell] that no peer holds, so no visible clash.
  int quietWrong(GameController c, int cell) {
    final s = c.state!;
    final peers = unitsOf(s.shape, cell).map((j) => s.values[j]).toSet();
    return [
      for (var v = 1; v <= 9; v++)
        if (v != s.solution[cell] && !peers.contains(v)) v,
    ].first;
  }

  /// The value a given peer of [cell] holds: placing it clashes.
  int clashing(GameController c, int cell) {
    final s = c.state!;
    return s.values[unitsOf(s.shape, cell).firstWhere((j) => s.isGiven(j))];
  }

  test('a correct placement: one light tick', () async {
    final (c, _, t) = await playing();
    enter(c, 1, c.state!.solution[1]);
    expect(t.ticks, ['light']);
  });

  test(
    'a clash with a peer, conflicts on: medium; conflicts off: light',
    () async {
      var (c, _, t) = await playing(announce: AnnounceMode.atEnd);
      enter(c, 1, clashing(c, 1));
      expect(t.ticks, ['medium']);
      (c, _, t) = await playing(announce: AnnounceMode.atEnd, conflicts: false);
      enter(c, 1, clashing(c, 1));
      expect(t.ticks, ['light'], reason: 'no clash shown, no firm tick');
    },
  );

  test('a wrong entry: medium when announced at once; light at the end '
      'with no visible clash', () async {
    var (c, _, t) = await playing();
    enter(c, 1, quietWrong(c, 1));
    expect(t.ticks, ['medium']);
    (c, _, t) = await playing(announce: AnnounceMode.atEnd);
    enter(c, 1, quietWrong(c, 1));
    expect(t.ticks, ['light']);
  });

  test('overwriting a clashing value with a clean one is light', () async {
    final (c, _, t) = await playing(announce: AnnounceMode.atEnd);
    enter(c, 1, clashing(c, 1));
    enter(c, 1, c.state!.solution[1]);
    expect(t.ticks, ['medium', 'light']);
  });

  test('the win and the last strike: medium', () async {
    var (c, _, t) = await playing();
    final s = c.state!;
    for (var i = 1; i < 81; i += 2) {
      enter(c, i, s.solution[i]);
    }
    expect(c.state!.won, isTrue);
    expect(t.ticks.last, 'medium');
    (c, _, t) = await playing();
    for (final i in [1, 3, 5]) {
      enter(c, i, quietWrong(c, i));
    }
    expect(c.state!.lost, isTrue);
    expect(t.ticks, ['medium', 'medium', 'medium']);
  });

  test('erase, undo, redo and a note toggle never tick', () async {
    final (c, _, t) = await playing();
    enter(c, 1, c.state!.solution[1]);
    t.ticks.clear();
    c
      ..erase()
      ..undo()
      ..redo()
      ..toggleNotes();
    enter(c, 3, 4);
    expect(t.ticks, isEmpty);
  });

  test('the two toggles are independent', () async {
    var (c, p, t) = await playing(sfx: false);
    enter(c, 1, c.state!.solution[1]);
    expect(p.played, isEmpty);
    expect(t.ticks, ['light']);
    (c, p, t) = await playing(haptics: false);
    enter(c, 1, c.state!.solution[1]);
    expect(p.played, [FeedbackEvent.place]);
    expect(t.ticks, isEmpty);
  });
}
