// Every duration the app animates with, and the switch that removes them.
//
// Motion is what the design shows and nothing more (owner, 2026-09-19): a
// cross-fade between screens, the end-of-game card rising in, the settings
// knob sliding, a button dipping while pressed. The phone's "Remove
// animations" setting collapses each to an instant change (#50). The loading
// bar's progress tween is exempt: it reports progress rather than decorating.

import 'package:flutter/widgets.dart';

/// The cross-fade between screens.
const Duration kRouteFade = Duration(milliseconds: 150);

/// The win and out-of-strikes card rising in.
const Duration kCardRise = Duration(milliseconds: 350);

/// The settings switch's knob.
const Duration kToggleSlide = Duration(milliseconds: 120);

/// A design button dimming while pressed.
const Duration kPressDip = Duration(milliseconds: 85);

/// The loading bar easing to each new fraction. Exempt from reduced motion.
const Duration kProgressTween = Duration(milliseconds: 200);

/// The screens' fade: linear.
const Curve kRouteCurve = Curves.linear;

/// The card, the knob and the dip.
const Curve kMotionCurve = Curves.easeOut;

/// [design], or nothing when the phone asks for no animations.
Duration motionDuration(BuildContext context, Duration design) =>
    reducedMotion(context) ? Duration.zero : design;

/// Whether the phone asks for no animations.
bool reducedMotion(BuildContext context) =>
    MediaQuery.maybeDisableAnimationsOf(context) ?? false;
