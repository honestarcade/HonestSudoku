# Brand sources

Vector sources for the launcher icon and the Play Store icon (#54). They are
committed so builds never depend on access to the design project. These are
not app assets: nothing here is bundled.

Provenance: claude.ai/design project `9e9471c9-5231-4fd8-9889-066345073295`,
file `Honest Sudoku.dc.html`, the brand sheet's APP ICON card (dark tile).
The mark and board were copied from its inline SVG on 2026-09-24.

| Source | Feeds | Notes |
|---|---|---|
| `icon-tile.svg` | `ArtSource/store/icon-512.png` | the APP ICON on a full-bleed `#04213F` square; Play applies its own mask |
| `icon-legacy.svg` | `mipmap-*/ic_launcher.png` (48–192 px) | the tile under the design's rounded corner (radius 10.15 of 64), for Android 7 |
| `android-foreground.svg` | `mipmap-*/ic_launcher_foreground.png` (108–432 px) | the adaptive icon's foreground layer; the background is `@color/ic_launcher_background` |
| `android-monochrome.svg` | `mipmap-*/ic_launcher_monochrome.png` (108–432 px) | Android 13 themed icon: corners and the eight thick lines only, white |
| `STUDIO-MARK.svg` | the launcher icon guard | the studio's shared four-corner group (below) |
| `fonts.conf` | `tools/render_icons.sh` | fontconfig limited to `assets/fonts/`, so the digits render in Outfit |

Render with `tools/render_icons.sh`; `tools/render_icons.sh --check` re-renders
into `build/icon-check/` and lists byte differences. It needs `rsvg-convert`
and `fc-match` (Homebrew `librsvg` and `fontconfig`).

**Studio mark.** `STUDIO-MARK.svg` is the corner group copied from Honest Frog
Across's `ArtSource/brand/android-foreground-frog-mint.svg` (sha256
`bad1e3e00147db67a86bfc7d4d6e5fc18c3117b0892fb110bb8abe66b39136a6`, read
2026-09-24). The brand sheet calls it "the same four-corner outline mark as
Honest Chess and Honest Solitaire". Those apps do not exist yet, so Frog
Across, the studio's shipped app, is the comparand.

**Edits from the design SVG.** librsvg ignores `dominant-baseline="central"`,
so each digit carries `dy="0.35em"` instead, which puts the digit's centre on
the cell's centre in Outfit. The mark-and-board group sits between
`mark:begin`/`mark:end` markers, identically in the three coloured sources;
the guard holds them to one copy.

**Safe zone.** In the foreground, the mark's 64-unit box spans 184 of 432 px
(46 of 108 dp), centred. A corner's outer reach on the diagonal is about
0.642 × the box, so the farthest point sits 0.642 × 46 ≈ 29.5 dp from the
centre, inside the 33-dp radius of the 66-dp safe zone that circle masks keep.
