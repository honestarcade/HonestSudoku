import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:honest_sudoku/engine/engine.dart';

import 'ui/app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // The board is designed for a portrait phone and never rotates (#12).
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  // M4 replaces this temporary launch path: the app opens straight onto a
  // board until the menu and setup screens exist. `--dart-define=
  // HS_LAUNCH_SIZE=16` opens another size (4, 6, 9 or 16) for screenshots.
  const size = int.fromEnvironment('HS_LAUNCH_SIZE', defaultValue: 9);
  final shape = GridShape.all.firstWhere(
    (s) => s.n == size,
    orElse: () => GridShape.classic,
  );
  // Medium where the size offers it; 4×4 offers Easy only (#25).
  final bands = supportedDifficulties(shape);
  final band = bands.contains(Difficulty.medium)
      ? Difficulty.medium
      : bands.last;
  runApp(HonestSudokuApp(launchShape: shape, launchDifficulty: band));
}
