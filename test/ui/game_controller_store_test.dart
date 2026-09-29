import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:honest_sudoku/engine/engine.dart';
import 'package:honest_sudoku/game/game.dart';
import 'package:honest_sudoku/store/app_store.dart';
import 'package:honest_sudoku/ui/board/board_grid.dart';
import 'package:honest_sudoku/ui/board/board_screen.dart';
import 'package:honest_sudoku/ui/board/game_controller.dart';
import 'package:honest_sudoku/ui/theme/board_theme.dart';

import '../game/fixtures.dart';
import 'stub_generator.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late AppStore store;
  late StubGenerator gen;
  final controllers = <GameController>[];

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('hs-ctl-');
    store = await AppStore.open(dir, log: (_) {});
    gen = StubGenerator();
  });
  tearDown(() {
    for (final c in controllers) {
      c.dispose();
    }
    controllers.clear();
    dir.deleteSync(recursive: true);
  });

  GameController make({
    AppStore? from,
    BoardGenerator? generator,
    void Function(String)? log,
  }) {
    final c = GameController(
      generator: generator ?? gen.call,
      seeds: CountingSeeds(),
      store: () async => from ?? store,
      log: log ?? (_) {},
    );
    controllers.add(c);
    return c;
  }

  Future<GameController> started(GridShape shape, Difficulty d) async {
    final c = make();
    await c.load();
    c.startNew(shape, d);
    await c.generationDone;
    c.enterBoard();
    return c;
  }

  void playEmpty(GameController c, {required bool right, int count = 1}) {
    final s = c.state!;
    var k = 0;
    for (var i = 0; i < s.values.length && k < count; i++) {
      if (!s.isGiven(i) && c.state!.values[i] == 0) {
        c.select(i);
        c.place(right ? s.solution[i] : s.solution[i] % s.n + 1);
        k++;
      }
    }
  }

  test('kill and relaunch restores the board, notes, history, time and '
      'mistakes, paused', () async {
    final a = await started(GridShape.classic, Difficulty.medium);
    playEmpty(a, right: false);
    playEmpty(a, right: true);
    final cell = a.state!.values.indexOf(0);
    a.select(cell);
    a.toggleNotes();
    a.place(4);
    a.toggleNotes();
    a.updateSettings(a.settings); // no-op
    await a.flush();
    final before = a.state!;
    a.dispose();
    controllers.remove(a);

    final b = make(from: await AppStore.open(dir));
    await b.load();
    final after = b.state!;
    expect(after.values, before.values);
    expect(after.notes, before.notes);
    expect(after.history, before.history);
    expect(after.mistakes, before.mistakes);
    expect(after.elapsedSeconds, before.elapsedSeconds);
    expect(after.paused, isTrue);
    expect(b.hasUnfinishedGame, isTrue);
    expect(b.summary!.meta, startsWith('9×9 · MEDIUM · '));
  });

  test('a won game is not restored as playable', () async {
    final a = await started(GridShape.mini, Difficulty.easy);
    playEmpty(a, right: true, count: 16);
    expect(a.state!.won, isTrue);
    await a.flush();
    final b = make(from: await AppStore.open(dir));
    await b.load();
    expect(b.state, isNull);
    expect(await store.readGame(), isA<Absent<SavedGame>>());
    expect(b.book.forDifficulty(Difficulty.easy).solved, 1);
  });

  test('two rapid changes produce one debounced write', () async {
    final a = await started(GridShape.classic, Difficulty.medium);
    await a.flush();
    final writes = store.writeCounts[StoreDocument.game] ?? 0;
    a.select(1);
    a.select(3);
    await Future<void>.delayed(const Duration(milliseconds: 400));
    await a.flush();
    // The flush adds one; the two selections added one more between them.
    expect((store.writeCounts[StoreDocument.game] ?? 0) - writes, 2);
  });

  test('a new board mid-game records an abandon: the streak reads 0', () async {
    final a = await started(GridShape.mini, Difficulty.easy);
    playEmpty(a, right: true, count: 16);
    expect(a.book.streak(Difficulty.easy), 1);
    a.startNew(GridShape.mini, Difficulty.easy);
    await a.generationDone;
    expect(a.book.streak(Difficulty.easy), 1, reason: 'the won game ended');
    a.startNew(GridShape.mini, Difficulty.easy);
    await a.generationDone;
    expect(a.book.streak(Difficulty.easy), 0);
    expect(a.book.shapeStats(Difficulty.easy, GridShape.mini).started, 3);
    await a.flush();
    final saved = (await store.readStats()).valueOrNull!;
    expect(saved.streak(Difficulty.easy), 0, reason: 'persisted at once');
  });

  test('restart records nothing new', () async {
    final a = await started(GridShape.classic, Difficulty.medium);
    playEmpty(a, right: false);
    final book = a.book;
    a.restart();
    expect(a.book, book);
  });

  test(
    'new boards take the last setup modes; settings reach a running game',
    () async {
      final a = make();
      await a.load();
      a.updateSettings(
        a.settings.copyWith(
          lastSetup: const LastSetup(strikeMode: StrikeMode.five),
        ),
      );
      a.startNew(GridShape.classic, Difficulty.medium);
      await a.generationDone;
      a.enterBoard();
      expect(a.state!.settings.strikeMode, StrikeMode.five);
      playEmpty(a, right: false, count: 4);
      expect([a.state!.mistakes, a.state!.lost], [4, false]);
      // Lowering the limit to 3 does not lose until the next wrong entry.
      a.updateSettings(
        a.settings.copyWith(
          game: a.settings.game.copyWith(strikeMode: StrikeMode.three),
        ),
      );
      expect(a.state!.lost, isFalse);
      playEmpty(a, right: false);
      expect(a.state!.lost, isTrue);
    },
  );

  test(
    'switching announce to now does not re-flag old wrong entries',
    () async {
      final a = make();
      await a.load();
      a.updateSettings(
        a.settings.copyWith(
          lastSetup: const LastSetup(announce: AnnounceMode.atEnd),
        ),
      );
      a.startNew(GridShape.classic, Difficulty.medium);
      await a.generationDone;
      playEmpty(a, right: false);
      final old = a.state!.selected!;
      expect(a.state!.notice, isNull);
      a.updateSettings(
        a.settings.copyWith(
          game: a.settings.game.copyWith(announce: AnnounceMode.now),
        ),
      );
      expect(a.state!.notice, isNull);
      expect(a.state!.isWrong(old), isTrue);
      expect(
        wrongShownCells(a.state!),
        isEmpty,
        reason: 'an entry placed unannounced stays untinted after the switch',
      );
      playEmpty(a, right: false);
      final fresh = a.state!.selected!;
      expect(wrongShownCells(a.state!), {
        fresh,
      }, reason: 'a wrong entry placed after the switch is tinted');
      await a.flush();
      final b = make(from: await AppStore.open(dir));
      await b.load();
      expect(wrongShownCells(b.state!), {
        fresh,
      }, reason: 'the unannounced entry stays untinted after a relaunch');
    },
  );

  test('a restored game copies its modes into the settings document', () async {
    final a = make();
    await a.load();
    a.updateSettings(
      a.settings.copyWith(
        lastSetup: const LastSetup(strikeMode: StrikeMode.zen),
      ),
    );
    a.startNew(GridShape.classic, Difficulty.medium);
    await a.generationDone;
    await a.flush();
    // Someone changes the setup afterwards; the saved game keeps Zen.
    await store.writeSettings(const AppSettings());
    final b = make(from: await AppStore.open(dir));
    await b.load();
    expect(b.state!.settings.strikeMode, StrikeMode.zen);
    expect(b.settings.game.strikeMode, StrikeMode.zen);
    expect(
      (await store.readSettings()).valueOrNull!.game.strikeMode,
      StrikeMode.zen,
    );
  });

  test(
    'a saved game from an unsupported pair is deleted with a log line',
    () async {
      final a = make();
      await a.load();
      final puzzle = fixturePuzzle(GridShape.mini, difficulty: Difficulty.hard);
      await store.writeGame(SavedGame.fromState(GameState.start(puzzle)));
      final lines = <String>[];
      final b = make(from: await AppStore.open(dir), log: lines.add);
      await b.load();
      expect(b.state, isNull);
      expect(await store.readGame(), isA<Absent<SavedGame>>());
      expect(lines, [
        contains('4×4 Hard is not a supported pair'),
      ], reason: 'an unsupported saved game is deleted with one log line');
    },
  );

  testWidgets('the STREAK tile reads 1 after the first win', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final c = GameController(generator: gen.call, seeds: CountingSeeds());
    final routes = RouteObserver<ModalRoute<void>>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorObservers: [routes],
        home: BoardScreen(controller: c, routeObserver: routes),
      ),
    );
    c.startNew(GridShape.mini, Difficulty.easy);
    await tester.pump();
    playEmpty(c, right: true, count: 16);
    await tester.pump(const Duration(milliseconds: 400));
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('tile-streak')),
        matching: find.text('1'),
      ),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });

  testWidgets('the grid restyles when the theme changes', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final c = GameController(generator: gen.call, seeds: CountingSeeds());
    final routes = RouteObserver<ModalRoute<void>>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorObservers: [routes],
        home: BoardScreen(controller: c, routeObserver: routes),
      ),
    );
    c.startNew(GridShape.classic, Difficulty.medium);
    await tester.pump();
    Color? gridBg() =>
        (tester
                    .widget<Container>(
                      find
                          .ancestor(
                            of: find.byType(ClipRRect),
                            matching: find.byType(Container),
                          )
                          .first,
                    )
                    .decoration!
                as BoxDecoration)
            .color;
    expect(gridBg(), BoardTheme.navy.gridBg);
    c.updateSettings(c.settings.copyWith(themeKey: 'paper'));
    await tester.pump();
    expect(gridBg(), BoardTheme.paper.gridBg);
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });

  test('mode changes mid-game carry into the next new game', () async {
    final a = make();
    await a.load();
    a.startNew(GridShape.classic, Difficulty.medium);
    await a.generationDone;
    expect(
      [a.state!.settings.strikeMode, a.state!.settings.announce],
      [StrikeMode.three, AnnounceMode.now],
    );
    a.updateSettings(
      a.settings.copyWith(
        game: a.settings.game.copyWith(
          announce: AnnounceMode.atEnd,
          strikeMode: StrikeMode.zen,
        ),
      ),
    );
    expect(
      [a.state!.settings.strikeMode, a.state!.settings.announce],
      [StrikeMode.zen, AnnounceMode.atEnd],
      reason: 'a mode change reaches the running game',
    );
    expect(
      [a.settings.lastSetup.strikeMode, a.settings.lastSetup.announce],
      [StrikeMode.zen, AnnounceMode.atEnd],
      reason: 'a mode change mid-game is copied into the last setup',
    );
    a.startNew(GridShape.classic, Difficulty.hard);
    await a.generationDone;
    expect(
      [a.state!.settings.strikeMode, a.state!.settings.announce],
      [StrikeMode.zen, AnnounceMode.atEnd],
      reason: 'the next board takes the modes changed mid-game',
    );
  });

  test('a theme picked mid-game survives the game ending, a new board and '
      'a relaunch', () async {
    final a = await started(GridShape.mini, Difficulty.easy);
    a.updateSettings(a.settings.copyWith(themeKey: BoardTheme.paper.key));
    playEmpty(a, right: true, count: 16);
    expect(a.state!.won, isTrue);
    a.startNew(GridShape.mini, Difficulty.easy);
    await a.generationDone;
    expect(
      a.themeKey,
      BoardTheme.paper.key,
      reason: 'a new board keeps the theme',
    );
    await a.flush();
    final b = make(from: await AppStore.open(dir));
    await b.load();
    expect(
      b.themeKey,
      BoardTheme.paper.key,
      reason: 'the theme is read back from the settings document',
    );
  });

  group('settings the controller cannot use', () {
    test('corrupt settings load as the defaults and are written back', () async {
      File('${dir.path}/settings.json').writeAsStringSync('{"v": 1, "da');
      final a = make();
      await a.load();
      expect(
        a.settings,
        const AppSettings(),
        reason: 'corrupt settings load as the defaults, as absent ones do',
      );
      expect(
        (await store.readSettings()).valueOrNull,
        const AppSettings(),
        reason:
            'corrupt settings are replaced by the defaults on disk, as absent '
            'ones are',
      );
    });

    test('newer settings load as the defaults and are left alone', () async {
      const newer = '{"v": 99, "data": {"themeKey": "paper"}}';
      final file = File('${dir.path}/settings.json')..writeAsStringSync(newer);
      final lines = <String>[];
      final a = make(log: lines.add);
      await a.load();
      expect(
        a.settings,
        const AppSettings(),
        reason: 'newer settings load as the defaults, as absent ones do',
      );
      expect(
        lines.where((l) => l.startsWith('not written')),
        isEmpty,
        reason: 'loading newer settings asks the store for no settings write',
      );
      expect(file.readAsStringSync(), newer);
    });
  });

  group('when things are written', () {
    int writes(StoreDocument d) => store.writeCounts[d] ?? 0;
    // Long enough for a write on the local disk, well inside the debounce.
    Future<void> settle([int ms = 100]) =>
        Future<void>.delayed(Duration(milliseconds: ms));

    test('statistics are not written as the clock runs', () async {
      final a = await started(GridShape.classic, Difficulty.medium);
      await a.flush();
      final seconds = a.state!.elapsedSeconds;
      final before = writes(StoreDocument.stats);
      await settle(2500);
      expect(a.state!.elapsedSeconds - seconds, greaterThanOrEqualTo(2));
      expect(
        writes(StoreDocument.stats),
        before,
        reason: 'a tick of the clock writes no statistics',
      );
    });

    // Backgrounding a paused game is the case where only the lifecycle's own
    // write can save it.
    for (final (what, paused, trigger)
        in <(String, bool, void Function(GameController))>[
          ('pausing', false, (c) => c.pause()),
          (
            'going to the background',
            true,
            (c) => c.didChangeAppLifecycleState(AppLifecycleState.paused),
          ),
          ('leaving the board', false, (c) => c.setBoardVisible(false)),
        ]) {
      test('$what writes the game at once and cancels the pending '
          'write', () async {
        final a = await started(GridShape.classic, Difficulty.medium);
        if (paused) a.pause();
        await a.flush();
        a.updateSettings(
          a.settings.copyWith(
            game: a.settings.game.copyWith(strikeMode: StrikeMode.five),
          ),
        );
        trigger(a);
        await settle();
        expect(
          (await store.readGame()).valueOrNull,
          SavedGame.fromState(a.state!),
          reason: '$what writes the game at once',
        );
        final after = writes(StoreDocument.game);
        await settle(400);
        expect(
          writes(StoreDocument.game),
          after,
          reason: '$what cancels the pending debounced write',
        );
      });
    }

    test('a new board is written at once and cancels the pending '
        'write', () async {
      final manual = ManualGenerator();
      final a = make(generator: manual.call);
      await a.load();
      a.startNew(GridShape.classic, Difficulty.medium);
      manual.finish();
      await a.generationDone;
      a.enterBoard();
      await a.flush();
      a.startNew(GridShape.classic, Difficulty.medium);
      await settle();
      final old = a.state!.puzzle.seed;
      a.select(1);
      expect(
        [a.state!.puzzle.seed, a.state!.selected],
        [old, 1],
        reason: 'the old board is still the game while the new one is made',
      );
      manual.finish();
      await a.generationDone;
      await settle();
      expect(
        (await store.readGame()).valueOrNull?.seed,
        a.state!.puzzle.seed,
        reason:
            'a new board is written at once, so a kill cannot bring back the '
            'game it replaced',
      );
      final after = writes(StoreDocument.game);
      await settle(400);
      expect(
        writes(StoreDocument.game),
        after,
        reason: "the new board's write cancels the pending debounced write",
      );
    });

    for (final how in ['fails', 'never arrives']) {
      test('an abandon is saved at once when the new board $how', () async {
        final a = await started(GridShape.mini, Difficulty.easy);
        playEmpty(a, right: true, count: 16);
        a.startNew(GridShape.mini, Difficulty.easy);
        await a.generationDone;
        await a.flush();
        expect(
          (await store.readStats()).valueOrNull!.streak(Difficulty.easy),
          1,
        );
        if (how == 'fails') {
          gen.failWith = timeoutFailure;
        } else {
          gen.hang = true;
        }
        a.startNew(GridShape.mini, Difficulty.easy);
        await settle();
        expect(
          how == 'fails' ? a.generationFailure : a.loading,
          isNotNull,
          reason: 'the new board $how',
        );
        expect(
          (await store.readStats()).valueOrNull!.streak(Difficulty.easy),
          0,
          reason: 'the abandon is on disk whether or not the new board arrives',
        );
      });
    }

    test('losing a restarted puzzle again records no second loss', () async {
      final a = await started(GridShape.classic, Difficulty.medium);
      playEmpty(a, right: false, count: 3);
      expect(a.state!.lost, isTrue);
      await settle();
      a.restart();
      final book = a.book;
      playEmpty(a, right: false, count: 3);
      expect(a.state!.lost, isTrue);
      final stats = writes(StoreDocument.stats);
      await settle();
      expect(a.book, same(book));
      expect(
        writes(StoreDocument.stats),
        stats,
        reason:
            'a second loss of one puzzle is not recorded: it is saved like '
            'any other move, after the debounce',
      );
    });

    test('a new last setup never reaches the running game', () async {
      final a = await started(GridShape.classic, Difficulty.medium);
      final modes = a.state!.settings;
      a.updateSettings(
        a.settings.copyWith(
          lastSetup: const LastSetup(
            strikeMode: StrikeMode.zen,
            announce: AnnounceMode.atEnd,
          ),
        ),
      );
      expect(
        a.state!.settings,
        modes,
        reason: 'updateSettings applies no last setup to a running game',
      );
    });

    test('no settings write is asked of the store while its document is '
        'newer', () async {
      const newer = '{"v": 99, "data": {"themeKey": "paper"}}';
      final file = File('${dir.path}/settings.json')..writeAsStringSync(newer);
      final lines = <String>[];
      final a = make(log: lines.add);
      await a.load();
      a.updateSettings(a.settings.copyWith(themeKey: 'paper'));
      a.startNew(GridShape.classic, Difficulty.medium);
      await a.generationDone;
      await a.flush();
      expect(
        lines.where((l) => l.startsWith('not written')),
        isEmpty,
        reason:
            'the controller skips settings writes while the document is '
            'newer',
      );
      expect(file.readAsStringSync(), newer);
    });
  });

  for (final won in [true, false]) {
    test('settings changes leave a ${won ? 'won' : 'lost'} game '
        'untouched', () async {
      final a = await started(GridShape.mini, Difficulty.easy);
      playEmpty(a, right: won, count: won ? 16 : 3);
      expect(won ? a.state!.won : a.state!.lost, isTrue);
      final over = a.state;
      final game = a.settings.game;
      a.updateSettings(
        a.settings.copyWith(
          game: game.copyWith(
            strikeMode: StrikeMode.zen,
            announce: AnnounceMode.atEnd,
            autoNotes: !game.autoNotes,
          ),
        ),
      );
      expect(a.settings.game.strikeMode, StrikeMode.zen);
      expect(
        a.state,
        same(over),
        reason: 'updateSettings leaves a finished game untouched',
      );
    });
  }
}
