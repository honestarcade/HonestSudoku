#!/usr/bin/env bash
# The end-to-end suite on a device (#66): the installed app, nothing stubbed,
# played to a win, set to Paper with a highlight off, a second game left
# part-played, the process killed, and the same binary relaunched with its
# data to prove what came back. Never part of the gate or CI: it needs a
# device.
#
# Usage: tools/e2e.sh <min|phone|serial> [--no-save]
#
# Two `flutter drive` runs of test_driver/app_flow_test.dart against
# test_driver/app_flow.dart: E2E_PHASE=play on a fresh install, then
# `am force-stop`, then E2E_PHASE=restore with --use-application-binary on
# the first run's APK, so the installed app and its files are kept.
#
# The app is uninstalled first, so its store starts empty: that wipes the
# app's data on the device.
#
# --no-save is the persistence step's proof: a debug build given
# HS_DISABLE_SAVE=true runs with no store (lib/ui/app.dart), and the restore
# run must then fail at "relaunch after the kill offers Continue". It exits
# 0 when it does and 1 when anything else happens.
#
# Exit: 0 passed, 1 a step failed, 2 no such device or bad arguments,
#       3 a tool is missing.
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"
export ADB_TAG=e2e
# shellcheck source=tools/lib/android_device.sh
. tools/lib/android_device.sh

APP_ID=com.honestarcade.sudoku
PROOF_STEP="relaunch after the kill offers Continue"

usage() { echo "usage: tools/e2e.sh <min|phone|serial> [--no-save]" >&2; exit 2; }
device=""
nosave=0
for arg in "$@"; do
  case "$arg" in
  --no-save) nosave=1 ;;
  -*) usage ;;
  *) [ -z "$device" ] || usage; device="$arg" ;;
  esac
done
[ -n "$device" ] || {
  echo "e2e: name a device; list them with: $ADB devices" >&2
  usage
}
resolve_device "$device"

mode=profile
defines=()
suffix=""
if [ "$nosave" = 1 ]; then
  suffix=-no-save
  # kSaveDisabled is gated on kDebugMode, so the proof is a debug build.
  mode=debug
  defines=(--dart-define=HS_DISABLE_SAVE=true)
fi
apk="$ROOT/build/app/outputs/flutter-apk/app-$mode.apk"
date="$(date +%Y-%m-%d)"
out="$ROOT/build/e2e"
rm -rf "$out"
mkdir -p "$out"
log="$out/drive.log"
echo "e2e: $DEVICE_NAME ($SERIAL), $mode build${suffix:+, saving disabled}"

"$ADB" -s "$SERIAL" uninstall "$APP_ID" >/dev/null 2>&1 || true

# #66: 30 s for a board on the phone, 60 on sudoku-min and other emulators.
gen_timeout=60
[ "$DEVICE_NAME" != phone ] || gen_timeout=30

start=$(date +%s)
set +e
E2E_PHASE=play E2E_GENERATION_TIMEOUT="$gen_timeout" \
  E2E_SAVED="$out/saved.json" E2E_REPORT="$out/play.json" \
  flutter drive --"$mode" -d "$SERIAL" --keep-app-running ${defines[@]+"${defines[@]}"} \
  --driver=test_driver/app_flow_test.dart \
  --target=test_driver/app_flow.dart 2>&1 | tee "$log"
play=${PIPESTATUS[0]}
set -e
play_s=$(($(date +%s) - start))

restore=1
restore_s=0
if [ "$play" = 0 ]; then
  # The kill: no lifecycle callback runs, so only what the app already
  # wrote survives.
  "$ADB" -s "$SERIAL" shell am force-stop "$APP_ID"
  if [ -n "$("$ADB" -s "$SERIAL" shell pidof "$APP_ID" | tr -d '\r')" ]; then
    echo "e2e: $APP_ID is still running after force-stop" >&2
    exit 1
  fi
  start=$(date +%s)
  set +e
  E2E_PHASE=restore E2E_SAVED="$out/saved.json" E2E_REPORT="$out/restore.json" \
    flutter drive --"$mode" -d "$SERIAL" --use-application-binary="$apk" \
    --driver=test_driver/app_flow_test.dart \
    --target=test_driver/app_flow.dart 2>&1 | tee -a "$log"
  restore=${PIPESTATUS[0]}
  set -e
  restore_s=$(($(date +%s) - start))
fi

report="$ROOT/build/e2e-$DEVICE_NAME-$date$suffix.md"
python3 - "$out" "$DEVICE_NAME" "$SERIAL" "$mode" "$play_s" "$restore_s" \
  >"$report" <<'PY'
import json, pathlib, sys
out, device, serial, mode, play_s, restore_s = sys.argv[1:]
print(f"## End-to-end — {device} ({serial}), {mode} build")
print()
print(f"play {play_s} s, restore {restore_s} s (each includes its build or install)")
print()
print("| phase | step | result | ms |")
print("|---|---|---|---|")
for phase in ("play", "restore"):
    f = pathlib.Path(out, f"{phase}.json")
    if not f.exists():
        print(f"| {phase} | (did not run) | | |")
        continue
    for s in json.loads(f.read_text())["steps"]:
        result = s["result"] + (f": {s['error']}" if "error" in s else "")
        print(f"| {phase} | {s['step']} | {result} | {s.get('ms', '')} |")
PY
cat "$report"

if [ "$nosave" = 1 ]; then
  if [ "$play" = 0 ] && [ "$restore" != 0 ] &&
    grep -q "STEP FAIL  $PROOF_STEP" "$log"; then
    echo "e2e: PROOF HOLDS — with saving disabled the restore failed at \"$PROOF_STEP\""
    exit 0
  fi
  echo "e2e: PROOF FAILED — with saving disabled the run did not fail at \"$PROOF_STEP\"" >&2
  exit 1
fi
if [ "$play" = 0 ] && [ "$restore" = 0 ]; then
  echo "e2e: PASSED on $DEVICE_NAME (play ${play_s} s, restore ${restore_s} s)"
  exit 0
fi
echo "e2e: FAILED on $DEVICE_NAME; see ${log#"$ROOT"/}" >&2
exit 1
