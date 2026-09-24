import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'feedback/sound_player.dart';
import 'ui/app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // The board is designed for a portrait phone and never rotates (#12).
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  runApp(
    HonestSudokuApp(
      sound: ChannelSoundPlayer(),
      assetManifest: () async =>
          (await AssetManifest.loadFromAssetBundle(rootBundle))
              .listAssets()
              .toSet(),
    ),
  );
}
