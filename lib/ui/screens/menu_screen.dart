// The main menu: the mark and wordmark, Continue (or New puzzle), the New
// puzzle card, four buttons and the About Honest Arcade row.

import 'package:flutter/material.dart';

import '../a11y/speak.dart';
import '../app_scope.dart';
import '../board/board_styles.dart';
import '../copy.dart';
import '../routes.dart';
import '../theme/board_theme.dart';
import '../theme/tokens.dart';
import '../widgets/app_mark.dart';
import '../widgets/design_button.dart';
import '../widgets/screen_frame.dart';
import '../widgets/wordmark.dart';

/// The menu background: the design's
/// `radial-gradient(110% 90% at 24% 12%, #0a3a80, #05285F 58%, #031634)`.
const RadialGradient kMenuGradient = RadialGradient(
  center: Alignment(-.52, -.76),
  radius: 1,
  colors: [Color(0xFF0A3A80), Color(0xFF05285F), Color(0xFF031634)],
  stops: [0, .58, 1],
  transform: EllipseGradientTransform(1.1, .9, Offset(.24, .12)),
);

/// A menu button's colours.
const ButtonStyleSpec _menuButton = ButtonStyleSpec(
  edge: HsColors.edge14,
  bg: HsColors.fill04,
  fg: HsColors.white,
);

/// The main menu.
class MenuScreen extends StatelessWidget {
  /// Creates the menu.
  const MenuScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final c = AppScope.of(context).controller;
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        final summary = c.summary;
        return ScreenFrame(
          gradient: kMenuGradient,
          gap: 15,
          padding: const EdgeInsets.fromLTRB(22, 20, 22, 34),
          children: [
            Row(
              children: [
                const AppMark(size: 52, interior: MarkInterior.board),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Wordmark(size: 27, header: true),
                      const SizedBox(height: 7),
                      Semantics(
                        label: speak(Copy.menuByline),
                        excludeSemantics: true,
                        child: Text(
                          Copy.menuByline,
                          style: plexMono(
                            9,
                            scale: 1,
                            color: HsColors.muted,
                            letterSpacingEm: .24,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            DesignButton.variant(
              DesignButtonVariant.primary,
              key: ValueKey(summary == null ? 'menu-new' : 'menu-continue'),
              scale: 1,
              radius: 16,
              padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 20),
              onPressed: () => summary == null
                  ? Navigator.of(context).pushNamed(Routes.setup)
                  : Routes.toBoardPaused(context),
              semanticsLabel: summary == null
                  ? Copy.newPuzzle
                  : '${Copy.continuePuzzle}, ${speak(summary.meta)}',
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      summary == null ? Copy.newPuzzle : Copy.continuePuzzle,
                      style: outfit(
                        18,
                        scale: 1,
                        weight: FontWeight.w600,
                        color: HsColors.deepNavy,
                      ),
                    ),
                  ),
                  if (summary != null)
                    Opacity(
                      opacity: .7,
                      child: Text(
                        summary.meta,
                        key: const ValueKey('menu-meta'),
                        style: plexMono(11, scale: 1, color: HsColors.deepNavy),
                      ),
                    ),
                ],
              ),
            ),
            DesignButton(
              key: const ValueKey('menu-new-card'),
              spec: const ButtonStyleSpec(
                edge: HsColors.edge16,
                bg: HsColors.fill05,
                fg: HsColors.white,
              ),
              scale: 1,
              radius: 16,
              alignment: Alignment.centerLeft,
              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 18),
              onPressed: () => Navigator.of(context).pushNamed(Routes.setup),
              // The glyph grid is decoration.
              semanticsLabel: '${Copy.newPuzzle}, ${speak(Copy.newPuzzleSub)}',
              child: Row(
                children: [
                  const _MenuGlyph(),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          Copy.newPuzzle,
                          style: outfit(17, scale: 1, weight: FontWeight.w600),
                        ),
                        const SizedBox(height: 7),
                        Text(
                          Copy.newPuzzleSub,
                          style: outfit(
                            11.5,
                            scale: 1,
                            color: HsColors.chipFg,
                            lineHeight: 1.45,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            for (final pair in const [
              [
                ('menu-stats', Copy.statistics, Routes.stats),
                ('menu-howto', Copy.howToPlay, Routes.howto),
              ],
              [
                ('menu-settings', Copy.settings, Routes.settings),
                ('menu-about-app', Copy.aboutApp, Routes.aboutApp),
              ],
            ])
              Row(
                children: [
                  for (var i = 0; i < 2; i++) ...[
                    if (i > 0) const SizedBox(width: 10),
                    Expanded(
                      child: DesignButton(
                        key: ValueKey(pair[i].$1),
                        spec: _menuButton,
                        scale: 1,
                        radius: 14,
                        alignment: Alignment.centerLeft,
                        padding: const EdgeInsets.symmetric(
                          vertical: 15,
                          horizontal: 16,
                        ),
                        onPressed: () =>
                            Navigator.of(context).pushNamed(pair[i].$3),
                        child: Text(
                          pair[i].$2,
                          style: outfit(14, scale: 1, weight: FontWeight.w500),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            DesignButton(
              key: const ValueKey('menu-about-studio'),
              spec: const ButtonStyleSpec(
                edge: HsColors.tealEdge35,
                bg: HsColors.tealFill10,
                fg: HsColors.teal,
              ),
              scale: 1,
              radius: 14,
              padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 16),
              onPressed: () =>
                  Navigator.of(context).pushNamed(Routes.aboutStudio),
              semanticsLabel: '${Copy.aboutStudio}. ${Copy.aboutStudioSub}',
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          Copy.aboutStudio,
                          style: outfit(
                            13.5,
                            scale: 1,
                            weight: FontWeight.w600,
                            color: HsColors.teal,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          Copy.aboutStudioSub,
                          style: outfit(
                            11,
                            scale: 1,
                            color: HsColors.desc,
                            lineHeight: 1.3,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    '›',
                    style: outfit(
                      16,
                      scale: 1,
                      weight: FontWeight.w500,
                      color: HsColors.teal,
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

/// The New puzzle card's 9×9 glyph: the design's eleven fixed digits.
class _MenuGlyph extends StatelessWidget {
  const _MenuGlyph();

  @override
  Widget build(BuildContext context) => Container(
    width: 74,
    height: 74,
    padding: const EdgeInsets.all(5),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(12),
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [HsColors.markNavy, HsColors.deepNavy],
      ),
    ),
    child: Column(
      children: [
        for (var r = 0; r < 9; r++) ...[
          if (r > 0) const SizedBox(height: 1),
          Expanded(
            child: Row(
              children: [
                for (var c = 0; c < 9; c++) ...[
                  if (c > 0) const SizedBox(width: 1),
                  Expanded(child: _cell(r * 9 + c)),
                ],
              ],
            ),
          ),
        ],
      ],
    ),
  );

  Widget _cell(int i) {
    final digit = Copy.menuDigits[i];
    return Container(
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: digit == null
            ? HsColors.fill07
            : const Color.fromRGBO(0, 214, 180, .2),
        borderRadius: BorderRadius.circular(1),
      ),
      child: digit == null
          ? null
          : Text(
              '$digit',
              textScaler: TextScaler.noScaling,
              style: outfit(
                4.5,
                scale: 1,
                weight: FontWeight.w600,
                color: const Color(0xFF7FF0DC),
              ),
            ),
    );
  }
}
