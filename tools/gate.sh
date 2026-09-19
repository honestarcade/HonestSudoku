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
# Deterministic classification. Without this the whitespace rules below behave
# differently in a UTF-8 shell and in the C locale a bare CI runner has — so a
# CI failure could not be reproduced by hand (#106).
export LC_ALL=C
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

SIGNING_VARS=(HS_KEYSTORE_PATH HS_KEYSTORE_PASS HS_KEY_ALIAS HS_KEY_PASS)

# Say which key the bundle will be signed with, so a passing gate never leaves
# the reader guessing whether the artefact is real.
#
# Four states, not three. A PARTLY set environment used to fall through to the
# last branch and print "no HS_* variables set", which was false twice over:
# variables were set, and build.gradle.kts treats any partial set as a hard
# GradleException in every mode. So a contributor who typed HS_KEY_PASSS was
# told they were on the debug fallback one line before the build stopped with
# "HS_KEY_PASS is not set" (#82). The message was wrong exactly where a correct
# one saves the most time — which is why this one names the missing variable.
# Blank, not merely empty. build.gradle.kts decides with Kotlin's
# isNullOrBlank(), which treats whitespace as unset; this used to decide with
# [ -n "$var" ], which does not. For `HS_KEY_PASS=" "` the two disagreed, and
# the disagreement ran the wrong way: the gate announced the upload key, Gradle
# took the debug fallback, the build SUCCEEDED and GATE PASSED was printed over
# a debug-signed bundle (#91). #82 was cosmetic because the gate failed either
# way. This one passed, which is why the two checks must agree exactly.
# Kotlin's Character.isWhitespace, for the ASCII range, exactly.
#
# POSIX [:space:] is space \t \n \v \f \r. Java ALSO counts 0x1C-0x1F, and
# 0x1C is a single ASCII byte that a mangled paste really produces. With four
# of them the gate announced one thing and the build did another, and the gate
# PASSED over a debug-signed bundle (#106).
#
# What this does NOT cover: the multi-byte whitespace Java also counts
# (U+1680, U+2000-U+200A, U+2028, U+2029, U+205F, U+3000). Widening `tr` again
# would be the third narrowing of the same rule. Instead the build itself now
# states which key it used and the gate fails if this prediction disagreed —
# see the step-5 cross-check below. That is the part that cannot drift.
hs_is_blank() {
  [ -z "$(printf '%s' "${1:-}" | tr -d '\011\012\013\014\015\034\035\036\037\040')" ]
}

signing_mode() {
  local set_count=0
  local missing=""
  local name
  for name in "${SIGNING_VARS[@]}"; do
    if hs_is_blank "${!name:-}"; then
      if [ -z "$missing" ]; then missing="$name"; fi
    else
      set_count=$((set_count + 1))
    fi
  done

  if [ "$set_count" -eq "${#SIGNING_VARS[@]}" ]; then
    # Say what the build will do, not what the variables suggest. Promising
    # the upload key while the keystore is missing is the same class of
    # false headline as the blank check above.
    if [ ! -r "${HS_KEYSTORE_PATH}" ]; then
      echo "HS_* set but HS_KEYSTORE_PATH is not readable — the build will fail"
    elif [ "${HS_RELEASE:-}" = "1" ]; then
      echo "HS_* set, HS_RELEASE=1 — signing with the upload key"
    else
      echo "HS_* set — signing with the upload key"
    fi
  elif [ "$set_count" -gt 0 ]; then
    echo "partial — $missing is empty, Gradle will refuse this build"
  elif [ "${HS_RELEASE:-}" = "1" ]; then
    echo "HS_RELEASE=1 with no HS_* variables — Gradle will refuse this build"
  else
    echo "debug fallback — no HS_* variables set"
  fi
}

# Report the mode and stop. The gate's own branches are only assertable if
# something can ask for them without running a six-minute build; leaving them
# unaskable is how the wrong message shipped.
if [ "${1:-}" = "--signing-mode" ]; then
  signing_mode
  exit 0
fi

