#!/usr/bin/env bash
# Creates, and on request boots, the two emulators the device matrix (#61)
# runs on, from two hardware definitions the script writes into
# ~/.android/devices.xml (avdmanager's user device profiles):
#
#   sudoku-min  API 24, google_apis arm64-v8a, 5-inch 720×1280 at 320 dpi —
#               the oldest Android the app claims and the smallest realistic
#               phone. google_apis rather than AOSP, which #61 chose for
#               TalkBack.
#   sudoku-big  the newest installed API, google_apis arm64-v8a, 6.7-inch
#               1080×2400 at 400 dpi — there to tell "small-screen bug" from "bug".
#
# Idempotent: an existing AVD is left alone and reported; devices.xml keeps
# every entry that is not one of these two. Not run by CI: it needs an SDK.
#
# Usage: tools/matrix_avds.sh [--recreate] [--only sudoku-min|sudoku-big]
#        tools/matrix_avds.sh --boot sudoku-min|sudoku-big
#
# Exit: 0 done, 1 bad arguments, 2 no Android SDK, 3 emulator or avdmanager
#       missing, 4 cmdline-tools absent (the install command is printed),
#       5 no matching system image after an install attempt, 6 the boot did
#       not complete within 5 minutes.
set -euo pipefail

usage() {
  echo "usage: tools/matrix_avds.sh [--recreate] [--only sudoku-min|sudoku-big]" >&2
  echo "       tools/matrix_avds.sh --boot sudoku-min|sudoku-big" >&2
  exit 1
}

recreate=0
only=""
boot=""
while [ $# -gt 0 ]; do
  case "$1" in
    --recreate) recreate=1 ;;
    --only)
      [ $# -ge 2 ] || usage
      only="$2"
      shift
      ;;
    --boot)
      [ $# -ge 2 ] || usage
      boot="$2"
      shift
      ;;
    *) usage ;;
  esac
  shift
done
for name in "$only" "$boot"; do
  case "$name" in "" | sudoku-min | sudoku-big) ;; *) usage ;; esac
done

# SDK and JAVA_HOME resolved as tools/screenshots.sh does.
SDK="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$HOME/Library/Android/sdk}}"
# avdmanager needs a JDK; M0 recorded Homebrew's openjdk@21, which is not on
# PATH (.n8/memory/android-toolchain.md).
if [ -z "${JAVA_HOME:-}" ]; then
  jdk=/opt/homebrew/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home
  [ -x "$jdk/bin/java" ] && export JAVA_HOME="$jdk"
fi
if [ ! -d "$SDK" ]; then
  echo "matrix_avds: no Android SDK at $SDK; set ANDROID_HOME" >&2
  exit 2
fi
ADB="$SDK/platform-tools/adb"
EMULATOR="$SDK/emulator/emulator"
ABI=arm64-v8a

# Each AVD boots on its own console port, so its serial is known and it can
# run beside the other scripts' emulators.
port_of() {
  case "$1" in
    sudoku-min) echo 5590 ;;
    sudoku-big) echo 5592 ;;
  esac
}

if [ -n "$boot" ]; then
  for tool in "$ADB" "$EMULATOR"; do
    if [ ! -x "$tool" ]; then
      echo "matrix_avds: $tool is missing" >&2
      exit 3
    fi
  done
  if ! "$EMULATOR" -list-avds | grep -qx "$boot"; then
    echo "matrix_avds: $boot does not exist; run tools/matrix_avds.sh --only $boot" >&2
    exit 1
  fi
  port="$(port_of "$boot")"
  serial="emulator-$port"
  if "$ADB" devices | grep -q "^$serial"; then
    echo "matrix_avds: $boot is already running as $serial"
    exit 0
  fi
  mkdir -p "$(dirname "$0")/../build"
  log="$(cd "$(dirname "$0")/.." && pwd)/build/matrix-$boot.log"
  # A visible window, on purpose: the pass is judged by eye.
  nohup "$EMULATOR" -avd "$boot" -port "$port" -no-snapshot-load \
    -no-boot-anim -no-audio -gpu host -memory 2048 >"$log" 2>&1 &
  echo "matrix_avds: booting $boot as $serial (log: $log)"
  for _ in $(seq 1 150); do
    if [ "$("$ADB" -s "$serial" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" = 1 ]; then
      echo "matrix_avds: $boot booted ($serial)"
      exit 0
    fi
    sleep 2
  done
  echo "matrix_avds: $boot did not finish booting in 5 minutes (log: $log)" >&2
  exit 6
