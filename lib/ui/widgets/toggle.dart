// The settings switch: a 46×26 track, teal when on, with a 20-point knob
// that slides from x 3 to 23 in 120 ms.

import 'package:flutter/widgets.dart';

import '../theme/tokens.dart';

/// A switch.
class Toggle extends StatelessWidget {
  /// Creates a switch.
  const Toggle({
    required this.value,
    required this.onChanged,
    this.semanticsLabel,
    super.key,
  });

  /// On or off.
  final bool value;

  /// Called with the new value.
  final ValueChanged<bool> onChanged;

  /// What a screen reader calls it.
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) => Semantics(
    toggled: value,
    label: semanticsLabel,
    excludeSemantics: true,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => onChanged(!value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        width: 46,
        height: 26,
        decoration: BoxDecoration(
          color: value ? HsColors.teal : HsColors.edge16,
          borderRadius: BorderRadius.circular(13),
        ),
        child: Stack(
          children: [
            AnimatedPositioned(
              duration: const Duration(milliseconds: 120),
              left: value ? 23 : 3,
              top: 3,
              child: Container(
                width: 20,
                height: 20,
                decoration: const BoxDecoration(
                  color: HsColors.white,
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
