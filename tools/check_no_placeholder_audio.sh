#!/usr/bin/env bash
# Refuses a tree that still carries a synthesised placeholder clip (#63).
#
# The release workflow runs this between the permission scan and the Play
# upload, so a bundle holding a placeholder is never uploaded. It is a script
# rather than inline YAML so the refusal can be proven against a temporary
# tree without a signing key or a tag.
#
# Usage: tools/check_no_placeholder_audio.sh [ROOT]   (default: this repository)
# Exit:  0  no assets/audio/**/placeholder-*.wav under ROOT
#        1  at least one: an ::error:: annotation per file, a summary line,
#           and, under Actions, a "Placeholder audio blocked this release"
#           section in the job summary
set -euo pipefail

root="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
found=""
if [ -d "$root/assets/audio" ]; then
  found=$(cd "$root" && find assets/audio -type f -name 'placeholder-*.wav' | LC_ALL=C sort)
fi

if [ -z "$found" ]; then
  echo "check_no_placeholder_audio: no placeholder audio in assets/audio/"
  exit 0
fi

count=0
listed=""
while IFS= read -r path; do
  count=$((count + 1))
  listed="$listed- $path"$'\n'
  echo "::error file=$path::Placeholder audio cannot ship: $path is a placeholder. Run tools/sfx.py --install to replace it."
done <<< "$found"
echo "check_no_placeholder_audio: $count placeholder clip(s) in assets/audio/; this release is blocked"

if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
  {
    echo "### Placeholder audio blocked this release"
    echo ""
    echo "$count synthesised clip(s) would have shipped; nothing was uploaded."
    echo "Install the licensed clips with tools/sfx.py --install."
    echo ""
    printf '%s' "$listed"
  } >> "$GITHUB_STEP_SUMMARY"
fi
exit 1