fi

AVDMANAGER="$(ls "$SDK"/cmdline-tools/*/bin/avdmanager 2>/dev/null | head -1 || true)"
SDKMANAGER="$(ls "$SDK"/cmdline-tools/*/bin/sdkmanager 2>/dev/null | head -1 || true)"
if [ -z "$SDKMANAGER" ]; then
  echo "matrix_avds: the Android command-line tools are absent from $SDK/cmdline-tools." >&2
  if [ -x "$SDK/tools/bin/sdkmanager" ]; then
    echo "  Install them with: $SDK/tools/bin/sdkmanager \"cmdline-tools;latest\"" >&2
  else
    echo "  Install them with: brew install --cask android-commandlinetools" >&2
    echo "  and move its cmdline-tools/latest into $SDK/cmdline-tools/latest/, or use" >&2
    echo "  Android Studio > Settings > Android SDK > SDK Tools > Android SDK Command-line Tools." >&2
  fi
  exit 4
fi
for tool in "$EMULATOR" "$AVDMANAGER" "$SDKMANAGER"; do
  if [ -z "$tool" ] || [ ! -x "$tool" ]; then
    echo "matrix_avds: ${tool:-avdmanager or sdkmanager} is missing" >&2
    exit 3
  fi
done
if ! command -v python3 >/dev/null 2>&1; then
  echo "matrix_avds: python3 is missing" >&2
  exit 3
fi

installed_apis() {
  # Stable google_apis images for $ABI only: `android-34`, not
  # `android-34-ext10` or a codename preview.
  "$SDKMANAGER" --list_installed 2>/dev/null |
    sed -nE "s#^ *system-images;android-([0-9]+);google_apis;$ABI .*#\1#p" |
    sort -n -u
}

# Echoes the API a matrix AVD is built on, installing its image if needed.
api_for() {
  local want
  if [ "$1" = sudoku-min ]; then
    want=24
    if ! installed_apis | grep -qx 24; then
      echo "matrix_avds: installing system-images;android-24;google_apis;$ABI" >&2
      yes | "$SDKMANAGER" "system-images;android-24;google_apis;$ABI" >&2 || true
    fi
    if ! installed_apis | grep -qx 24; then
      # No API 24 image to be had: fall back to the lowest installed one,
      # and say so, because the run log must name the floor actually tested.
      want="$(installed_apis | head -1)"
      [ -n "$want" ] && echo "matrix_avds: no API 24 image; sudoku-min falls back to API $want" >&2
    fi
  else
    want="$(installed_apis | tail -1)"
    if [ -z "$want" ]; then
      echo "matrix_avds: installing system-images;android-35;google_apis;$ABI" >&2
      yes | "$SDKMANAGER" "system-images;android-35;google_apis;$ABI" >&2 || true
      want="$(installed_apis | tail -1)"
    fi
  fi
  if [ -z "$want" ]; then
    echo "matrix_avds: no google_apis;$ABI system image is installed, even after" >&2
    echo "  sdkmanager \"system-images;android-24;google_apis;$ABI\"" >&2
    exit 5
  fi
  echo "$want"
}

