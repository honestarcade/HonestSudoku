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

SECRETS_DIR="$HOME/HonestArcadeApps/secrets"
KEYSTORE="$SECRETS_DIR/sudoku-upload.keystore"
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
for hs_existing in "$KEYSTORE" "$CREDENTIALS"; do
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

umask 177
# Quoted, because this file documents itself as sourceable. An unquoted value
# containing a space breaks `. this-file`, and one containing a shell
# metacharacter executes on it. The generator produces alphanumerics today, but
# the file is written to be read and edited by a human (#108).
cat > "$CREDENTIALS" <<EOF
# Honest Sudoku upload keystore credentials — MOVE TO YOUR PASSWORD MANAGER,
# then delete this file. Every line is a comment or an export, so this file can
# be sourced directly: \`set -a; . this-file; set +a\`.
export HS_KEYSTORE_PATH="$KEYSTORE"
export HS_KEYSTORE_PASS="$HS_KEYSTORE_PASS"
export HS_KEY_ALIAS="$ALIAS"
export HS_KEY_PASS="$HS_KEYSTORE_PASS"
# NOTE: PKCS12 keystores use ONE password for store and key — HS_KEY_PASS
# equals HS_KEYSTORE_PASS by format design, not by an oversight.
# This file doubles as an env template: source it to build a signed release.
EOF
chmod 600 "$CREDENTIALS"

echo "Created $KEYSTORE"
echo "Created $CREDENTIALS  (chmod 600 — move the password to your password manager and delete it)"
