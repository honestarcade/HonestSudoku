import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:honest_sudoku/engine/engine.dart';
import 'package:honest_sudoku/game/game.dart';
import 'package:honest_sudoku/ui/board/notice_banner.dart';
import 'package:honest_sudoku/ui/theme/tokens.dart';

import '../harness.dart';

void main() {
  const cases = {
    BannerKind.error: (
      HsColors.noticeErrorBg,
      HsColors.noticeErrorRing,
      HsColors.wrongRed,
    ),
    BannerKind.ok: (HsColors.noticeOkBg, HsColors.noticeOkRing, HsColors.teal),
    BannerKind.hint: (
      HsColors.noticeHintBg,
      HsColors.noticeHintRing,
      HsColors.hintYellow,
    ),
  };

  for (final entry in cases.entries) {
    testWidgets('${entry.key.name}: fill, ring and kicker', (tester) async {
      await pumpFramed(
        tester,
        NoticeBanner(notice: Notice(entry.key, 'TAG', 'Body text.'), scale: 1),
      );
      final box = tester.widget<Container>(
        find.byKey(const ValueKey('notice')),
      );
      final d = box.decoration! as BoxDecoration;
      expect(d.color, entry.value.$1);
      expect((d.border! as Border).top.color, entry.value.$2);
      expect(
        tester.widget<Text>(find.text('TAG')).style!.color,
        entry.value.$3,
      );
      expect(
        tester.widget<Text>(find.text('Body text.')).style!.color,
        HsColors.bodyBlue,
      );
    });
  }

  testWidgets('an action calls back', (tester) async {
    var taps = 0;
    await pumpFramed(
      tester,
      NoticeBanner(
        notice: const Notice(BannerKind.error, 'GENERATION FAILED', 'x'),
        scale: 1,
        action: NoticeAction('TRY AGAIN', () => taps++),
      ),
    );
    await tester.tap(find.text('TRY AGAIN'));
    expect(taps, 1);
  });

  testWidgets('no action, no button', (tester) async {
    await pumpFramed(
      tester,
      const NoticeBanner(notice: Notice(BannerKind.ok, 'CHECK', 'x'), scale: 1),
    );
    expect(find.byKey(const ValueKey('notice-action')), findsNothing);
  });
}
