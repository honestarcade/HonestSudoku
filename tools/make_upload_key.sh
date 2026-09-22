#!/usr/bin/env bash
# Generate the Android upload keystore for Honest Sudoku, once.
#
# This key becomes the app's identity. Once Play App Signing is enrolled at the
# first upload, regenerating it does NOT produce an equivalent key — Play will
# refuse bundles signed with anything else, and the only way back is the
# Console's upload-key reset flow. Hence the refusal to overwrite below: the
# most expensive mistake available here is running this twice.
#
# The password comes from the environment, never an argument, so it cannot be
# read out of shell history or a process listing.
#
# Usage:
#   HS_KEYSTORE_PASS='<a long random password>' tools/make_upload_key.sh
#
# Writes (both chmod 600, both outside the repository):
#   ~/HonestArcadeApps/secrets/sudoku-upload.keystore
#   ~/HonestArcadeApps/secrets/sudoku-signing-credentials.txt
set -euo pipefail

# Every relative path below is relative to the repository root, and the
# refusal that protects the committed certificate is only a refusal if it
# looks there: run from anywhere else, CERT_OUT named a file that did not
# exist and the script carried on (#230).
cd "$(dirname "$0")/.."

# Overridable so the round-trip can be tested without touching the owner's
# real secrets directory. #13's discretion specified this for exactly that
# reason and it was never added, which is why the guard fixture has to fake
# $HOME instead (#123).
SECRETS_DIR="${HS_SECRETS_DIR:-$HOME/HonestArcadeApps/secrets}"
KEYSTORE="$SECRETS_DIR/sudoku-upload.keystore"
# Relative to the repository root, which this script cd's to. Overridable so
# the round trip can be tested without writing over the committed one.
CERT_OUT="${HS_UPLOAD_CERT_OUT:-android/signing/upload_certificate.pem}"
CREDENTIALS="$SECRETS_DIR/sudoku-signing-credentials.txt"
ALIAS="upload"
KEYTOOL="${HS_KEYTOOL:-/opt/homebrew/opt/openjdk@21/bin/keytool}"

# Either output existing is a refusal, not just the keystore.
#
# The credentials file is the only record of the generated password until the
# owner moves it into a password manager, and the keystore it unlocks cannot be
# regenerated once Play has enrolled it — so overwriting that file is the one
# irreversible thing this script can do. It used to refuse on the keystore
# alone, which meant a run with the keystore moved aside silently replaced the
# password of a key that still existed (#93).
# The exported certificate is refused too, and this is not hypothetical: it
# defaults to a path relative to the repository root, which this script cd's
# to, so a run with a fake $HOME — which is exactly how the guard suite
# exercises it — wrote a THROWAWAY key's certificate over the committed one.
# The keystore and credentials were protected and the certificate was not
# (#123). A wrong certificate here makes verify_upload_cert.sh fail every
# build, and it is the file Play App Signing enrols.
for hs_existing in "$KEYSTORE" "$CREDENTIALS" "$CERT_OUT"; do
  if [ -e "$hs_existing" ]; then
    echo "make_upload_key: $hs_existing already exists — refusing to overwrite." >&2
    echo "  This key is the app's identity with Play, and the credentials file" >&2
    echo "  is the only copy of its password until you move it to a password" >&2
    echo "  manager. If you genuinely need a new key, use the Play Console's" >&2
    echo "  upload-key reset flow and move BOTH files aside deliberately." >&2
    exit 2
  fi
done

if [ -z "${HS_KEYSTORE_PASS:-}" ]; then
  echo "make_upload_key: set HS_KEYSTORE_PASS in the environment." >&2
  echo "  Passed as an argument it would land in your shell history." >&2
  exit 2
fi

# A minimum length, because the leak scan depends on one.
#
# The scan searches TRANSFORMED forms of a secret — base64, rot13, reversed,
# the first and last eight characters — only for values of eight characters or
# more. Below that a lowercased four-letter password is four ordinary letters
# and matches English prose, so the transforms were producing false failures
# (#208). Raising the floor fixed that and opened a hole in the same motion: a
# genuinely short password would then be searched verbatim only, and a
# base64'd copy of it in a job summary would not be found (#220).
#
# PKCS12 and keytool accept six. This makes the guard's assumption true at the
# only place a keystore is created, so the threshold is a guarantee rather
# than a blind spot.
if [ "${#HS_KEYSTORE_PASS}" -lt 12 ]; then
  echo "make_upload_key: HS_KEYSTORE_PASS is ${#HS_KEYSTORE_PASS} characters; 12 is the minimum." >&2
  echo "  This is an upload key that signs every release; a short password is" >&2
  echo "  also one the leak scan can only search for verbatim (#220)." >&2
  exit 2
