#!/usr/bin/env bash
# The quality gate: everything CI will run, in the order CI will run it.
#
# "Green locally" and "green in CI" mean the same thing only if they are the
# same list, so M1's workflow consumes the arrays below rather than restating
# the steps. A step added here is a step CI gains.
#
# Signing: with no HS_* variables the release build falls back to the debug key
# (see android/app/build.gradle.kts), so the gate passes on a fresh clone with
# no secrets. With HS_RELEASE=1 and no secrets it fails at the build step —
# that is intended, and it is how CI proves a release is really signed.
#
# Usage: tools/gate.sh
set -euo pipefail
cd "$(dirname "$0")/.."

LABELS=(
  "resolve dependencies"
  "analyze"
  "check formatting"
  "test (includes the invariant guards)"
  "build release bundle"
  "scan the bundle for permissions"
)

COMMANDS=(
  "flutter pub get --enforce-lockfile"
  "dart analyze --fatal-infos"
  "dart format --output=none --set-exit-if-changed ."
  "flutter test --no-pub"
  "flutter build appbundle --release --no-pub"
  "tools/check_aab.sh"
)

BUNDLE="build/app/outputs/bundle/release/app-release.aab"

# Say which key the bundle will be signed with, so a passing gate never leaves
# the reader guessing whether the artefact is real.
signing_mode() {
  if [ "${HS_RELEASE:-}" = "1" ]; then
    echo "HS_RELEASE=1 — a missing secret is a hard failure"
  elif [ -n "${HS_KEYSTORE_PATH:-}" ] && [ -n "${HS_KEYSTORE_PASS:-}" ] \
    && [ -n "${HS_KEY_ALIAS:-}" ] && [ -n "${HS_KEY_PASS:-}" ]; then
    echo "HS_* set — signing with the upload key"
  else
    echo "debug fallback — no HS_* variables set"
  fi
}

total=${#LABELS[@]}
i=0
while [ "$i" -lt "$total" ]; do
  step=$((i + 1))
  label="${LABELS[$i]}"
  command="${COMMANDS[$i]}"

  if [ "$step" -eq 5 ]; then
    echo "[$step/$total] $label ($(signing_mode))"
  else
    echo "[$step/$total] $label"
  fi

  # Output streams live: a gate that buffers is a gate nobody watches.
  #
  # The status is captured BEFORE any test, not inside `if ! cmd; then $? ...`.
  # In that form `$?` is the status of the negation, which is always 0 — so the
  # gate printed GATE FAILED and exited 0, and CI would have called it a pass.
  status=0
  eval "$command" || status=$?
  if [ "$status" -ne 0 ]; then
    echo "GATE FAILED at $label"
    exit "$status"
  fi
  i=$((i + 1))
done

echo "GATE PASSED $BUNDLE"
