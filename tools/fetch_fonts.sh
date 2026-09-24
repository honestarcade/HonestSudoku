#!/usr/bin/env bash
# Fetches the app's two typefaces from pinned upstream commits (#47).
#
# The fonts ship inside the app and are never downloaded at run time
# (invariant 1); this script is how they got into assets/fonts/, and how a
# later bump is made reproducibly. CI never runs it.
#
#   tools/fetch_fonts.sh           fetch what is missing; verify what is there
#   tools/fetch_fonts.sh --update  re-fetch everything at the pinned commits
#   tools/fetch_fonts.sh --check   verify the recorded hashes, no network
#
# Exit: 0 ok, 1 a hash differs, 2 a tool is missing, 3 the network failed,
#       4 a recorded file is missing or a font file is not recorded.
#
# Bumping a pin is an edit to the two lines below plus --update.
set -euo pipefail
cd "$(dirname "$0")/.."

OUTFIT_REPO="Outfitio/Outfit-Fonts"
OUTFIT_COMMIT="902773808eb372f70fb34e8946dd1ffe604efc79"
OUTFIT_DATE="2023-03-26"  # the commit's date, from the GitHub API on 2026-09-23
PLEX_REPO="google/fonts"
PLEX_COMMIT="b5efa9c32e8f9b63005f5cdb1ad5527a77d2cd04"
PLEX_DATE="2026-09-23"    # the commit's date, from the GitHub API on 2026-09-23

DIR="assets/fonts"
SUMS="$DIR/SHA256SUMS"
SOURCES="$DIR/SOURCES.tsv"

# destination|repo|commit|commit date|upstream path
FILES="
Outfit-Light.ttf|$OUTFIT_REPO|$OUTFIT_COMMIT|$OUTFIT_DATE|fonts/ttf/Outfit-Light.ttf
Outfit-Regular.ttf|$OUTFIT_REPO|$OUTFIT_COMMIT|$OUTFIT_DATE|fonts/ttf/Outfit-Regular.ttf
Outfit-Medium.ttf|$OUTFIT_REPO|$OUTFIT_COMMIT|$OUTFIT_DATE|fonts/ttf/Outfit-Medium.ttf
Outfit-SemiBold.ttf|$OUTFIT_REPO|$OUTFIT_COMMIT|$OUTFIT_DATE|fonts/ttf/Outfit-SemiBold.ttf
Outfit-Bold.ttf|$OUTFIT_REPO|$OUTFIT_COMMIT|$OUTFIT_DATE|fonts/ttf/Outfit-Bold.ttf
OFL-Outfit.txt|$OUTFIT_REPO|$OUTFIT_COMMIT|$OUTFIT_DATE|OFL.txt
IBMPlexMono-Regular.ttf|$PLEX_REPO|$PLEX_COMMIT|$PLEX_DATE|ofl/ibmplexmono/IBMPlexMono-Regular.ttf
IBMPlexMono-Medium.ttf|$PLEX_REPO|$PLEX_COMMIT|$PLEX_DATE|ofl/ibmplexmono/IBMPlexMono-Medium.ttf
IBMPlexMono-SemiBold.ttf|$PLEX_REPO|$PLEX_COMMIT|$PLEX_DATE|ofl/ibmplexmono/IBMPlexMono-SemiBold.ttf
OFL-IBMPlexMono.txt|$PLEX_REPO|$PLEX_COMMIT|$PLEX_DATE|ofl/ibmplexmono/OFL.txt
"

hash_of() {
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | cut -d' ' -f1
  elif command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | cut -d' ' -f1
  else
    echo "fetch_fonts: no shasum or sha256sum" >&2
    exit 2
  fi
}

recorded() {
  [ -f "$SUMS" ] || return 0
  awk -v f="$1" '$2 == f { print $1 }' "$SUMS"
}

