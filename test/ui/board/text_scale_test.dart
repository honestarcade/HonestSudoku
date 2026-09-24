// The board at the phone's font size (#53): everything but the grid scales
// up to 1.3×, nothing overflows or leaves the screen, and the grid's digits
// grow only with Large digits.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:honest_sudoku/engine/engine.dart';
import 'package:honest_sudoku/game/game.dart';
import 'package:honest_sudoku/ui/board/board_layout.dart';
import 'package:honest_sudoku/ui/board/board_screen.dart';
import 'package:honest_sudoku/ui/board/game_controller.dart';
import 'package:honest_sudoku/ui/board/notice_banner.dart';
import 'package:honest_sudoku/ui/theme/tokens.dart';

import '../stub_generator.dart';

Future<void> _loadFonts() async {
  Future<ByteData> bytes(String f) async =>
      ByteData.sublistView(await File('assets/fonts/$f').readAsBytes());
  final outfit = FontLoader(kFontOutfit);
  for (final w in ['Light', 'Regular', 'Medium', 'SemiBold', 'Bold']) {
    outfit.addFont(bytes('Outfit-$w.ttf'));
  }
  await outfit.load();
  final mono = FontLoader(kFontMono);
  for (final w in ['Regular', 'Medium', 'SemiBold']) {
    mono.addFont(bytes('IBMPlexMono-$w.ttf'));
  }
  await mono.load();
}

/// Pumps the board at [width]×[height] and [textScale], stages it, and
/// runs [check].
Future<void> _board(
  WidgetTester tester, {
  required double width,
  required double height,
  required double textScale,
  GridShape shape = GridShape.classic,
  bool bigDigits = false,
  void Function(GameController c)? stage,
  Future<void> Function(GameController c)? check,
}) async {
  final handle = tester.ensureSemantics();
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  final c = GameController(
    generator: StubGenerator().call,
    seeds: CountingSeeds(),
    settings: AppSettings(game: GameSettings(bigDigits: bigDigits)),
  );
  final routes = RouteObserver<ModalRoute<void>>();
  await tester.pumpWidget(
    MediaQuery(
      data: MediaQueryData.fromView(tester.view)
          .copyWith(disableAnimations: true),
      child: MaterialApp(
        navigatorObservers: [routes],
        home: BoardScreen(controller: c, routeObserver: routes),
      ),
    ),
  );
  c.startNew(shape, supportedDifficulties(shape).last);
  await tester.pump();
  await tester.pump();
  stage?.call(c);
  await tester.pump();
  expect(tester.takeException(), isNull);
  _expectInside(tester, Size(width, height));
  _expectStacked(tester);
  await check?.call(c);
  await tester.pumpWidget(const SizedBox());
  c.dispose();
  handle.dispose();
}

/// Every visible semantics node's box lies on the screen (0.5-px slack).
/// Nodes inside a scroll view count as fitting: they scroll.
void _expectInside(WidgetTester tester, Size screen) {
  final root = tester
      .binding
      .renderViews
      .first
      .owner!
      .semanticsOwner!
      .rootSemanticsNode!;
  final off = <String>[];
  void visit(SemanticsNode node, Matrix4 parent, bool scrolls) {
    final m = node.transform == null
        ? parent
        : (parent.clone()..multiply(node.transform!));
    final flags = node.getSemanticsData().flagsCollection;
    final inScroll = scrolls || flags.hasImplicitScrolling;
    final r = MatrixUtils.transformRect(m, node.rect);
    if (!inScroll &&
        !node.isMergedIntoParent &&
        !flags.isHidden &&
        !r.isEmpty &&
        (r.left < -.5 ||
            r.top < -.5 ||
            r.right > screen.width + .5 ||
            r.bottom > screen.height + .5)) {
      off.add('"${node.label}" at $r');
    }
    node.visitChildren((child) {
      visit(child, m, inScroll);
      return true;
    });
  }

  visit(root, Matrix4.identity(), false);
  expect(
    off,
    isEmpty,
    reason:
        'off the ${screen.width}×${screen.height} '
        'screen:\n  ${off.join('\n  ')}',
  );
}

/// Banner above pad above tools, no overlap, while the board shows.
void _expectStacked(WidgetTester tester) {
  final pad = find.byKey(const ValueKey('pad'));
  if (pad.evaluate().isEmpty) return; // a card covers the board
  final padBox = tester.getRect(pad);
  final tools = tester.getRect(find.byKey(const ValueKey('tools')));
  expect(
    padBox.bottom,
    lessThanOrEqualTo(tools.top - 7.5 * tools.width / 390),
    reason: 'the pad runs into the tools',
  );
  final notice = find.byKey(const ValueKey('notice'));
  if (notice.evaluate().isNotEmpty) {
    expect(
      tester.getRect(notice).bottom,
      lessThanOrEqualTo(padBox.top + .5),
      reason: 'the banner runs into the pad',
    );
  }
}

int _wrong(GameController c, int i) => c.state!.solution[i] % c.state!.n + 1;

