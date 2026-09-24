// About the App: the boxed mark and version, the paragraph, what's in it,
// the promises, and the links. The design's install size is dropped: the
// app cannot know it.

import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../board/board_styles.dart';
import '../copy.dart';
import '../link_opener.dart';
import '../routes.dart';
import '../theme/tokens.dart';
import '../widgets/app_mark.dart';
import '../widgets/design_button.dart';
import '../widgets/screen_frame.dart';
import '../widgets/screen_header.dart';
import '../widgets/text_link.dart';

/// About the App.
class AboutAppScreen extends StatelessWidget {
  /// Creates the screen.
  const AboutAppScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final opener = scope.links;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Routes.toMenu(context);
      },
      child: ScreenFrame(
        children: [
          ScreenHeader(
            title: Copy.aboutApp,
            keyPrefix: 'about',
            onBack: () => Routes.toMenu(context),
          ),
          Panel(
            radius: 16,
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const AppMark(size: 62, boxed: true),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        Copy.appName,
                        style: outfit(20, scale: 1, weight: FontWeight.w700),
                      ),
                      const SizedBox(height: 7),
                      Text(
                        scope.buildInfo.aboutLine,
                        key: const ValueKey('about-version'),
                        style: plexMono(
                          10,
                          scale: 1,
                          color: HsColors.muted,
                          letterSpacingEm: .14,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Text(
            Copy.aboutIntro,
            style: outfit(
              13.5,
              scale: 1,
              color: HsColors.bodySoft,
              lineHeight: 1.65,
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              kickerText(Copy.whatsInIt),
              for (final f in Copy.features) ...[
                const SizedBox(height: 8),
                Panel(
                  radius: 11,
                  padding: const EdgeInsets.symmetric(
                    vertical: 11,
                    horizontal: 13,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        margin: const EdgeInsets.only(top: 6),
                        decoration: const BoxDecoration(
                          color: HsColors.teal,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              f.title,
                              style: outfit(
                                12,
                                scale: 1,
                                weight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 5),
                            Text(
                              f.body,
                              style: outfit(
                                11,
                                scale: 1,
                                color: HsColors.chipFg,
                                lineHeight: 1.4,
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
          Panel(
            radius: 13,
            color: HsColors.tealFill10,
            border: HsColors.tealEdge32,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                kickerText(Copy.honestPromises, size: 9, color: HsColors.teal),
                const SizedBox(height: 11),
                LayoutBuilder(
                  builder: (context, box) => Wrap(
                    spacing: 7,
                    runSpacing: 7,
                    children: [
                      for (final chip in Copy.promiseChips)
                        SizedBox(
                          width: (box.maxWidth - 7) / 2,
                          child: _PromiseChip(chip),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                DesignButton(
                  key: const ValueKey('about-promises'),
                  spec: const ButtonStyleSpec(
                    edge: HsColors.tealEdge40,
                    bg: Color(0x00000000),
                    fg: HsColors.teal,
                  ),
                  scale: 1,
                  radius: 11,
                  padding: const EdgeInsets.all(12),
                  onPressed: () =>
                      Navigator.of(context).pushNamed(Routes.aboutStudio),
                  child: Text(
                    Copy.promisesButton,
                    style: outfit(
                      12.5,
                      scale: 1,
                      weight: FontWeight.w600,
                      color: HsColors.teal,
                    ),
                  ),
                ),
              ],
            ),
          ),
          FooterLinks(
            lead: Copy.madeBy,
            links: [
              TextLink(
                key: const ValueKey('about-link-site'),
                label: Copy.linkHonestArcade,
                uri: AppLinks.site,
                opener: opener,
              ),
              TextLink(
                key: const ValueKey('about-link-source'),
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

class _PromiseChip extends StatelessWidget {
  const _PromiseChip(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 10),
    decoration: BoxDecoration(
      color: HsColors.fill07,
      borderRadius: BorderRadius.circular(999),
    ),
    child: Row(
      children: [
        Text(
          '✓',
          style: outfit(
            10,
            scale: 1,
            weight: FontWeight.w600,
            color: HsColors.teal,
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            style: plexMono(
              10,
              scale: 1,
              color: HsColors.bodyBlue,
              lineHeight: 1.2,
            ),
          ),
        ),
      ],
    ),
  );
}
