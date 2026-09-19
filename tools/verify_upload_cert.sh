#!/usr/bin/env bash
# Does this bundle carry the key Play has enrolled?
#
# The committed certificate (android/signing/upload_certificate.pem) is the
# public half of the upload key. This compares its SHA-256 fingerprint with the
# one the bundle is actually signed with, which is the only check that catches
# a release signed by the wrong key before Play rejects it.
#
# Specified in #13 "so M1 can reuse it" and never written until #108. M1's
# release job should call this after building and before uploading.
#
# A bundle built with no HS_* variables is signed with the DEBUG key and will
# MISMATCH. That is correct, not a bug — the gate's step 5 says which key it
# used, and this script is for the runs that claim to use the upload key.
#
# Usage: tools/verify_upload_cert.sh [path/to/app.aab]
# Exit:  0  the bundle is signed with the committed certificate
#        1  it is not — the fingerprints are printed
#        2  a required input is missing
#        3  keytool could not be found
set -euo pipefail
export LC_ALL=C
cd "$(dirname "$0")/.."

AAB="${1:-build/app/outputs/bundle/release/app-release.aab}"
# Overridable so the match path is testable without a repository key, and so
# M1 can point it at a certificate fetched from Play App Signing.
PEM="${HS_UPLOAD_CERT:-android/signing/upload_certificate.pem}"
KEYTOOL="${HS_KEYTOOL:-/opt/homebrew/opt/openjdk@21/bin/keytool}"

if [ ! -x "$KEYTOOL" ]; then
  if command -v keytool > /dev/null 2>&1; then
    KEYTOOL="$(command -v keytool)"
  else
    echo "verify_upload_cert: no keytool. Set HS_KEYTOOL to one." >&2
    exit 3
  fi
fi

# `/usr/bin/keytool` on macOS is the same stub as `/usr/bin/java`: it exists,
# it is executable, and it cannot run. Finding it on PATH and believing it is
# the trap `.n8/memory/android-toolchain.md` documents for `java`.
# Captured, not piped: `set -o pipefail` is on, so the stub's non-zero exit
# would make the whole pipeline false even when grep found the message — and
# the check would silently never fire. That is the same shape as the SIGPIPE
# race this project fixed in tools/check_aab.sh.
KEYTOOL_PROBE="$("$KEYTOOL" -help 2>&1 || true)"
case "$KEYTOOL_PROBE" in
*"Unable to locate a Java Runtime"*)
  echo "verify_upload_cert: $KEYTOOL is the macOS stub, not a real keytool." >&2
  echo "  Set HS_KEYTOOL, e.g. /opt/homebrew/opt/openjdk@21/bin/keytool." >&2
  exit 3
  ;;
esac

for required in "$AAB" "$PEM"; do
  if [ ! -r "$required" ]; then
    echo "verify_upload_cert: cannot read $required" >&2
    exit 2
  fi
done

# `keytool -printcert` prints several lines per certificate; the SHA-256 one is
# what Play enrols. -m1 because a bundle may carry a chain.
fingerprint_of() {
  "$KEYTOOL" -printcert "$1" "$2" 2>/dev/null |
    grep -m1 -oE 'SHA256: [0-9A-F:]+' | sed 's/^SHA256: //'
}

BUNDLE_FP="$(fingerprint_of -jarfile "$AAB" || true)"
PEM_FP="$(fingerprint_of -file "$PEM" || true)"

if [ -z "$BUNDLE_FP" ]; then
  echo "verify_upload_cert: $AAB carries no readable signing certificate." >&2
  echo "  An unsigned bundle cannot be uploaded; build it with the HS_* variables set." >&2
  exit 2
fi
if [ -z "$PEM_FP" ]; then
  echo "verify_upload_cert: $PEM is not a readable certificate." >&2
  exit 2
fi

echo "committed certificate: $PEM_FP"
echo "bundle signed with:    $BUNDLE_FP"

if [ "$BUNDLE_FP" = "$PEM_FP" ]; then
  echo "MATCH — this bundle carries the enrolled upload key"
  exit 0
fi

echo "MISMATCH — this bundle is NOT signed with the committed upload key." >&2
echo "  If the build reported the DEBUG key fallback, that is why: set the" >&2
echo "  four HS_* variables. If it reported the upload key, the keystore in" >&2
echo "  use is not the one Play enrolled, and uploading will be rejected." >&2
exit 1
