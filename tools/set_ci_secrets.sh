#!/usr/bin/env bash
# Load the four signing secrets into the repository from the credentials file
# tools/make_upload_key.sh wrote.
#
# It PARSES that file rather than sourcing it, which is a deliberate departure
# from #19's wording. The file executes arbitrary code when sourced (#119,
# open): it is written by an unquoted heredoc with double-quoted values, so a
# password containing `$(` or a backtick runs on `. this-file`, and the value
# it records is the expanded form rather than the one the keystore was made
# with. Building a new happy path on `source` while that is open would be
# adding a second caller to a known defect. Parsing costs three lines and keeps
# working whichever way the quoting is fixed.
#
# Prints the names of the secrets it set. Never a value.
#
# Usage: tools/set_ci_secrets.sh
set -euo pipefail
export LC_ALL=C
cd "$(dirname "$0")/.."

CREDENTIALS="$HOME/HonestArcadeApps/secrets/sudoku-signing-credentials.txt"

command -v gh > /dev/null 2>&1 || {
  echo "set_ci_secrets: gh is not on PATH" >&2
  exit 3
}

[ -r "$CREDENTIALS" ] || {
  echo "set_ci_secrets: cannot read $CREDENTIALS" >&2
  echo "  It is written by tools/make_upload_key.sh and is not in the repository." >&2
  exit 2
}

# Read one `export NAME=value` from the credentials file, without executing it.
# Surrounding quotes are stripped; nothing is expanded.
read_credential() {
  sed -n "s/^[[:space:]]*export[[:space:]]\+$1=//p" "$CREDENTIALS" |
    head -1 |
    sed -e 's/^"\(.*\)"$/\1/' -e "s/^'\(.*\)'$/\1/"
}

KEYSTORE_PATH="$(read_credential HS_KEYSTORE_PATH)"
KEYSTORE_PASS="$(read_credential HS_KEYSTORE_PASS)"
KEY_ALIAS="$(read_credential HS_KEY_ALIAS)"
KEY_PASS="$(read_credential HS_KEY_PASS)"

for pair in "HS_KEYSTORE_PATH:$KEYSTORE_PATH" "HS_KEYSTORE_PASS:$KEYSTORE_PASS" \
  "HS_KEY_ALIAS:$KEY_ALIAS" "HS_KEY_PASS:$KEY_PASS"; do
  name="${pair%%:*}"
  value="${pair#*:}"
  [ -n "$value" ] || {
    echo "set_ci_secrets: $name is missing or empty in $CREDENTIALS" >&2
    exit 2
  }
done

[ -r "$KEYSTORE_PATH" ] || {
  echo "set_ci_secrets: the keystore named in the credentials file is not readable:" >&2
  echo "  $KEYSTORE_PATH" >&2
  exit 2
}

# Base64 on one line: `gh secret set` takes the value on stdin, and a newline
# inside it would survive into the runner's decode.
base64 < "$KEYSTORE_PATH" | tr -d '\n' | gh secret set HS_KEYSTORE_B64
printf '%s' "$KEYSTORE_PASS" | gh secret set HS_KEYSTORE_PASS
printf '%s' "$KEY_ALIAS" | gh secret set HS_KEY_ALIAS
printf '%s' "$KEY_PASS" | gh secret set HS_KEY_PASS

echo "set: HS_KEYSTORE_B64 HS_KEYSTORE_PASS HS_KEY_ALIAS HS_KEY_PASS"
echo "(PLAY_SERVICE_ACCOUNT_JSON is set by tools/setup_play_ci.sh)"