check() {
  if [ ! -f "$SUMS" ]; then
    echo "fetch_fonts: $SUMS is missing" >&2
    exit 4
  fi
  local status=0 hash name
  while read -r hash name; do
    [ -n "$name" ] || continue
    if [ ! -f "$DIR/$name" ]; then
      echo "fetch_fonts: $name is recorded but missing" >&2
      exit 4
    fi
    if [ "$(hash_of "$DIR/$name")" != "$hash" ]; then
      echo "fetch_fonts: $name does not match its recorded hash" >&2
      status=1
    fi
  done < "$SUMS"
  local f
  for f in "$DIR"/*.ttf "$DIR"/OFL-*.txt; do
    [ -e "$f" ] || continue
    if [ -z "$(recorded "$(basename "$f")")" ]; then
      echo "fetch_fonts: $(basename "$f") is present but not recorded" >&2
      exit 4
    fi
  done
  [ "$status" -eq 0 ] && echo "fetch_fonts: every file matches its recorded hash"
  exit "$status"
}

case "${1:-}" in
--check) check ;;
--update | "") ;;
*)
  echo "usage: tools/fetch_fonts.sh [--update|--check]" >&2
  exit 2
  ;;
esac
UPDATE=0
[ "${1:-}" = "--update" ] && UPDATE=1

command -v curl >/dev/null 2>&1 || { echo "fetch_fonts: curl is missing" >&2; exit 2; }
mkdir -p "$DIR"
today="$(date -u +%Y-%m-%d)"
new_sums="$(mktemp "${TMPDIR:-/tmp}/fonts-sums.XXXXXX")"
new_sources="$(mktemp "${TMPDIR:-/tmp}/fonts-sources.XXXXXX")"
trap 'rm -f "$new_sums" "$new_sources"' EXIT
printf 'file\trepo\tcommit\tcommitted\tdownloaded\n' > "$new_sources"

echo "$FILES" | while IFS='|' read -r name repo commit committed path; do
  [ -n "$name" ] || continue
  dest="$DIR/$name"
  want="$(recorded "$name")"
  if [ -f "$dest" ] && [ "$UPDATE" -eq 0 ]; then
    have="$(hash_of "$dest")"
    if [ -n "$want" ] && [ "$have" != "$want" ]; then
      echo "fetch_fonts: $name differs from its recorded hash; refusing (use --update)" >&2
      exit 1
    fi
    echo "$have  $name" >> "$new_sums"
    grep "^$name	" "$SOURCES" >> "$new_sources" 2>/dev/null ||
      printf '%s\t%s\t%s\t%s\t%s\n' "$name" "$repo" "$commit" "$committed" "$today" >> "$new_sources"
    continue
  fi
  tmp="$(mktemp "${TMPDIR:-/tmp}/font.XXXXXX")"
  if ! curl -fsSL "https://raw.githubusercontent.com/$repo/$commit/$path" -o "$tmp"; then
    rm -f "$tmp"
    echo "fetch_fonts: could not download $repo/$commit/$path" >&2
    exit 3
  fi
  mv "$tmp" "$dest"
  echo "$(hash_of "$dest")  $name" >> "$new_sums"
  printf '%s\t%s\t%s\t%s\t%s\n' "$name" "$repo" "$commit" "$committed" "$today" >> "$new_sources"
  echo "fetched $name"
done

mv "$new_sums" "$SUMS"
mv "$new_sources" "$SOURCES"
trap - EXIT

# The README's table, between its markers, from SOURCES.tsv and SHA256SUMS.
if [ -f "$DIR/README.md" ]; then
  table="$(mktemp "${TMPDIR:-/tmp}/fonts-table.XXXXXX")"
  {
    echo "<!-- fonts:begin -->"
    echo "| File | Source | Commit | Committed | Downloaded | SHA-256 |"
    echo "|---|---|---|---|---|---|"
    tail -n +2 "$SOURCES" | while IFS='	' read -r name repo commit committed day; do
      printf '| `%s` | %s | `%s` | %s | %s | `%s` |\n' \
        "$name" "$repo" "${commit:0:12}" "$committed" "$day" "$(recorded "$name")"
    done
    echo "<!-- fonts:end -->"
  } > "$table"
  awk -v t="$table" '
    /<!-- fonts:begin -->/ { while ((getline line < t) > 0) print line; skip = 1; next }
    /<!-- fonts:end -->/ { skip = 0; next }
    !skip { print }
  ' "$DIR/README.md" > "$DIR/README.md.new"
  mv "$DIR/README.md.new" "$DIR/README.md"
  rm -f "$table"
fi
echo "fetch_fonts: done"
