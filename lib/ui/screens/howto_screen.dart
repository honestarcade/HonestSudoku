// How to play: the design's five rule cards and the controls panel.

import 'package:flutter/material.dart';

import '../copy.dart';
import '../theme/tokens.dart';
import '../widgets/screen_frame.dart';
import '../widgets/screen_header.dart';

/// How to play.
class HowToScreen extends StatelessWidget {
  /// Creates the screen.
  const HowToScreen({super.key});

  @override
  Widget build(BuildContext context) => ScreenFrame(
    children: [
      ScreenHeader(
        title: Copy.howToPlay,
        keyPrefix: 'howto',
        onBack: () => Navigator.of(context).maybePop(),
      ),
      for (var i = 0; i < Copy.rules.length; i++)
        Panel(
          key: ValueKey('howto-rule-$i'),
          radius: 13,
          color: i == 0 ? HsColors.tealFill11 : HsColors.fill05,
          border: i == 0 ? HsColors.tealEdge34 : null,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              kickerText(
                Copy.rules[i].tag,
                size: 9,
                color: i == 0 ? HsColors.teal : HsColors.kicker,
              ),
              const SizedBox(height: 9),
              Text(
                Copy.rules[i].body,
                style: outfit(
                  12.5,
                  scale: 1,
                  color: HsColors.bodyBlue,
                  lineHeight: 1.6,
                ),
              ),
            ],
          ),
        ),
      Panel(
        radius: 13,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            kickerText(Copy.controls, size: 9),
            for (final g in Copy.gestures) ...[
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      vertical: 5,
                      horizontal: 8,
                    ),
                    decoration: BoxDecoration(
                      color: HsColors.tealFill14,
                      borderRadius: BorderRadius.circular(7),
                    ),
                    child: Text(
                      g.key,
                      style: plexMono(9.5, scale: 1, color: HsColors.teal),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      g.value,
                      style: outfit(
                        11.5,
                        scale: 1,
                        color: HsColors.bodySoft,
                        lineHeight: 1.45,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    ],
  );
}
