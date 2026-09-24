// The one button every screen uses: the design's box, colours and radius,
// a slight dip while pressed (the prototype's hover border has no touch
// equivalent), and a hook for a spoken label.

import 'package:flutter/widgets.dart';

import '../board/board_styles.dart';
import '../theme/tokens.dart';

/// The design's recurring button looks.
enum DesignButtonVariant {
  /// Teal fill, deep navy text: Resume, Next puzzle, Start.
  primary(
    ButtonStyleSpec(
      edge: Color(0x00000000),
      bg: HsColors.teal,
      fg: HsColors.deepNavy,
    ),
  ),

  /// Faint fill, light edge, white text: Restart, New puzzle.
  secondary(
    ButtonStyleSpec(
      edge: HsColors.edge18,
      bg: HsColors.fill05,
      fg: HsColors.white,
    ),
  ),

  /// Fainter fill, soft blue text: Rules, Settings.
  soft(
    ButtonStyleSpec(
      edge: HsColors.edge14,
      bg: HsColors.fill04,
      fg: HsColors.chipFg,
    ),
  ),

  /// No fill, muted text: Main menu.
  ghost(
    ButtonStyleSpec(
      edge: Color(0x00000000),
      bg: Color(0x00000000),
      fg: HsColors.muted,
    ),
  ),

  /// Edged card for choices: unselected look.
  outline(
    ButtonStyleSpec(
      edge: HsColors.edge14,
      bg: HsColors.fill04,
      fg: HsColors.toolFg,
    ),
  );

  const DesignButtonVariant(this.spec);

  /// The variant's colours.
  final ButtonStyleSpec spec;
}

/// A design-styled button.
///
/// Its box is whatever its parent and [padding] make it; the whole box is
/// the tap target. A null [onPressed] renders the same and ignores taps.
class DesignButton extends StatefulWidget {
  /// Creates a button with [spec] colours.
  const DesignButton({
    required this.child,
    required this.onPressed,
    required this.spec,
    required this.scale,
    this.radius = 13,
    this.padding = EdgeInsets.zero,
    this.height,
    this.semanticsLabel,
    super.key,
  });

  /// Creates a button in one of the design's recurring looks.
  DesignButton.variant(
    DesignButtonVariant variant, {
    required Widget child,
    required VoidCallback? onPressed,
    required double scale,
    double radius = 13,
    EdgeInsets padding = EdgeInsets.zero,
    double? height,
    String? semanticsLabel,
    Key? key,
  }) : this(
         child: child,
         onPressed: onPressed,
         spec: variant.spec,
         scale: scale,
         radius: radius,
         padding: padding,
         height: height,
         semanticsLabel: semanticsLabel,
         key: key,
       );

  /// The label.
  final Widget child;

  /// Called on tap; null for an inert button.
  final VoidCallback? onPressed;

  /// Colours and opacity.
  final ButtonStyleSpec spec;

  /// Design points to logical pixels.
  final double scale;

  /// Corner radius in design points.
  final double radius;

  /// Inner padding in design points.
  final EdgeInsets padding;

  /// Fixed height in design points, if any.
  final double? height;

  /// What a screen reader says; the child's text when null (M5 fills these).
  final String? semanticsLabel;

  @override
  State<DesignButton> createState() => _DesignButtonState();
}

class _DesignButtonState extends State<DesignButton> {
  var _down = false;

  void _set(bool down) {
    if (_down != down) setState(() => _down = down);
  }

  @override
  Widget build(BuildContext context) {
    final spec = widget.spec;
    final s = widget.scale;
    final enabled = widget.onPressed != null;
    Widget box = Container(
      height: widget.height == null ? null : widget.height! * s,
      padding: widget.padding * s,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: spec.bg,
        borderRadius: BorderRadius.circular(widget.radius * s),
        border: spec.edge.a == 0 ? null : Border.all(color: spec.edge),
      ),
      child: DefaultTextStyle.merge(
        style: TextStyle(color: spec.fg),
        child: widget.child,
      ),
    );
    box = Opacity(opacity: spec.opacity * (_down ? .85 : 1), child: box);
    if (widget.semanticsLabel != null) {
      box = Semantics(
        button: true,
        enabled: enabled,
        label: widget.semanticsLabel,
        excludeSemantics: true,
        child: box,
      );
    }
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onPressed,
      onTapDown: enabled ? (_) => _set(true) : null,
      onTapUp: enabled ? (_) => _set(false) : null,
      onTapCancel: enabled ? () => _set(false) : null,
      child: box,
    );
  }
}
