# Play listing art

Everything the listing uploads except its words (the listing copy is M7's,
#9, and will sit beside these as `listing-copy.md`).

| Asset | Source | Regenerate |
|---|---|---|
| `icon-512.png` | `assets/brand/icon-tile.svg` | `tools/render_icons.sh` (#54) |
| `feature-graphic-1024x500.png` | `assets/brand/feature-graphic.svg` | `tools/render_store_assets.sh` |
| `screenshots/01-menu.png` … `08-howto.png` | `test_driver/store_app.dart`, driven by `test_driver/store_app_test.dart` | `tools/screenshots.sh` |

Both renderers draw with the bundled fonts only (`tools/lib/fonts_check.sh`
refuses otherwise). The feature graphic is written as a 24-bit PNG by
`tools/png_strip_alpha.py`, which drops the alpha channel rsvg-convert
emits; the screenshots go through the same script.

**Play's rules, and how these meet them.**

- Feature graphic: 1024×500, JPEG or 24-bit PNG, no alpha. Ours is a 24-bit
  PNG.
- App icon: 512×512, 32-bit PNG. Ours is RGBA.
- Phone screenshots: 320–3840 px on each side, the long side no more than
  twice the short, 9:16 for recommendation eligibility. Ours are 1080×1920.

`test/guards/store_assets_guard_test.dart` holds every file to those shapes.

**Screenshots.** `tools/screenshots.sh` boots the `sudoku-store` AVD (Nexus
5X profile, 1080×1920 at 420 dpi). The driver target switches the app to immersive
mode, so each capture is the app's own full 1080×1920 surface with no system
bars. It then drives the app through that
target, which uses fixed seeds and a store pre-written with default
settings and a statistics book:

- 9×9 Medium from seed 20260824 (`kStoreSeed9`), three correct entries and a
  hint;
- 16×16 Hard from seed 1 (`kStoreSeed16`, the first seed tried; it
  generated within the ceiling on the store AVD on 2026-09-24);
- Settings with Navy felt selected, then the same game on Paper with a hint;
- statistics, How to play, and the menu last so it offers Continue.

The statistics book is chosen backwards from the captures: the drive itself
starts two games and abandons the first, and the book allows for that.
