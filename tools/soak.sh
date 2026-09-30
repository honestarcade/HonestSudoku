#!/usr/bin/env bash
# The engine soak on a device (#65): every supported size and band, seeds
# 1..20 each, timed from request to board, every board checked, the golden
# fingerprints recomputed on the device. Never part of the gate or CI: it
# needs a device.
#
# Usage: tools/soak.sh [--device <min|phone|serial>] [--seeds N]
#
# Runs test_driver/engine_soak.dart under flutter drive --profile, collects
# the one `SOAK {json}` line per pair from `adb logcat -d`, and writes the
# table to build/soak-<device>-<YYYY-MM-DD>.md. --seeds lowers the count for
# a quick look; a table from fewer than 20 seeds says so in its heading and
# is not the #65 measurement.
#
# Exit: 0 every assertion held, 1 any did (after every pair has run),
#       2 no single device, 3 a tool is missing, 5 the drive did not run.
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"
export ADB_TAG=soak
# shellcheck source=tools/lib/android_device.sh
. tools/lib/android_device.sh

# Pairs accepted over the ceiling, as `<shape>:<band>`, comma-separated.
# An entry needs the owner's approval and the measurement beside it (#65).
EXPECTED_EXCEEDANCE=""

device=""
seeds=20
while [ $# -gt 0 ]; do
  case "$1" in
  --device) device="${2:-}"; shift 2 ;;
  --seeds) seeds="${2:-}"; shift 2 ;;
  *) echo "usage: tools/soak.sh [--device <min|phone|serial>] [--seeds N]" >&2; exit 2 ;;
  esac
done
case "$seeds" in '' | *[!0-9]* | 0) echo "soak: --seeds takes a positive integer" >&2; exit 2 ;; esac

resolve_device "$device"
date="$(date +%Y-%m-%d)"
mkdir -p "$ROOT/build"
table="$ROOT/build/soak-$DEVICE_NAME-$date.md"
verdicts="$ROOT/build/soak-$DEVICE_NAME-$date.json"
drivelog="$ROOT/build/soak-$DEVICE_NAME-$date.log"
echo "soak: $DEVICE_NAME ($SERIAL), seeds 1..$seeds"

"$ADB" -s "$SERIAL" logcat -c
start=$(date +%s)
set +e
SOAK_SEEDS="$seeds" SOAK_EXCEED="$EXPECTED_EXCEEDANCE" SOAK_OUT="$verdicts" \
  flutter drive --profile -d "$SERIAL" \
  --driver=test_driver/engine_soak_test.dart \
  --target=test_driver/engine_soak.dart 2>&1 | tee "$drivelog"
drive=${PIPESTATUS[0]}
set -e
seconds=$(($(date +%s) - start))

if [ ! -f "$verdicts" ]; then
  echo "soak: the drive did not run (exit $drive); see $drivelog" >&2
  exit 5
fi

# Read before the pipe: `adb shell` reads stdin, and inside the pipe it
# would swallow the log.
prop() { "$ADB" -s "$SERIAL" shell getprop "$1" </dev/null | tr -d '\r'; }
model="$(prop ro.product.model)"
android="$(prop ro.build.version.release)"
abi="$(prop ro.product.cpu.abi)"
"$ADB" -s "$SERIAL" logcat -d | python3 tools/soak_table.py \
  --device "$DEVICE_NAME" --serial "$SERIAL" --date "$date" \
  --seconds "$seconds" --seeds "$seeds" --verdicts "$verdicts" \
  --model "$model" --android "$android" --abi "$abi" >"$table"
cat "$table"
echo "soak: table written to ${table#"$ROOT"/} (${seconds} s)"
exit $((drive == 0 ? 0 : 1))
