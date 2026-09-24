// The settings switch: a 46×26 track, teal when on, with a 20-point knob
// that slides from x 3 to 23 (kToggleSlide).

import 'package:flutter/widgets.dart';

import '../motion.dart';
import '../theme/tokens.dart';
import 'tap_target.dart';

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
  Widget build(BuildContext context) => TapTarget(
    child: Semantics(
      toggled: value,
      label: semanticsLabel,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => onChanged(!value),
        child: AnimatedContainer(
          duration: motionDuration(context, kToggleSlide),
          curve: kMotionCurve,
          width: 46,
          height: 26,
          decoration: BoxDecoration(
            color: value ? HsColors.teal : HsColors.edge16,
            borderRadius: BorderRadius.circular(13),
          ),
          child: Stack(
            children: [
              AnimatedPositioned(
                duration: motionDuration(context, kToggleSlide),
                curve: kMotionCurve,
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
    ),
  );
}