# Writes the two hardware definitions into devices.xml, replacing any earlier
# copy of them and keeping every other entry.
write_devices() {
  mkdir -p "$HOME/.android"
  python3 - "$HOME/.android/devices.xml" <<'PY'
import re, sys

path = sys.argv[1]
NS = "http://schemas.android.com/sdk/devices/7"


def device(name, diagonal, density, dpi, x, y, ratio):
    return f"""  <d:device>
    <d:name>{name}</d:name>
    <d:id>{name}</d:id>
    <d:manufacturer>Honest Arcade</d:manufacturer>
    <d:hardware>
      <d:screen>
        <d:screen-size>normal</d:screen-size>
        <d:diagonal-length>{diagonal}</d:diagonal-length>
        <d:pixel-density>{density}</d:pixel-density>
        <d:screen-ratio>{ratio}</d:screen-ratio>
        <d:dimensions>
          <d:x-dimension>{x}</d:x-dimension>
          <d:y-dimension>{y}</d:y-dimension>
        </d:dimensions>
        <d:xdpi>{dpi}</d:xdpi>
        <d:ydpi>{dpi}</d:ydpi>
        <d:touch>
          <d:multitouch>jazz-hands</d:multitouch>
          <d:mechanism>finger</d:mechanism>
          <d:screen-type>capacitive</d:screen-type>
        </d:touch>
      </d:screen>
      <d:networking>Wifi</d:networking>
      <d:sensors>Accelerometer</d:sensors>
      <d:mic>false</d:mic>
      <d:keyboard>nokeys</d:keyboard>
      <d:nav>nonav</d:nav>
      <d:ram unit="MiB">2048</d:ram>
      <d:buttons>soft</d:buttons>
      <d:internal-storage unit="GiB">2</d:internal-storage>
      <d:removable-storage unit="MiB"></d:removable-storage>
      <d:cpu>Generic CPU</d:cpu>
      <d:gpu>Generic GPU</d:gpu>
      <d:abi>arm64-v8a</d:abi>
      <d:dock></d:dock>
      <d:power-type>battery</d:power-type>
    </d:hardware>
    <d:software>
      <d:api-level>-</d:api-level>
      <d:live-wallpaper-support>true</d:live-wallpaper-support>
      <d:bluetooth-profiles></d:bluetooth-profiles>
      <d:gl-version>2.0</d:gl-version>
      <d:gl-extensions></d:gl-extensions>
      <d:status-bar>true</d:status-bar>
    </d:software>
    <d:state name="Portrait" default="true">
      <d:description>The phone in portrait view</d:description>
      <d:screen-orientation>port</d:screen-orientation>
      <d:keyboard-state>keyssoft</d:keyboard-state>
      <d:nav-state>navhidden</d:nav-state>
    </d:state>
    <d:state name="Landscape">
      <d:description>The phone in landscape view</d:description>
      <d:screen-orientation>land</d:screen-orientation>
      <d:keyboard-state>keyssoft</d:keyboard-state>
      <d:nav-state>navhidden</d:nav-state>
    </d:state>
  </d:device>
"""


ours = device("sudoku-min", "5.0", "xhdpi", 320, 720, 1280, "long") + device(
    "sudoku-big", "6.7", "400dpi", 400, 1080, 2400, "long"
)
try:
    text = open(path, encoding="utf-8").read()
except FileNotFoundError:
    text = ""
if "</d:devices>" not in text:
    text = (
        '<?xml version="1.0" encoding="utf-8"?>\n'
        f'<d:devices xmlns:d="{NS}" '
        'xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">\n'
        "</d:devices>\n"
    )
text = re.sub(
    r"[ \t]*<d:device\b[^>]*>(?:(?!</d:device>).)*?"
    r"<d:name>sudoku-(?:min|big)</d:name>.*?</d:device>\s*\n?",
    "",
    text,
    flags=re.S,
)
text = text.replace("</d:devices>", ours + "</d:devices>", 1)
open(path, "w", encoding="utf-8").write(text)
PY
}

create() {
  local name="$1" api cfg
  if "$EMULATOR" -list-avds | grep -qx "$name"; then
    if [ "$recreate" = 1 ]; then
      "$AVDMANAGER" delete avd -n "$name" >/dev/null
    else
      echo "matrix_avds: $name already exists; left alone (--recreate rebuilds it)"
      return
    fi
  fi
  api="$(api_for "$name")"
  echo no | "$AVDMANAGER" create avd -n "$name" -d "$name" \
    -k "system-images;android-$api;google_apis;$ABI" >/dev/null
  cfg="$HOME/.android/avd/$name.avd/config.ini"
  # Everything the profile cannot say. vm.heapSize is the per-app Java heap.
  sed -i.bak -E '/^(hw\.gpu\.(mode|enabled)|hw\.ramSize|hw\.sdCard|sdcard\.size|vm\.heapSize|disk\.dataPartition\.size|hw\.keyboard)=/d' "$cfg"
  rm -f "$cfg.bak"
  {
    echo "hw.gpu.enabled=yes"
    echo "hw.gpu.mode=host"
    echo "hw.ramSize=2048"
    echo "vm.heapSize=256"
    echo "hw.sdCard=no"
    echo "disk.dataPartition.size=2G"
    echo "hw.keyboard=no"
  } >>"$cfg"
  echo "matrix_avds: created $name on API $api (system-images;android-$api;google_apis;$ABI)"
}

write_devices
for name in sudoku-min sudoku-big; do
  [ -n "$only" ] && [ "$only" != "$name" ] && continue
  create "$name"
done
