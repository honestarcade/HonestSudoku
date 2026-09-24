// The bundled fonts load and are real fonts (#47): text laid out in them
// measures differently from the same text in the test font.

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:honest_sudoku/ui/theme/tokens.dart';

Future<ByteData> _bytes(String path) async =>
    ByteData.sublistView(await File(path).readAsBytes());

Future<void> _load(String family, List<String> files) async {
  final loader = FontLoader(family);
  for (final f in files) {
    loader.addFont(_bytes('assets/fonts/$f'));
  }
  await loader.load();
}

double _width(String text, TextStyle style) {
  final painter = TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: TextDirection.ltr,
  )..layout();
  final w = painter.width;
  painter.dispose();
  return w;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await _load(kFontOutfit, [
      'Outfit-Light.ttf',
      'Outfit-Regular.ttf',
      'Outfit-Medium.ttf',
      'Outfit-SemiBold.ttf',
      'Outfit-Bold.ttf',
    ]);
    await _load(kFontMono, [
      'IBMPlexMono-Regular.ttf',
      'IBMPlexMono-Medium.ttf',
      'IBMPlexMono-SemiBold.ttf',
    ]);
  });

  for (final (text, family, weight) in [
    ('Honest Sudoku', kFontOutfit, FontWeight.w700),
    ('READY', kFontMono, FontWeight.w500),
  ]) {
    test('"$text" in $family ${weight.value} is not the test font', () {
      final real = _width(
        text,
        TextStyle(fontFamily: family, fontSize: 40, fontWeight: weight),
      );
      final baseline = _width(
        text,
        TextStyle(fontFamily: 'FlutterTest', fontSize: 40, fontWeight: weight),
      );
      expect(
        (real - baseline).abs() / baseline,
        greaterThanOrEqualTo(.05),
        reason: '$family measured $real against the test font\'s $baseline',
      );
    });
  }

  test('an empty file is not a font', () async {
    const text = 'Honest Sudoku';
    const style = TextStyle(fontFamily: 'Empty', fontSize: 40);
    final before = _width(text, style);
    final loader = FontLoader('Empty')..addFont(Future.value(ByteData(0)));
    try {
      await loader.load();
    } catch (_) {
      return; // Refused outright: nothing more to show.
    }
    expect(
      _width(text, style),
      before,
      reason: 'zero bytes changed how text measures',
    );
  });
}
