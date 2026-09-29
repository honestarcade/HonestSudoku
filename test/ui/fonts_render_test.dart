// The bundled fonts load and are real fonts (#47): text laid out in them
// measures differently from the same text in the test font.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:honest_sudoku/ui/screens/menu_screen.dart';
import 'package:honest_sudoku/ui/theme/tokens.dart';

import 'helpers.dart';

/// Every bundled face, by family.
const _faces = {
  kFontOutfit: [
    'Outfit-Light.ttf',
    'Outfit-Regular.ttf',
    'Outfit-Medium.ttf',
    'Outfit-SemiBold.ttf',
    'Outfit-Bold.ttf',
  ],
  kFontMono: [
    'IBMPlexMono-Regular.ttf',
    'IBMPlexMono-Medium.ttf',
    'IBMPlexMono-SemiBold.ttf',
  ],
};

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
    for (final MapEntry(key: family, value: files) in _faces.entries) {
      await _load(family, files);
    }
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

  // In a family of its own, a face that is not a real font has nothing to
  // fall back on among its siblings: the text lays out in the test font.
  for (final file in _faces.values.expand((f) => f)) {
    test('$file is a font of its own', () async {
      final family = 'Probe $file';
      await _load(family, [file]);
      final real = _width(
        'Honest Sudoku',
        TextStyle(fontFamily: family, fontSize: 40),
      );
      final baseline = _width(
        'Honest Sudoku',
        const TextStyle(fontFamily: 'FlutterTest', fontSize: 40),
      );
      expect(
        (real - baseline).abs() / baseline,
        greaterThanOrEqualTo(.05),
        reason: '$file laid out as the test font: it is not a font',
      );
    });
  }

  test('the text styles fall back to the system fonts', () {
    final sans = outfit(12, scale: 1);
    expect(sans.fontFamily, kFontOutfit);
    expect(
      sans.fontFamilyFallback,
      kFontFallback,
      reason: 'outfit() falls back to the system sans-serif',
    );
    final mono = plexMono(12, scale: 1);
    expect(mono.fontFamily, kFontMono);
    expect(
      mono.fontFamilyFallback,
      ['monospace', ...kFontFallback],
      reason: 'plexMono() falls back to the system monospace, then sans-serif',
    );
    expect(kFontFallback, isNotEmpty);
  });

  testWidgets('the app theme falls back to the system fonts', (tester) async {
    await pumpApp(tester);
    final theme = Theme.of(tester.element(find.byType(MenuScreen)));
    final styles = {
      'bodyMedium': theme.textTheme.bodyMedium,
      'titleLarge': theme.textTheme.titleLarge,
      'labelLarge': theme.textTheme.labelLarge,
    };
    for (final MapEntry(key: name, value: style) in styles.entries) {
      expect(style!.fontFamily, kFontOutfit, reason: name);
      expect(
        style.fontFamilyFallback,
        kFontFallback,
        reason: "the theme's $name falls back to the system sans-serif",
      );
    }
  });
}