# Say when the local Flutter is not the one CI pins.
#
# A warning, never a failure: a contributor on a nearby version should be able
# to run the gate, and the only thing that matters is that they know CI will
# use a different one. `.fvmrc` is the single pin `subosito/flutter-action`
# reads, so this compares against the same file rather than a second copy.
#
# Parsed with sed rather than jq, which stock macOS does not have. Either read
# failing is silence, not noise — this is a courtesy line, and a courtesy that
# errors is worse than none.
flutter_pin_warning() {
  local pin local_version
  [ -r .fvmrc ] || return 0
  pin="$(sed -n 's/.*"flutter"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' .fvmrc | head -1)"
  [ -n "$pin" ] || return 0
  local_version="$(flutter --version --machine 2>/dev/null |
    sed -n 's/.*"frameworkVersion"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)"
  [ -n "$local_version" ] || return 0
  if [ "$local_version" != "$pin" ]; then
    echo "note: flutter $local_version differs from .fvmrc pin $pin; CI uses the pin" >&2
  fi
}
flutter_pin_warning

# The path GATE PASSED names must hold THIS run's artefact or nothing, and it
# must do so for the whole run — the removal used to sit at step 5, by which
# time step 4 had already read whatever was there (#108).
rm -f "$BUNDLE"
BUILD_LOG="$(mktemp -t hs-gate-build)"
trap 'rm -f "$BUILD_LOG"' EXIT
SIGNING_MODE=""

# Runs one step as an array of words.
#
# `eval` was the dispatcher, which #17's own discretion forbade in writing
# ("executes each step as an array of words via a function (no `eval`)"). No
# exploit today, since COMMANDS holds literals — but the stated contract is
# that M1's CI consumes this, and there was no function for it to call (#108).
run_step() {
  local -a words
  read -r -a words <<< "$1"
  "${words[@]}"
}

total=${#LABELS[@]}
i=0
while [ "$i" -lt "$total" ]; do
  step=$((i + 1))
  label="${LABELS[$i]}"
  command="${COMMANDS[$i]}"

  if [ "$step" -eq 5 ]; then
    SIGNING_MODE="$(signing_mode)"
    echo "[$step/$total] $label ($SIGNING_MODE)"
  else
    echo "[$step/$total] $label"
  fi

  # Output streams live: a gate that buffers is a gate nobody watches.
  #
  # The status is captured BEFORE any test, not inside `if ! cmd; then $? ...`.
  # In that form `$?` is the status of the negation, which is always 0 — so the
  # gate printed GATE FAILED and exited 0, and CI would have called it a pass.
  status=0
  if [ "$step" -eq 5 ]; then
    # Captured as well as streamed, so the cross-check below can read what
    # Gradle actually said. PIPESTATUS, not $?, because $? here would be tee.
    run_step "$command" 2>&1 | tee "$BUILD_LOG"
    status=${PIPESTATUS[0]}
  else
    run_step "$command" || status=$?
  fi
  if [ "$status" -ne 0 ]; then
    echo "GATE FAILED at $label"
    exit "$status"
  fi

  # The cross-check. `signing_mode` is a prediction; Gradle is the fact. They
  # have drifted apart twice (#91 on ASCII whitespace, #106 on 0x1C and
  # U+3000), each time with the gate announcing the upload key over a
  # debug-signed bundle. A disagreement is now a gate failure.
  if [ "$step" -eq 5 ]; then
    if grep -q "signed with the UPLOAD key" "$BUILD_LOG"; then
      actual="upload"
    elif grep -q "signed with the DEBUG key" "$BUILD_LOG"; then
      actual="debug"
    else
      echo "GATE FAILED at $label: the build said nothing about which key it" >&2
      echo "  used. build.gradle.kts must print one of the two lines this" >&2
      echo "  cross-check reads, or the gate cannot tell you what it built." >&2
      exit 1
    fi
    case "$SIGNING_MODE" in
      *"upload key"*) predicted="upload" ;;
      *) predicted="debug" ;;
    esac
    if [ "$actual" != "$predicted" ]; then
      echo "GATE FAILED at $label: the header said '$SIGNING_MODE'," >&2
      echo "  and Gradle signed with the $actual key. These two decide" >&2
      echo "  'is this variable set' separately and have disagreed before." >&2
      exit 1
    fi
    echo "signing: Gradle used the $actual key (header agreed)"
  fi
  i=$((i + 1))
done

echo "GATE PASSED $BUNDLE"
