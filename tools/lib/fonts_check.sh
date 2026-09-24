# Sourced by tools/render_icons.sh and tools/render_store_assets.sh (#54, #57).
#
# Points rsvg-convert at the bundled fonts and refuses (exit 2) unless it
# really uses them. Two things must hold, and the first alone is not enough:
# fontconfig must resolve Outfit to assets/fonts/, and Pango must ask
# fontconfig at all. On macOS Pango defaults to CoreText and ignores
# fontconfig, so the icons were once rendered in a system font while the
# fc-match probe passed; PANGOCAIRO_BACKEND=fc is the fix, and a render of
# the same word in Outfit and in a family that does not exist must differ.
# Expects ROOT to be the repository root.

for tool in rsvg-convert fc-match python3 cmp; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "fonts: $tool is missing (brew install librsvg fontconfig)" >&2
    exit 3
  fi
done

export FONTCONFIG_FILE="$ROOT/assets/brand/fonts.conf"
export PANGOCAIRO_BACKEND=fc
mkdir -p "$ROOT/build/fontconfig-cache"

resolved="$(fc-match -f '%{file}' Outfit)"
fonts="$(cd "$ROOT/assets/fonts" && pwd -P)"
case "$(cd "$(dirname "$resolved")" 2>/dev/null && pwd -P)/" in
"$fonts"/) ;;
*)
  echo "fonts: Outfit resolves to $resolved, not a file under assets/fonts/" >&2
  echo "  -- run tools/fetch_fonts.sh, and check assets/brand/fonts.conf" >&2
  exit 2
  ;;
esac

probe="$(mktemp -d "${TMPDIR:-/tmp}/fonts-probe.XXXXXX")"
for family in Outfit NoSuchFamilyHere; do
  printf '<svg xmlns="http://www.w3.org/2000/svg" width="240" height="60"><text x="4" y="44" font-family="%s" font-size="40">Sudoku</text></svg>' \
    "$family" >"$probe/$family.svg"
  rsvg-convert "$probe/$family.svg" -o "$probe/$family.png"
done
if cmp -s "$probe/Outfit.png" "$probe/NoSuchFamilyHere.png"; then
  rm -rf "$probe"
  echo "fonts: rsvg-convert draws Outfit exactly like a missing font, so it" >&2
  echo "  is not using assets/fonts/ (is PANGOCAIRO_BACKEND honoured?)" >&2
  exit 2
fi
rm -rf "$probe"
