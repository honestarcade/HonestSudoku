---
name: accessibility
description: The tap-target exemption for grid cells, how spoken labels are built, and which guideline tests to run
metadata:
  type: project
---

# Accessibility conventions (#51, #52, #56)

- **The one tap-target exemption:** grid cells. A 16×16 cell is 22 design
  points and cannot be 48 dp on a phone. Cell nodes carry `kGridCellTag`
  (`lib/ui/a11y/labels.dart`), and `HonestTapTargetGuideline`
  (`test/ui/a11y/honest_tap_target_guideline.dart`) skips exactly that tag;
  its own test proves a 40-dp button still fails.
- **48 dp without moving the design:** `TapTarget` grows a control's hit
  area and semantics rect around its painted box; `TapTargetGroup` at a
  component's root lets a hit in a grown margin reach the control. The board's
  pad, tools and top bar are grouped; links are exempt and carry neither.
- **Labels:** board phrases come from `lib/ui/a11y/labels.dart`; visible text
  elsewhere goes through `speak()` (`lib/ui/a11y/speak.dart`): `×` is "by", `·`
  a comma, `m:ss` words, CSS-uppercase text sentence case, `—` "none yet".
- **Contrast:** text colours are held to 4.5:1 by
  `test/ui/theme/token_contrast_test.dart` (guard); a failing design colour is
  nudged by `contrast.dart`'s rule and recorded in `tokens.dart`'s header.
- **Run:** `flutter test test/ui/a11y test/ui/board/semantics_test.dart
  test/ui/screens/screens_semantics_test.dart test/ui/theme`.
