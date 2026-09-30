# shellcheck shell=bash
# Sourced by tools/soak.sh and tools/e2e.sh (#65, #66).
#
# Resolves the Android SDK and JAVA_HOME the way tools/screenshots.sh does,
# then turns a device argument into one adb serial:
#
#   min       the running emulator whose AVD is `sudoku-min` (#61)
#   phone     the one attached physical device
#   <serial>  that device, as `adb devices` lists it
#   (empty)   the one attached device, whatever it is; refused when several
#
# On success SERIAL holds the serial and DEVICE_NAME a filename-safe name for
# it (the alias, else the AVD name, else the model). A missing or ambiguous
# device exits 2 with the command that lists them. Expects ADB_TAG to name
# the calling script in messages.

SDK="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$HOME/Library/Android/sdk}}"
if [ -z "${JAVA_HOME:-}" ]; then
  jdk=/opt/homebrew/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home
  [ -x "$jdk/bin/java" ] && export JAVA_HOME="$jdk"
fi
ADB="$SDK/platform-tools/adb"
for tool in "$ADB" flutter python3; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "$ADB_TAG: $tool is missing" >&2
    exit 3
  fi
done

# Serials of attached devices in the `device` state, one per line.
_attached() { "$ADB" devices | awk 'NR > 1 && $2 == "device" { print $1 }'; }

_refuse() {
  echo "$ADB_TAG: $1" >&2
  echo "  attached devices ($ADB devices):" >&2
  "$ADB" devices | sed 1d | sed 's/^/    /' >&2
  exit 2
}

# The one line of $1, or nothing when it holds none or several.
_only() { [ "$(printf '%s' "$1" | grep -c .)" = 1 ] && printf '%s' "$1"; }

# resolve_device <alias|serial|empty>
resolve_device() {
  local want="$1" s found=""
  case "$want" in
  min)
    for s in $(_attached); do
      case "$s" in emulator-*)
        [ "$("$ADB" -s "$s" emu avd name 2>/dev/null | head -1 | tr -d '\r')" = sudoku-min ] &&
          found="$found$s"$'\n' ;;
      esac
    done
    SERIAL="$(_only "$found")" ||
      _refuse "no running sudoku-min emulator (boot it with tools/matrix_avds.sh --boot sudoku-min, #61)"
    DEVICE_NAME=sudoku-min
    ;;
  phone)
    for s in $(_attached); do
      case "$s" in emulator-*) ;; *) found="$found$s"$'\n' ;; esac
    done
    SERIAL="$(_only "$found")" || _refuse "expected exactly one physical device"
    DEVICE_NAME=phone
    ;;
  '')
    SERIAL="$(_only "$(_attached)")" ||
      _refuse "expected exactly one attached device; name one"
    DEVICE_NAME=
    ;;
  *)
    _attached | grep -qx -- "$want" || _refuse "$want is not an attached device"
    SERIAL="$want"
    DEVICE_NAME=
    ;;
  esac
  if [ -z "$DEVICE_NAME" ]; then
    case "$SERIAL" in
    emulator-*) DEVICE_NAME="$("$ADB" -s "$SERIAL" emu avd name 2>/dev/null | head -1 | tr -d '\r')" ;;
    esac
    [ -n "$DEVICE_NAME" ] ||
      DEVICE_NAME="$("$ADB" -s "$SERIAL" shell getprop ro.product.model | tr -d '\r')"
    DEVICE_NAME="$(printf '%s' "$DEVICE_NAME" | tr -c 'A-Za-z0-9._-' '-')"
  fi
}
