// The frame every non-board screen shares: a navy (or gradient) background
// behind the whole phone, the content in a scrolling column inside the safe
// area with the design's paddings, capped at 430 points on wide screens.

import 'package:flutter/material.dart';

import '../a11y/speak.dart';
import '../theme/tokens.dart';

/// A scrolling screen.
class ScreenFrame extends StatelessWidget {
  /// Creates the frame.
  const ScreenFrame({
    required this.children,
    this.gradient,
    this.gap = 13,
    this.padding = const EdgeInsets.fromLTRB(20, 12, 20, 30),
    this.overlay,
    super.key,
  });

  /// The content, top to bottom.
  final List<Widget> children;

  /// A background gradient; plain navy when null.
  final Gradient? gradient;

  /// Space between the children.
  final double gap;

  /// Around the content, inside the safe area.
  final EdgeInsets padding;

  /// Something drawn over the whole screen (a confirmation card).
  final Widget? overlay;

  @override
  Widget build(BuildContext context) => Material(
    type: MaterialType.transparency,
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: gradient == null ? HsColors.navy : null,
        gradient: gradient,
      ),
      child: Stack(
        children: [
          SafeArea(
            child: SingleChildScrollView(
              padding: padding,
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 430),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var i = 0; i < children.length; i++) ...[
                        if (i > 0) SizedBox(height: gap),
                        children[i],
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
          ?overlay,
        ],
      ),
    ),
  );
}

/// A rounded, faintly filled panel.
class Panel extends StatelessWidget {
  /// Creates a panel.
  const Panel({
    required this.child,
    this.color = HsColors.fill05,
    this.radius = 14,
    this.padding = const EdgeInsets.symmetric(vertical: 14, horizontal: 15),
    this.border,
    this.gradient,
    super.key,
  });

  /// The content.
  final Widget child;

  /// The fill.
  final Color color;

  /// The corner radius.
  final double radius;

  /// Inner padding.
  final EdgeInsets padding;

  /// An edge, for the teal panels.
  final Color? border;

  /// A gradient fill instead of [color].
  final Gradient? gradient;

  @override
  Widget build(BuildContext context) => Container(
    padding: padding,
    decoration: BoxDecoration(
      color: gradient == null ? color : null,
      gradient: gradient,
      borderRadius: BorderRadius.circular(radius),
      border: border == null ? null : Border.all(color: border!),
    ),
    child: child,
  );
}

/// A panel's title.
Widget panelTitle(String text, {double size = 13.5}) => Semantics(
  header: true,
  child: Text(text, style: outfit(size, scale: 1, weight: FontWeight.w600)),
);

/// A panel's description.
Text panelDesc(String text, {double size = 11, double lineHeight = 1.4}) =>
    Text(
      text,
      style: outfit(
        size,
        scale: 1,
        color: HsColors.desc,
        lineHeight: lineHeight,
      ),
    );

/// A mono kicker (`BY GRID SIZE`).
/// A section heading: spoken in sentence case, not spelled out.
Widget kickerText(
  String text, {
  Color color = HsColors.cardKicker,
  double size = 9.5,
  Key? key,
}) => Semantics(
  header: true,
  label: speak(text),
  excludeSemantics: true,
  child: Text(
    text,
    key: key,
    style: plexMono(size, scale: 1, color: color, letterSpacingEm: .16),
  ),
);