void main() {
  setUpAll(_loadFonts);

  group('no overflow, nothing off screen', () {
    for (final (w, h) in [(360.0, 640.0), (390.0, 844.0)]) {
      for (final scale in [1.0, 1.3]) {
        for (final big in [false, true]) {
          for (final shape in GridShape.all) {
            for (final notice in [false, true]) {
              testWidgets(
                '${shape.label} ${w.toInt()}×${h.toInt()} ×$scale'
                '${big ? ' large digits' : ''}${notice ? ' hint' : ''}',
                (tester) => _board(
                  tester,
                  width: w,
                  height: h,
                  textScale: scale,
                  shape: shape,
                  bigDigits: big,
                  stage: notice ? (c) => c.hint() : null,
                ),
              );
            }
          }
        }
      }
    }

    final small = (width: 360.0, height: 640.0, textScale: 1.3);
    for (final shape in GridShape.all) {
      testWidgets(
        '${shape.label} in note mode with a mistake, 360×640 ×1.3',
        (tester) => _board(
          tester,
          width: small.width,
          height: small.height,
          textScale: small.textScale,
          shape: shape,
          stage: (c) {
            final i = c.state!.values.indexOf(0);
            c.select(i);
            c.place(_wrong(c, i));
            c.toggleNotes();
          },
        ),
      );
    }

    for (final (name, stage) in <(String, void Function(GameController))>[
      ('pause card', (c) => c.pause()),
      (
        'win card',
        (c) {
          final s = c.state!;
          for (var i = 0; i < s.values.length; i++) {
            if (!s.isGiven(i)) {
              c.select(i);
              c.place(s.solution[i]);
            }
          }
        },
      ),
      (
        'out-of-strikes card',
        (c) {
          for (var k = 0; k < 3; k++) {
            final i = c.state!.values.indexOf(0);
            c.select(i);
            c.place(_wrong(c, i));
          }
        },
      ),
    ]) {
      testWidgets(
        'the $name, 360×640 ×1.3',
        (tester) => _board(
          tester,
          width: small.width,
          height: small.height,
          textScale: small.textScale,
          stage: stage,
        ),
      );
    }
  });

  group('the worst notice never pushes the pad into the tools', () {
    for (final shape in GridShape.all) {
      test('${shape.label}, a 300-character hint at 1.3× on 360 px', () {
        final layout = BoardLayout.of(shape);
        const scale = 360 / 390;
        final notice = Notice(
          BannerKind.hint,
          'HINT · HIDDEN PAIR',
          'x ' * 150,
        );
        double h(int lines) =>
            NoticeBanner.measureHeight(
              notice: notice,
              scale: scale,
              textScaler: const TextScaler.linear(1.3),
              maxLines: lines,
            ) /
            scale;
        final lines = layout.noticeMaxLines(h(3));
        final padY = layout.padY(noticeHeight: h(lines));
        expect(
          padY + layout.padHeight,
          lessThanOrEqualTo(kToolBarY - kToolClearance),
          reason: '${shape.label}: $lines lines',
        );
        expect(padY, greaterThan(layout.noticeY + h(lines)));
      });
    }
  });

  testWidgets('the banner\'s measured height is its laid-out height', (
    tester,
  ) async {
    const notice = Notice(
      BannerKind.hint,
      'HINT',
      'Only one place in this row can take a 7, so it goes there.',
    );
    for (final (scale, lines) in [(1.0, 3), (1.3, 3), (1.3, 2)]) {
      await tester.pumpWidget(
        MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(scale)),
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: Align(
              alignment: Alignment.topLeft,
              child: NoticeBanner(notice: notice, scale: 1, maxLines: lines),
            ),
          ),
        ),
      );
      final measured = NoticeBanner.measureHeight(
        notice: notice,
        scale: 1,
        textScaler: TextScaler.linear(scale),
        maxLines: lines,
      );
      expect(
        tester.getSize(find.byType(NoticeBanner)).height,
        closeTo(measured, .5),
        reason: '×$scale, $lines lines',
      );
    }
  });

  group('complements', () {
    testWidgets('the timer chip grows with the font size', (tester) async {
      final widths = <double>[];
      for (final scale in [1.0, 1.3]) {
        await _board(
          tester,
          width: 390,
          height: 844,
          textScale: scale,
          check: (_) async => widths.add(
            tester.getSize(find.byKey(const ValueKey('chip-timer'))).width,
          ),
        );
      }
      expect(widths.last, greaterThan(widths.first));
    });

    testWidgets('the grid\'s digits ignore the font size and follow Large '
        'digits', (tester) async {
      final sizes = <(double, bool), double>{};
      for (final scale in [1.0, 1.3]) {
        for (final big in [false, true]) {
          await _board(
            tester,
            width: 390,
            height: 844,
            textScale: scale,
            bigDigits: big,
            check: (_) async {
              final digit = find.descendant(
                of: find.byKey(const ValueKey('cell-0')),
                matching: find.byType(RichText),
              );
              final p = tester.renderObject<RenderParagraph>(digit);
              sizes[(scale, big)] = p.textScaler.scale(p.text.style!.fontSize!);
            },
          );
        }
      }
      expect(sizes[(1.3, false)], sizes[(1.0, false)]);
      expect(sizes[(1.3, true)], sizes[(1.0, true)]);
      expect(sizes[(1.0, true)], sizes[(1.0, false)]! + 1);
    });
  });
}