fi

if [ ! -x "$KEYTOOL" ]; then
  echo "make_upload_key: no keytool at $KEYTOOL" >&2
  echo "  Override with HS_KEYTOOL=/path/to/keytool (the macOS /usr/bin/java" >&2
  echo "  stub is not a JDK; this project uses Homebrew openjdk@21)." >&2
  exit 3
fi

mkdir -p "$SECRETS_DIR"
chmod 700 "$SECRETS_DIR"

# PKCS12 is the modern default and takes one password for both the store and
# the key; -storepass:env keeps it off the command line.
"$KEYTOOL" -genkeypair \
  -storetype PKCS12 \
  -keystore "$KEYSTORE" \
  -alias "$ALIAS" \
  -keyalg RSA \
  -keysize 2048 \
  -sigalg SHA256withRSA \
  -validity 10000 \
  -dname "O=Honest Arcade, CN=Honest Sudoku" \
  -storepass:env HS_KEYSTORE_PASS \
  -keypass:env HS_KEYSTORE_PASS

chmod 600 "$KEYSTORE"

# Export the public certificate and print its fingerprint.
#
# Without this, a rotation that follows the runbook produced a new keystore
# and left `android/signing/upload_certificate.pem` describing the OLD key —
# so `tools/verify_upload_cert.sh` would fail every build afterwards, and the
# reason would not be obvious (#123). The certificate is the public half; it
# is written into the repository on purpose.
mkdir -p "$(dirname "$CERT_OUT")"
"$KEYTOOL" -exportcert -rfc \
  -keystore "$KEYSTORE" \
  -storetype PKCS12 \
  -alias "$ALIAS" \
  -storepass:env HS_KEYSTORE_PASS \
  -file "$CERT_OUT"
chmod 644 "$CERT_OUT"

FINGERPRINT="$("$KEYTOOL" -printcert -file "$CERT_OUT" |
  grep -m1 -oE 'SHA256: [0-9A-F:]+' | sed 's/^SHA256: //')"
echo "certificate written to $CERT_OUT"
echo "  alias:   $ALIAS"
echo "  SHA-256: ${FINGERPRINT:-unknown}"
echo "  Commit it, and update the table in android/signing/README.md."

umask 177

# Escape the four characters that are still live inside double quotes.
#
# #108 wrapped these values in double quotes, which stops a space and a
# semicolon and does NOT stop command substitution. The file is written by a
# heredoc, so `$(...)` and a backtick expanded when it was written AND again
# when it was sourced: the password recorded was the expanded form, 8
# characters where the keystore was made with 143, and it did not open the
# keystore (#119). A password containing `"` truncated the value the same way.
#
# printf with %s writes the value literally — no heredoc expansion — and the
# escaping keeps it inert if anyone sources the file anyway. The escape order
# matters: backslash first, or it doubles the backslashes the others add.
escape_for_double_quotes() {
  printf '%s' "$1" |
    sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' -e 's/\$/\\$/g' -e 's/`/\\`/g'
}

{
  printf '%s\n' \
    '# Honest Sudoku upload keystore credentials — MOVE TO YOUR PASSWORD MANAGER,' \
    '# then delete this file.' \
    '#' \
    '# Do NOT source this file. tools/set_ci_secrets.sh PARSES it instead. The' \
    '# values are double-quoted with the shell-special characters escaped, so a' \
    '# dot-source is inert — but parsing is the supported path and the only one' \
    '# that is tested (#119).'
  printf 'export HS_KEYSTORE_PATH="%s"\n' "$(escape_for_double_quotes "$KEYSTORE")"
  printf 'export HS_KEYSTORE_PASS="%s"\n' "$(escape_for_double_quotes "$HS_KEYSTORE_PASS")"
  printf 'export HS_KEY_ALIAS="%s"\n' "$(escape_for_double_quotes "$ALIAS")"
  printf 'export HS_KEY_PASS="%s"\n' "$(escape_for_double_quotes "$HS_KEYSTORE_PASS")"
  printf '%s\n' \
    '# NOTE: PKCS12 keystores use ONE password for store and key — HS_KEY_PASS' \
    '# equals HS_KEYSTORE_PASS by format design, not by an oversight.'
} > "$CREDENTIALS"
chmod 600 "$CREDENTIALS"

echo "Created $KEYSTORE"
echo "Created $CREDENTIALS  (chmod 600 — move the password to your password manager and delete it)"
