#!/usr/bin/env bash
# Run check_aab.sh against the exact bundle a release run uploaded, downloaded
# from that run's Actions artifact rather than rebuilt, so a permission that
# only the release path introduces is caught (#59).
#
# Usage:  tools/verify_release_artifact.sh <run-id> [--keep]
# Exit:   check_aab.sh's own code on the downloaded bundle, or
#         4  usage error, download failed, not exactly one .aab found, or
#            its sha256 differs from the one the run recorded
#
# Stages into build/release-artifact/<run-id>/ and deletes it afterwards
# unless --keep is given. Needs gh (authenticated), shasum and check_aab.sh's
# own tools.
set -euo pipefail

cd "$(dirname "$0")/.."

if [ $# -lt 1 ] || [ $# -gt 2 ]; then
  echo "usage: tools/verify_release_artifact.sh <run-id> [--keep]" >&2
  exit 4
fi
RUN_ID="$1"
KEEP=""
if [ $# -eq 2 ]; then
  [ "$2" = "--keep" ] || { echo "unknown option: $2" >&2; exit 4; }
  KEEP=1
fi
case "$RUN_ID" in
  ''|*[!0-9]*) echo "run id must be a number: $RUN_ID" >&2; exit 4 ;;
esac

STAGE="build/release-artifact/$RUN_ID"
rm -rf "$STAGE"
mkdir -p "$STAGE"
cleanup() { [ -n "$KEEP" ] || rm -rf "$STAGE"; }
trap cleanup EXIT

if ! gh run download "$RUN_ID" --dir "$STAGE"; then
  echo "could not download the artifacts of run $RUN_ID" >&2
  exit 4
fi

AABS=()
while IFS= read -r f; do AABS+=("$f"); done < <(find "$STAGE" -name '*.aab' -type f)
if [ "${#AABS[@]}" -ne 1 ]; then
  echo "expected exactly one .aab in run $RUN_ID's artifacts, found ${#AABS[@]}" >&2
  exit 4
fi
AAB="${AABS[0]}"

echo "artifact: ${AAB#"$STAGE"/}"
echo "size:     $(wc -c < "$AAB" | tr -d ' ') bytes"
SUM="$(shasum -a 256 "$AAB" | awk '{print $1}')"
echo "sha256:   $SUM"
# The release job writes the digest it computed beside the bundle; a mismatch
# means the file checked here is not the one the run uploaded to Play.
if [ -f "$AAB.sha256" ]; then
  RECORDED="$(awk '{print $1; exit}' "$AAB.sha256")"
  if [ "$RECORDED" != "$SUM" ]; then
    echo "sha256 mismatch: the run recorded $RECORDED" >&2
    exit 4
  fi
  echo "sha256 matches the run's own record"
fi

set +e
tools/check_aab.sh "$AAB"
rc=$?
set -e
exit "$rc"
