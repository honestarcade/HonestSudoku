import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:honest_sudoku/engine/engine.dart';
import 'package:honest_sudoku/game/game.dart';
import 'package:honest_sudoku/ui/board/game_controller.dart';

import 'stub_generator.dart';

void main() {
  late StubGenerator gen;
  late GameController c;

  setUp(() {
    gen = StubGenerator();
  });

  GameController make({AppSettings settings = const AppSettings()}) =>
      c = GameController(
        generator: gen.call,
        seeds: CountingSeeds(),
        settings: settings,
      );

  // The controller's clock is a periodic timer, so it must be disposed
  // before the test ends, not in a tear-down.
  void ctlTest(String name, Future<void> Function(WidgetTester) body) =>
      testWidgets(name, (tester) async {
        await body(tester);
        c.dispose();
      });

  ctlTest('startNew shows loading, then a board', (tester) async {
    make().startNew(GridShape.classic, Difficulty.medium);
    expect(c.loading, isNotNull);
    expect(c.state, isNull);
    await tester.pump();
    expect(c.loading, isNull);
    expect(c.state!.shape, GridShape.classic);
    expect(gen.requests.single.seed, 5000);
  });

  ctlTest('the clock counts only while playing and while the board is '
      'showing', (tester) async {
    make().startNew(GridShape.classic, Difficulty.medium);
    await tester.pump();
    c.enterBoard();
    await tester.pump(const Duration(seconds: 3));
    expect(c.state!.elapsedSeconds, 3);
    c.pause();
    await tester.pump(const Duration(seconds: 3));
    expect(c.state!.elapsedSeconds, 3);
    c.resume();
    c.setBoardVisible(false);
    await tester.pump(const Duration(seconds: 3));
    expect(c.state!.elapsedSeconds, 3);
    c.setBoardVisible(true);
    await tester.pump(const Duration(seconds: 1));
    expect(c.state!.elapsedSeconds, 4);
  });

  ctlTest('leaving the app pauses; coming back does not unpause', (
    tester,
  ) async {
    make().startNew(GridShape.classic, Difficulty.medium);
    await tester.pump();
    c.enterBoard();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    expect(c.state!.paused, isTrue);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    expect(c.state!.paused, isTrue);
  });

  ctlTest('a brief inactive does not pause; a lasting one does', (
    tester,
  ) async {
    make().startNew(GridShape.classic, Difficulty.medium);
    await tester.pump();
    c.enterBoard();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump(const Duration(milliseconds: 100));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump(const Duration(milliseconds: 400));
    expect(c.state!.paused, isFalse);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump(const Duration(milliseconds: 400));
    expect(c.state!.paused, isTrue);
  });

  ctlTest('a finished game is not paused by leaving the app', (tester) async {
    make().startNew(GridShape.classic, Difficulty.medium);
    await tester.pump();
    c.enterBoard();
    final s = c.state!;
    for (var i = 0; i < 81; i++) {
      if (!s.isGiven(i)) {
        c.select(i);
        c.place(s.solution[i]);
      }
    }
    expect(c.state!.won, isTrue);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    expect(c.state!.paused, isFalse);
  });

  ctlTest('a failed new deal keeps the board and offers a retry', (
    tester,
  ) async {
    make().startNew(GridShape.classic, Difficulty.medium);
    await tester.pump();
    c.enterBoard();
    final before = c.state!.puzzle;
    gen.failWith = timeoutFailure;
    c.newDeal();
    await tester.pump();
    expect(c.state!.puzzle, before);
    expect(c.generationFailure!.tag, 'GENERATION FAILED');
    expect(
      c.generationFailure!.body,
      "Couldn't build a board in time. Try again.",
    );
    gen.failWith = null;
    c.retry();
    await tester.pump();
    expect(c.generationFailure, isNull);
    expect(c.state!.puzzle.seed, gen.requests.last.seed);
    expect(
      gen.requests.last.seed,
      isNot(gen.requests[1].seed),
      reason: 'a retry draws a fresh seed',
    );
  });

  ctlTest('cancelling a generation says so; disposing cancels the stream', (
    tester,
  ) async {
    gen.hang = true;
    make().startNew(GridShape.classic, Difficulty.medium);
    await tester.pump();
    c.enterBoard();
    c.cancelGeneration();
    expect(gen.cancelled, isTrue);
    expect(c.generationFailure!.tag, 'GENERATION CANCELLED');

    final gen2 = StubGenerator()..hang = true;
    final c2 = GameController(generator: gen2.call, seeds: CountingSeeds());
    c2.startNew(GridShape.classic, Difficulty.medium);
    await tester.pump();
    c2.dispose();
    await tester.pump();
    expect(gen2.cancelled, isTrue);
  });

  ctlTest('updateSettings applies to the game on screen', (tester) async {
    make().startNew(GridShape.classic, Difficulty.medium);
    await tester.pump();
    c.enterBoard();
    c.updateSettings(const AppSettings(game: GameSettings(autoNotes: true)));
    expect(c.state!.settings.autoNotes, isTrue);
    expect(c.state!.notes.any((n) => n.isNotEmpty), isTrue);
  });
}
