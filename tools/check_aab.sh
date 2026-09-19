#!/usr/bin/env bash
# Scan a built Android App Bundle for declared permissions and confirm its
# package id. Enforces project invariant 1 (CLAUDE.md) on the artefact that
# actually ships, which is the only place a plugin's merged manifest can be
# seen.
#
# The bundle's AndroidManifest.xml is protobuf-encoded, not text XML, so this
# is a byte-string search rather than an XML parse: the permission names and
# the package id survive the encoding intact as printable runs, which is all
# the check needs.
#
# Usage:  tools/check_aab.sh [path/to/app.aab]
# Exit:   0  no permissions declared, package correct
#         1  one or more permissions declared
#         2  package id missing or wrong
#         3  file unreadable, not an .aab, or no manifest entry in the zip
#
# Needs only unzip, tr, grep and sort. Written for bash 3.2 (macOS default).
set -euo pipefail
export LC_ALL=C

# Resolve the default path from the repository root, so the script works from
# anywhere.
cd "$(dirname "$0")/.."

AAB="${1:-build/app/outputs/bundle/release/app-release.aab}"
PACKAGE="com.honestarcade.sudoku"
MANIFEST_ENTRY="base/manifest/AndroidManifest.xml"

case "$AAB" in
  *.aab) ;;
  *) echo "check_aab: $AAB is not an .aab (this scan only understands bundles)" >&2; exit 3 ;;
esac

if [ ! -r "$AAB" ]; then
  echo "check_aab: cannot read $AAB" >&2
  exit 3
fi

# Pre-list rather than trusting `unzip -p` to fail: it prints nothing and exits
# 0 for a missing entry, which would read as "no permissions found".
#
# grep -c, never grep -q: -q exits at the first match, closing the pipe under
# `unzip`, which then dies of SIGPIPE — and with `set -o pipefail` that failure
# becomes the pipeline's. On a bundle this size it is a race, so the check
# passed or failed at random between identical runs. -c reads to the end.
ENTRY_COUNT="$(unzip -Z1 "$AAB" 2>/dev/null | grep -xc "$MANIFEST_ENTRY" || true)"
if [ "${ENTRY_COUNT:-0}" -eq 0 ]; then
  echo "check_aab: $AAB has no $MANIFEST_ENTRY entry" >&2
  exit 3
fi

STRINGS="$(unzip -p "$AAB" "$MANIFEST_ENTRY" 2>/dev/null | tr -c '[:print:]' '\n' || true)"

if [ -z "$STRINGS" ]; then
  echo "check_aab: $MANIFEST_ENTRY in $AAB produced no readable strings" >&2
  exit 3
fi

# What counts as an offender, and why the obvious rule is wrong.
#
# A byte scan cannot see XML structure, and `android.permission.X` appears in a
# manifest for two opposite reasons:
#
#   REQUESTING   <uses-permission android:name="android.permission.INTERNET"/>
#                the app asks Android for a capability.  This is what invariant
#                1 forbids.
#
#   RESTRICTING  <receiver android:permission="android.permission.DUMP">
#                the app refuses to talk to callers who lack DUMP.  This grants
#                the app nothing; it is a lock, not a key.
#
# Every Flutter release build contains exactly one of the second kind, from
# androidx.profileinstaller's ProfileInstallReceiver. So a rule of "fail on any
# android.permission. string" can never pass on any Flutter app, which is why
# the allowlist below exists. It holds one entry, matched exactly. Anything
# else — including a new restriction — fails and forces a human to look.
#
# Also present in every release build: a signature-level permission the app
# declares on ITSELF (<package>.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION), added
# by androidx.core so dynamically-registered receivers are not world-readable.
# It is granted only to this app's own signature, is not an android.permission.*
# and is not shown to users by Play. The bare `permission` run below is that
# element's name.
ALLOWED_RESTRICTION="android.permission.DUMP"

FOUND_PERMS="$(printf '%s\n' "$STRINGS" | grep -o 'android\.permission\.[A-Z_]*' | sort -u || true)"

OFFENDERS=""
ALLOWED_SEEN=""
while IFS= read -r perm; do
  [ -z "$perm" ] && continue
  if [ "$perm" = "$ALLOWED_RESTRICTION" ]; then
    ALLOWED_SEEN="$perm"
  else
    OFFENDERS="$OFFENDERS$perm
"
  fi
done <<EOF
$FOUND_PERMS
EOF

# A bare `uses-permission` run means an element with no readable name — that is
# always suspicious and never allowlisted. A bare `permission` run is the
# self-permission element described above and is expected.
BARE="$(printf '%s\n' "$STRINGS" | grep -x -E 'uses-permission|uses-permission-sdk-23' | sort -u || true)"
if [ -n "$BARE" ]; then
  OFFENDERS="$OFFENDERS$BARE
"
fi

OFFENDERS="$(printf '%s' "$OFFENDERS" | grep -v '^$' | sort -u || true)"

# The package must appear as a whole token: followed by end-of-run or by a
# character that cannot continue an id. `grep -x` was the obvious choice and is
# wrong here — the protobuf packs the next field's bytes straight after the
# string, so the real run reads `com.honestarcade.sudoku"K` and never equals the
# id on its own. This form still rejects the longer scaffold id
# (…sudoku.honest_sudoku), which is what the exact match was for.
# grep -c here too, for the same SIGPIPE reason as the entry check above.
PACKAGE_HITS="$(printf '%s\n' "$STRINGS" | grep -cE "(^|[^.A-Za-z0-9_])${PACKAGE//./\\.}([^.A-Za-z0-9_]|\$)" || true)"
PACKAGE_OK=0
if [ "${PACKAGE_HITS:-0}" -gt 0 ]; then
  PACKAGE_OK=1
fi

# Report everything found before exiting, so one run tells the whole story.
STATUS=0
if [ -n "$OFFENDERS" ]; then
  while IFS= read -r line; do
    [ -n "$line" ] && echo "PERMISSION: $line" >&2
  done <<EOF
$OFFENDERS
EOF
  STATUS=1
fi

if [ "$PACKAGE_OK" -eq 0 ]; then
  echo "PACKAGE MISSING: expected $PACKAGE in $AAB" >&2
  [ "$STATUS" -eq 0 ] && STATUS=2
fi

if [ "$STATUS" -ne 0 ]; then
  exit "$STATUS"
fi

if [ -n "$ALLOWED_SEEN" ]; then
  echo "note: $ALLOWED_SEEN present as a receiver access restriction, not a request (allowlisted)" >&2
fi
echo "no permissions declared (package $PACKAGE)"
