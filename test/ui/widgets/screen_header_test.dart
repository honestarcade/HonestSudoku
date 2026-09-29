// The header's ‹ (#323): its size, and its ink centred in the button, drawn
// in the bundled Outfit rather than the test font.

import 'dart:io';

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:honest_sudoku/ui/theme/tokens.dart';
import 'package:honest_sudoku/ui/widgets/screen_header.dart';

const _scale = 4.0;
final _boundary = GlobalKey();

Future<void> _pumpHeader(WidgetTester tester, {double textScale = 1}) async {
  tester.view.physicalSize = const Size(390, 100) * _scale;
  tester.view.devicePixelRatio = _scale;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MediaQuery(
      data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: RepaintBoundary(
          key: _boundary,
          child: ColoredBox(
            color: const Color(0xFF000000),
            child: Align(
              alignment: Alignment.topLeft,
              child: ScreenHeader(title: 'Settings', onBack: () {}),
            ),
          ),
        ),
      ),
    ),
  );
}

/// The ‹'s ink box in logical pixels: the bright pixels inside the button,
/// clear of its 1-pt edge.
Future<Rect> _ink(WidgetTester tester) async {
  final button = tester.getRect(find.byKey(const ValueKey('screen-back')));
  final boundary =
      _boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final bytes = (await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: _scale);
    final data = await image.toByteData();
    return (image.width, data!);
  }))!;
  final (width, data) = bytes;
  var (left, top, right, bottom) = (1e9, 1e9, -1e9, -1e9);
  final inner = button.deflate(2);
  for (var y = (inner.top * _scale).ceil(); y < inner.bottom * _scale; y++) {
    for (var x = (inner.left * _scale).ceil(); x < inner.right * _scale; x++) {
      if (data.getUint8((y * width + x) * 4) < 128) continue;
      left = x < left ? x.toDouble() : left;
      right = x + 1 > right ? x + 1.0 : right;
      top = y < top ? y.toDouble() : top;
      bottom = y + 1 > bottom ? y + 1.0 : bottom;
    }
  }
  return Rect.fromLTRB(left, top, right, bottom) / _scale;
}

Future<void> _load(String family, List<String> files) async {
  final loader = FontLoader(family);
  for (final f in files) {
    loader.addFont(
      File('assets/fonts/$f').readAsBytes().then(ByteData.sublistView),
    );
  }
  await loader.load();
}

extension on Rect {
  Rect operator /(double k) =>
      Rect.fromLTRB(left / k, top / k, right / k, bottom / k);
}

void main() {
  setUpAll(() => _load(kFontOutfit, ['Outfit-Medium.ttf']));

  testWidgets('the ‹ is 26 pt, and system text size does not grow it', (
    tester,
  ) async {
    for (final textScale in [1.0, 1.3]) {
      await _pumpHeader(tester, textScale: textScale);
      final glyph = find.text('‹');
      expect(
        tester.widget<Text>(glyph).style!.fontSize,
        26,
        reason: 'the back glyph is set at 26 pt',
      );
      expect(
        tester.renderObject<RenderParagraph>(glyph).textScaler,
        TextScaler.noScaling,
        reason: 'the back glyph keeps its size in its fixed box',
      );
    }
  });

  testWidgets('the ‹ ink is centred in the 34-pt button', (tester) async {
    await _pumpHeader(tester);
    final button = tester.getRect(find.byKey(const ValueKey('screen-back')));
    expect(button.size, const Size(34, 34));
    final ink = await _ink(tester);
    expect(
      ink.height,
      greaterThan(7),
      reason: 'the back glyph draws in Outfit at 26 pt',
    );
    expect(
      (ink.center.dy - button.center.dy).abs(),
      lessThan(.5),
      reason: 'the back glyph ink is vertically centred in its button',
    );
    expect(
      (ink.center.dx - button.center.dx).abs(),
      lessThan(.5),
      reason: 'the back glyph ink is horizontally centred in its button',
    );
  });
}
