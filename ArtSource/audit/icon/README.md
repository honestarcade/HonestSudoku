# Launcher icon audit (#54)

Taken 2026-09-24 on the `sudoku-dev` AVD (API 34, Google APIs, Pixel launcher):

- `circle.png`: screenshot of the app drawer. This launcher masks icons to a
  circle; the four corners stay whole inside it.
- `splash.png`: screenshot 0.4 s into a cold start. Android 12+'s splash
  shows the icon on navy; no white frame.

Renders, not screenshots. The API 34 launcher offers no icon-shape switch,
and its themed-icons toggle could not be reached from adb:

- `squircle-render.png`: the committed foreground layer on the tile navy
  under a squircle mask, composited with rsvg-convert.
- `themed-render.png`: the committed monochrome layer, tinted as a themed
  launcher tints it, under a circle mask.
