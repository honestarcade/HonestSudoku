import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:honest_sudoku/build_info.dart';
import 'package:honest_sudoku/engine/engine.dart';
import 'package:honest_sudoku/store/app_store.dart';
import 'package:honest_sudoku/ui/app.dart';
import 'package:honest_sudoku/ui/board/board_grid.dart';
import 'package:honest_sudoku/ui/routes.dart';
import 'package:honest_sudoku/ui/screens/menu_screen.dart';
import 'package:honest_sudoku/ui/widgets/app_mark.dart';

import '../helpers.dart';
import '../stub_generator.dart';

String label(WidgetTester tester) =>
    tester.widget<Text>(find.byKey(const ValueKey('loading-label'))).data!;

Future<void> pumpGenerating(WidgetTester tester, ManualGenerator gen) async {
  setScreen(tester, 390, 844);
  await tester.pumpWidget(
    HonestSudokuApp(
      generator: gen.call,
      seeds: CountingSeeds(),
      store: () async => null,
      links: RecordingLinkOpener(),
      initialRoute: Routes.setup,
    ),
  );
  await tester.pumpAndSettle();
  await tester.ensureVisible(find.byKey(const ValueKey('setup-start')));
  await tester.tap(find.byKey(const ValueKey('setup-start')));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 200));
}

void main() {
  testWidgets('the label follows the generation phase', (tester) async {
    final gen = ManualGenerator();
    await pumpGenerating(tester, gen);
    expectMark(tester, 132, MarkInterior.board);
    expect(label(tester), 'GENERATING');
    for (final (f, want) in [
      (.2, 'GENERATING'),
      (.6, 'CARVING GIVENS'),
      (.9, 'READY'),
    ]) {
      gen.emit(GenerationProgress(f));
      await tester.pump(const Duration(milliseconds: 50));
      expect(label(tester), want, reason: 'at $f');
    }
    gen.finish();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    expect(find.byType(BoardGrid), findsOneWidget);
  });

  testWidgets('a fast board still shows the screen for 400 ms', (tester) async {
    final gen = ManualGenerator();
    await pumpGenerating(tester, gen);
    gen.finish();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.byKey(const ValueKey('loading-bar')), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(find.byType(BoardGrid), findsOneWidget);
  });

  testWidgets('a failed generation shows the notice and does not hand over', (
    tester,
  ) async {
    final gen = ManualGenerator();
    await pumpGenerating(tester, gen);
    gen.emit(const GenerationFailedEvent(timeoutFailure));
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('loading-notice')), findsOneWidget);
    expect(
      find.text("Couldn't build a board in time. Try again."),
      findsOneWidget,
    );
    expect(find.byType(BoardGrid), findsNothing);
    await tester.tap(find.byKey(const ValueKey('loading-back')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('setup-start')), findsOneWidget);
  });

  testWidgets('launch: never before 800 ms, then the menu', (tester) async {
    setScreen(tester, 390, 844);
    await tester.pumpWidget(
      HonestSudokuApp(
        generator: StubGenerator().call,
        store: () async => null,
        links: RecordingLinkOpener(),
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));
    expect(label(tester), 'READY');
    await tester.pump(const Duration(milliseconds: 650));
    expect(
      find.byType(MenuScreen),
      findsNothing,
      reason: 'the load finished, but 800 ms have not passed',
    );
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();
    expect(find.byType(MenuScreen), findsOneWidget);
  });

  testWidgets('launch: a store that will not open offers a retry', (
    tester,
  ) async {
    setScreen(tester, 390, 844);
    var fail = true;
    Future<AppStore?> store() async {
      if (fail) throw StateError('no directory');
      return null;
    }

    await tester.pumpWidget(
      HonestSudokuApp(
        generator: StubGenerator().call,
        store: store,
        links: RecordingLinkOpener(),
      ),
    );
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('SAVED DATA UNAVAILABLE'), findsOneWidget);
    expect(find.byType(MenuScreen), findsNothing);
    expect(find.byKey(const ValueKey('loading-back')), findsNothing);
    fail = false;
    await tester.tap(find.text('TRY AGAIN'));
    await tester.pump();
    await tester.pumpAndSettle();
    expect(find.byType(MenuScreen), findsOneWidget);
  });

  group('BuildInfo', () {
    test('parses name+build and formats both lines', () {
      final b = BuildInfo.parse('1.4.0+27');
      expect(
        [b.versionLine, b.aboutLine],
        ['v1.4.0 · BUILD 27', 'v1.4.0 · OFFLINE'],
      );
      expect(BuildInfo.parse('2.0.0-beta.1+3').name, '2.0.0-beta.1');
    });

    test('absent or malformed falls back to v0.0.0 · BUILD 0', () {
      for (final raw in ['', '1.0', '1.0.0', '1.0.0+x', 'v1.0.0+2']) {
        expect(
          BuildInfo.parse(raw).versionLine,
          'v0.0.0 · BUILD 0',
          reason: raw,
        );
      }
    });
  });

  testWidgets('routes: a fresh board leaves [menu, board]; the menu clears '
      'everything', (tester) async {
    await pumpApp(tester);
    await startFromMenu(tester);
    final names = RouteNames();
    // The app's own observer is in its AppScope; read it through a screen.
    final element = tester.element(find.byType(BoardGrid));
    final scopeNames =
        (element
                .findAncestorWidgetOfExactType<Navigator>()!
                .observers
                .whereType<RouteNames>())
            .single
            .names;
    expect(scopeNames, [Routes.menu, Routes.board]);
    expect(names.names, isEmpty);
    Routes.toMenu(element);
    await tester.pumpAndSettle();
    expect(
      (tester
              .element(find.byType(MenuScreen))
              .findAncestorWidgetOfExactType<Navigator>()!
              .observers
              .whereType<RouteNames>())
          .single
          .names,
      [Routes.menu],
    );
    expect(find.byType(MenuScreen), findsOneWidget);
    expect(GridShape.all, hasLength(4));
  });
}
