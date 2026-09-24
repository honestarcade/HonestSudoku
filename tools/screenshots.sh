#!/usr/bin/env bash
# Takes the Play listing's eight phone screenshots (#57) on an emulator and
# writes them to ArtSource/store/screenshots/. Not run by CI: it needs an
# emulator, and its output is committed.
#
# Creates the AVD `sudoku-store` (Nexus 5X profile: 1080×1920, 420 dpi) on the
# newest installed google_apis system image if it is absent, boots it, runs
# test_driver/store_app.dart through flutter drive (store_app_test.dart taps
# and captures), strips
# the PNGs' alpha, copies them into place and shuts the emulator down.
#
# Exit: 0 captured, 2 another emulator is running, 3 a tool is missing,
#       4 no google_apis system image is installed, 5 the capture failed.
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"

SDK="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$HOME/Library/Android/sdk}}"
# avdmanager needs a JDK; M0 recorded Homebrew's openjdk@21, which is not on
# PATH (.n8/memory/android-toolchain.md).
if [ -z "${JAVA_HOME:-}" ]; then
  jdk=/opt/homebrew/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home
  [ -x "$jdk/bin/java" ] && export JAVA_HOME="$jdk"
fi
ADB="$SDK/platform-tools/adb"
EMULATOR="$SDK/emulator/emulator"
AVDMANAGER="$(ls "$SDK"/cmdline-tools/*/bin/avdmanager 2>/dev/null | head -1 || true)"
for tool in "$ADB" "$EMULATOR" flutter python3; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "screenshots: $tool is missing" >&2
    exit 3
  fi
done

AVD=sudoku-store
PORT=5580
SERIAL="emulator-$PORT"

if "$ADB" devices | grep -q '^emulator-'; then
  echo "screenshots: another emulator is running; stop it first" >&2
  "$ADB" devices >&2
  exit 2
fi

if ! "$EMULATOR" -list-avds | grep -qx "$AVD"; then
  if [ -z "$AVDMANAGER" ]; then
    echo "screenshots: avdmanager is missing. Install the Android command-line" >&2
    echo "  tools into $SDK/cmdline-tools/latest/ (developer.android.com/studio#command-tools)" >&2
    exit 4
  fi
  # The newest installed google_apis image for this machine's ABI; no
  # preview or extension-level images.
  abi=x86_64
  [ "$(uname -m)" = arm64 ] && abi=arm64-v8a
  image="$(ls -d "$SDK"/system-images/android-[0-9]*/google_apis/"$abi" 2>/dev/null |
    sed -E 's#.*/android-([0-9]+)/.*#\1#' | sort -n | tail -1 || true)"
  if [ -z "$image" ]; then
    echo "screenshots: no google_apis;$abi system image is installed; install" >&2
    echo "  one with sdkmanager \"system-images;android-34;google_apis;$abi\"" >&2
    exit 4
  fi
  echo no | "$AVDMANAGER" create avd -n "$AVD" -d "Nexus 5X" \
    -k "system-images;android-$image;google_apis;$abi" >/dev/null
  cfg="$HOME/.android/avd/$AVD.avd/config.ini"
  {
    echo "hw.gpu.mode=host"
    echo "hw.ramSize=2048"
    echo "hw.keyboard=yes"
  } >>"$cfg"
fi

"$EMULATOR" -avd "$AVD" -port "$PORT" -no-snapshot-load -no-boot-anim \
  -no-audio >"$ROOT/build/screenshots-emulator.log" 2>&1 &
cleanup() { "$ADB" -s "$SERIAL" emu kill >/dev/null 2>&1 || true; }
trap cleanup EXIT

"$ADB" -s "$SERIAL" wait-for-device
for _ in $(seq 1 150); do
  [ "$("$ADB" -s "$SERIAL" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" = 1 ] && break
  sleep 2
done
for scale in window_animation_scale transition_animation_scale animator_duration_scale; do
  "$ADB" -s "$SERIAL" shell settings put global "$scale" 0
done
# SystemUI demo mode: a 9:41 clock, full battery and signal, same every run.
"$ADB" -s "$SERIAL" shell settings put global sysui_demo_allowed 1
"$ADB" -s "$SERIAL" shell am broadcast -a com.android.systemui.demo -e command enter >/dev/null
"$ADB" -s "$SERIAL" shell am broadcast -a com.android.systemui.demo -e command clock -e hhmm 0941 >/dev/null
"$ADB" -s "$SERIAL" shell am broadcast -a com.android.systemui.demo -e command battery -e level 100 -e plugged false >/dev/null
"$ADB" -s "$SERIAL" shell am broadcast -a com.android.systemui.demo -e command network -e wifi show -e level 4 >/dev/null
"$ADB" -s "$SERIAL" shell am broadcast -a com.android.systemui.demo -e command notifications -e visible false >/dev/null

rm -rf "$ROOT/build/store-screenshots"
if ! flutter drive --profile -d "$SERIAL" \
  --driver=test_driver/store_app_test.dart \
  --target=test_driver/store_app.dart; then
  echo "screenshots: the capture failed" >&2
  exit 5
fi

out="$ROOT/ArtSource/store/screenshots"
mkdir -p "$out"
names="01-menu 02-setup 03-board-9x9 04-board-16x16 05-paper-hint 06-stats 07-settings 08-howto"
for name in $names; do
  src="$ROOT/build/store-screenshots/$name.png"
  if [ ! -f "$src" ]; then
    echo "screenshots: $name.png was not taken" >&2
    exit 5
  fi
  cp "$src" "$out/$name.png"
  python3 tools/png_strip_alpha.py "$out/$name.png"
  echo "  $name.png"
done
echo "screenshots: done"
