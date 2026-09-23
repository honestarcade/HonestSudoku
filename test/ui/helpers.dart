// Shared helpers for tests that run the whole app.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:honest_sudoku/build_info.dart';
import 'package:honest_sudoku/store/app_store.dart';
import 'package:honest_sudoku/ui/app.dart';
import 'package:honest_sudoku/ui/link_opener.dart';
import 'package:honest_sudoku/ui/routes.dart';

import 'stub_generator.dart';

/// Records what would have opened.
final class RecordingLinkOpener extends LinkOpener {
  /// Every open, in order.
  final opened = <(Uri, LinkMode)>[];

  @override
  Future<void> open(Uri uri, LinkMode mode) async => opened.add((uri, mode));
}

/// A logical [width]×[height] screen at pixel ratio 1.
void setScreen(WidgetTester tester, double width, double height) {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

/// The app over a stub generator and no store, opened at [initialRoute]
/// (the menu by default, skipping the launch splash).
Future<({StubGenerator gen, RecordingLinkOpener links})> pumpApp(
  WidgetTester tester, {
  String initialRoute = Routes.menu,
  StubGenerator? gen,
  Future<AppStore?> Function()? store,
  BuildInfo buildInfo = const BuildInfo('1.2.3', 45),
  double width = 390,
  double height = 844,
  double textScale = 1,
}) async {
  setScreen(tester, width, height);
  final g = gen ?? StubGenerator();
  final links = RecordingLinkOpener();
  // A fresh app every call: without this, a second call in one test keeps
  // the first app's state and navigator.
  await tester.pumpWidget(const SizedBox());
  // Through the platform, which the app's own MediaQuery reads.
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  await tester.pumpWidget(
    HonestSudokuApp(
      generator: g.call,
      seeds: CountingSeeds(),
      store: store ?? () async => null,
      links: links,
      buildInfo: buildInfo,
      initialRoute: initialRoute,
    ),
  );
  await tester.pumpAndSettle();
  return (gen: g, links: links);
}

/// From the menu: New puzzle, then Start; waits out the loading screen.
Future<void> startFromMenu(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('menu-new-card')));
  await tester.pumpAndSettle();
  await tester.ensureVisible(find.byKey(const ValueKey('setup-start')));
  await tester.tap(find.byKey(const ValueKey('setup-start')));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
  await tester.pumpAndSettle();
}
