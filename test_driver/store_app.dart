// The app as the store screenshots see it (#57): fixed seeds, a store
// pre-written with default settings and a plausible statistics book, full
// screen, and the Flutter Driver extension so test_driver/store_app_test.dart
// can tap through it. Run by tools/screenshots.sh, never shipped: the release
// build's target is lib/main.dart.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_driver/driver_extension.dart';
import 'package:honest_sudoku/build_info.dart';
import 'package:honest_sudoku/engine/engine.dart';
import 'package:honest_sudoku/game/game.dart';
import 'package:honest_sudoku/store/app_store.dart';
import 'package:honest_sudoku/ui/app.dart';
import 'package:honest_sudoku/ui/app_scope.dart';
import 'package:honest_sudoku/ui/board/game_controller.dart';
import 'package:honest_sudoku/ui/link_opener.dart';

/// The 9×9 Medium board's seed, the design's golden seed.
const kStoreSeed9 = 20260824;

/// The 16×16 Hard board's seed: the first, counting from 1, that generates
/// under the ceiling on the store AVD. Seed 1 did, on the first run.
const kStoreSeed16 = 1;

/// Seeds in order, repeating the last.
final class _Seeds implements SeedSource {
  _Seeds(this._queue);
  final List<int> _queue;
  var _i = 0;

  @override
  int next() => _queue[_i < _queue.length - 1 ? _i++ : _i];
}

final class _NoLinks extends LinkOpener {
  @override
  Future<void> open(Uri uri, LinkMode mode) async {}
}

/// A book with a few weeks of play, chosen backwards from the captures: the
/// drive itself starts two games (9×9 Medium, then 16×16 Hard) and abandons
/// the first, which these figures allow for.
StatsBook storeBook() {
  var b = StatsBook.empty;
  const plan = {
    // difficulty: (started, solved, best seconds)
    Difficulty.easy: (12, 10, 252),
    Difficulty.medium: (9, 7, 468),
    Difficulty.hard: (6, 4, 785),
    Difficulty.expert: (3, 2, 1360),
    Difficulty.evil: (1, 0, 0),
  };
  for (final MapEntry(key: d, value: (started, solved, best)) in plan.entries) {
    for (var k = 0; k < started; k++) {
      b = b.recordStart(GridShape.classic, d);
      if (k < solved) {
        final seconds = best + (k * 97) % 400;
        b = b
            .recordTime(GridShape.classic, d, seconds)
            .recordWin(GridShape.classic, d, seconds);
      } else {
        b = b.recordLoss(GridShape.classic, d);
      }
    }
  }
  for (final (shape, d) in [
    (GridShape.short, Difficulty.medium),
    (GridShape.short, Difficulty.easy),
    (GridShape.mini, Difficulty.easy),
  ]) {
    b = b
        .recordStart(shape, d)
        .recordTime(shape, d, 95)
        .recordWin(shape, d, 95);
  }
  return b;
}

/// The app's controller, found in the element tree (no seam in lib/).
GameController? _findController() {
  GameController? found;
  void visit(Element e) {
    if (found != null) return;
    final w = e.widget;
    if (w is AppScope) {
      found = w.controller;
      return;
    }
    e.visitChildren(visit);
  }

  WidgetsBinding.instance.rootElement?.visitChildren(visit);
  return found;
}

/// Answers the driver: the running game, so it can enter correct values
/// and check a hint shows.
Future<String> _answer(String? request) async {
  final s = _findController()?.state;
  return jsonEncode(switch (request) {
    'state' => {
      'values': s?.values,
      'solution': s?.solution,
      'n': s?.n,
      'notice': s?.notice != null,
      'shape': s?.shape.label,
    },
    _ => <String, Object?>{},
  });
}

Future<void> main() async {
  enableFlutterDriverExtension(handler: _answer);
  WidgetsFlutterBinding.ensureInitialized();
  // Full screen, no system bars: the capture is the whole 1080×1920 display.
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  final dir = await Directory.systemTemp.createTemp('store-shots');
  final store = await AppStore.open(dir);
  await store.writeSettings(
    const AppSettings(game: GameSettings(showTimer: true)),
  );
  await store.writeStats(storeBook());

  runApp(
    HonestSudokuApp(
      store: () async => AppStore.open(dir),
      seeds: _Seeds([kStoreSeed9, kStoreSeed16]),
      links: _NoLinks(),
      buildInfo: BuildInfo.current,
    ),
  );
}
