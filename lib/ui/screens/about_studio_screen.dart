// About Honest Arcade: the studio's words, the support card, the seven
// promises, three chips and the footer links.

import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../copy.dart';
import '../link_opener.dart';
import '../routes.dart';
import '../theme/board_theme.dart';
import '../theme/tokens.dart';
import '../widgets/app_mark.dart';
import '../widgets/screen_frame.dart';
import '../widgets/screen_header.dart';
import '../widgets/text_link.dart';

/// The studio screen's background: the design's
/// `radial-gradient(110% 80% at 78% 12%, #0a3a80, #05285F 58%, #031634)`.
const RadialGradient kStudioGradient = RadialGradient(
  center: Alignment(.56, -.76),
  radius: 1,
  colors: [Color(0xFF0A3A80), Color(0xFF05285F), Color(0xFF031634)],
  stops: [0, .58, 1],
  transform: EllipseGradientTransform(1.1, .8, Offset(.78, .12)),
);

/// About Honest Arcade.
class AboutStudioScreen extends StatelessWidget {
  /// Creates the screen.
  const AboutStudioScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final opener = AppScope.of(context).links;
    const chips = [
      (HsColors.tealFill14, HsColors.teal),
      (HsColors.blueChip, HsColors.promiseBlue),
      (HsColors.violetChip, HsColors.promiseViolet),
    ];
    // The design's goBack: to the board when opened from it — which this
    // screen never is — otherwise to the menu, even from About the App.
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Routes.toMenu(context);
      },
      child: ScreenFrame(
        gradient: kStudioGradient,
        gap: 15,
        children: [
          ScreenHeader(
            title: Copy.aboutStudio,
            keyPrefix: 'studio',
            onBack: () => Routes.toMenu(context),
          ),
          const Padding(
            padding: EdgeInsets.only(top: 6, bottom: 2),
            child: Center(child: AppMark(size: 120)),
          ),
          Text(
            Copy.studioIntro,
            style: outfit(
              14,
              scale: 1,
              color: HsColors.studioText,
              lineHeight: 1.65,
            ),
          ),
          Text(
            Copy.studioLine,
            style: outfit(
              14,
              scale: 1,
              color: HsColors.muted,
              lineHeight: 1.65,
            ),
          ),
          Semantics(
            link: true,
            container: true,
            child: GestureDetector(
              key: const ValueKey('studio-support'),
              behavior: HitTestBehavior.opaque,
              onTap: () => opener.open(AppLinks.contribute, LinkMode.external),
              child: Panel(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color.fromRGBO(0, 214, 180, .13),
                    Color.fromRGBO(132, 72, 252, .13),
                  ],
                ),
                border: const Color.fromRGBO(0, 214, 180, .28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    kickerText(Copy.supportKicker, color: HsColors.teal),
                    const SizedBox(height: 6),
                    Text(
                      Copy.supportBody,
                      style: outfit(
                        12.5,
                        scale: 1,
                        color: HsColors.studioText,
                        lineHeight: 1.55,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      Copy.supportLink,
                      style: outfit(11.5, scale: 1, weight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              kickerText(Copy.ourPromises),
              for (final p in Copy.promises) ...[
                const SizedBox(height: 8),
                Panel(
                  radius: 12,
                  padding: const EdgeInsets.symmetric(
                    vertical: 12,
                    horizontal: 14,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '✓',
                        style: outfit(
                          12,
                          scale: 1,
                          weight: FontWeight.w600,
                          color: Color(p.color),
                          lineHeight: 1.2,
                        ),
                      ),
                      const SizedBox(width: 11),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              p.title,
                              style: outfit(
                                12.5,
                                scale: 1,
                                weight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 5),
                            Text(
                              p.body,
                              style: outfit(
                                11,
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
              ],
            ],
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: [
              for (var i = 0; i < Copy.studioChips.length; i++)
                Container(
                  padding: const EdgeInsets.symmetric(
                    vertical: 7,
                    horizontal: 12,
                  ),
                  decoration: BoxDecoration(
                    color: chips[i].$1,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    Copy.studioChips[i],
                    style: plexMono(10.5, scale: 1, color: chips[i].$2),
                  ),
                ),
            ],
          ),
          FooterLinks(
            center: true,
            links: [
              TextLink(
                key: const ValueKey('studio-link-site'),
                label: Copy.linkSite,
                uri: AppLinks.site,
                opener: opener,
              ),
              TextLink(
                key: const ValueKey('studio-link-source'),
                label: Copy.linkSource,
                uri: AppLinks.source,
                opener: opener,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
