// The app's root: owns the game controller and the navigator.

import 'package:flutter/material.dart';
import 'package:honest_sudoku/engine/engine.dart';
import 'package:honest_sudoku/game/game.dart';

import 'board/board_screen.dart';
import 'board/game_controller.dart';
import 'theme/tokens.dart';

/// The app.
class HonestSudokuApp extends StatefulWidget {
  /// Creates the app, opening a [launchShape] board at [launchDifficulty].
  /// [generator] and [seeds] replace the real ones, for tests.
  const HonestSudokuApp({
    this.launchShape = GridShape.classic,
    this.launchDifficulty = Difficulty.medium,
    this.generator,
    this.seeds,
    super.key,
  });

  /// The size the app opens on.
  final GridShape launchShape;

  /// The band the app opens on.
  final Difficulty launchDifficulty;

  /// Replaces the isolate generator.
  final BoardGenerator? generator;

  /// Replaces the random seed source.
  final SeedSource? seeds;

  @override
  State<HonestSudokuApp> createState() => _HonestSudokuAppState();
}

class _HonestSudokuAppState extends State<HonestSudokuApp> {
  late final GameController _controller = GameController(
    generator: widget.generator,
    seeds: widget.seeds,
  )..startNew(widget.launchShape, widget.launchDifficulty);
  final _routes = RouteObserver<ModalRoute<void>>();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Honest Sudoku',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: HsColors.navy,
      fontFamily: kFontOutfit,
    ),
    navigatorObservers: [_routes],
    home: BoardScreen(controller: _controller, routeObserver: _routes),
  );
}
