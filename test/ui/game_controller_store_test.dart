import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:honest_sudoku/engine/engine.dart';
import 'package:honest_sudoku/game/game.dart';
import 'package:honest_sudoku/store/app_store.dart';
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

  GameController make([AppStore? s]) {
    final c = GameController(
      generator: gen.call,
      seeds: CountingSeeds(),
      store: () async => s ?? store,
      log: (_) {},
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

    final b = make(await AppStore.open(dir));
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
    final b = make(await AppStore.open(dir));
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
      expect(a.state!.notice, isNull);
      a.updateSettings(
        a.settings.copyWith(
          game: a.settings.game.copyWith(announce: AnnounceMode.now),
        ),
      );
      expect(a.state!.notice, isNull);
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
    final b = make(await AppStore.open(dir));
    await b.load();
    expect(b.state!.settings.strikeMode, StrikeMode.zen);
    expect(b.settings.game.strikeMode, StrikeMode.zen);
    expect(
      (await store.readSettings()).valueOrNull!.game.strikeMode,
      StrikeMode.zen,
    );
  });

  test('a saved game from an unsupported pair is deleted', () async {
    final a = make();
    await a.load();
    final puzzle = fixturePuzzle(GridShape.mini, difficulty: Difficulty.hard);
    await store.writeGame(SavedGame.fromState(GameState.start(puzzle)));
    final b = make(await AppStore.open(dir));
    await b.load();
    expect(b.state, isNull);
    expect(await store.readGame(), isA<Absent<SavedGame>>());
  });

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
}
