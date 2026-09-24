#!/usr/bin/env bash
# Renders the Play feature graphic from assets/brand/feature-graphic.svg
# (#57) in the bundled fonts, as a 24-bit PNG: Play refuses alpha on it.
# The phone screenshots come from tools/screenshots.sh; the 512-px icon from
# tools/render_icons.sh.
#
#   tools/render_store_assets.sh           render into ArtSource/store/
#   tools/render_store_assets.sh --check   render into build/store-check/ and
#                                          list byte differences (exit 0)
#
# Exit: 0 rendered, 2 rsvg-convert would not draw with assets/fonts/, 3 a
#       tool is missing, 5 the output's size or type is wrong.
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"

# shellcheck source=tools/lib/fonts_check.sh
. "$ROOT/tools/lib/fonts_check.sh"

OUT="$ROOT/ArtSource/store"
CHECK=0
if [ "${1:-}" = "--check" ]; then
  CHECK=1
  OUT="$ROOT/build/store-check"
  rm -rf "$OUT"
fi
mkdir -p "$OUT"

png="$OUT/feature-graphic-1024x500.png"
rsvg-convert -w 1024 -h 500 assets/brand/feature-graphic.svg -o "$png"
python3 tools/png_strip_alpha.py "$png"
python3 - "$png" <<'PY' || exit 5
import struct, sys
data = open(sys.argv[1], "rb").read(26)
w, h = struct.unpack(">II", data[16:24])
if data[:8] != b"\x89PNG\r\n\x1a\n" or (w, h) != (1024, 500) or data[25] != 2:
    sys.exit(f"render_store_assets: {sys.argv[1]} is {w}x{h} type {data[25]}")
PY
echo "  feature-graphic-1024x500.png (1024x500, 24-bit)"

if [ "$CHECK" -eq 1 ]; then
  cmp -s "$png" "$ROOT/ArtSource/store/feature-graphic-1024x500.png" ||
    echo "differs: ArtSource/store/feature-graphic-1024x500.png"
fi
echo "render_store_assets: done"
