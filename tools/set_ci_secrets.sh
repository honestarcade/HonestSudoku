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

# Named, not inferred. `gh` otherwise resolves the repository from `git remote`,
# so running this from a fork clone — or a worktree whose origin was repointed —
# uploads the real upload keystore and its password to somebody else's
# repository secrets, silently (#134).
REPO="honestarcade/HonestSudoku"

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
#
# Carriage returns are stripped first, and trailing whitespace outside the
# quotes is dropped, because both used to defeat the `$`-anchored quote strip
# and leave the literal quote characters inside the secret — a wrong password
# uploaded with no error, surfacing much later as a red release build (#126).
# Inside double quotes the three shell escapes are unescaped; inside single
# quotes nothing is. Nothing is ever expanded or executed.
read_credential() {
  tr -d '\r' < "$CREDENTIALS" |
    sed -n "s/^[[:space:]]*export[[:space:]][[:space:]]*$1=//p" |
    head -1 |
    awk '{
      line = $0
      if (substr(line, 1, 1) == "\"") {
        # Scan to the matching quote, unescaping the four characters that are
        # live inside double quotes — the same four make_upload_key.sh escapes
        # when it writes the file (#119), so the round trip is exact.
        # quote survives. Everything after it — a comment, stray spaces — is
        # not part of the value. Anchoring the strip to end-of-line instead
        # meant `export HS_KEY_PASS="pw" # note` uploaded the quotes and the
        # comment as the password, silently (#143).
        out = ""
        for (i = 2; i <= length(line); i++) {
          c = substr(line, i, 1)
          if (c == "\\" && i < length(line)) {
            n = substr(line, i + 1, 1)
            if (n == "\"" || n == "$" || n == "\\" || n == "`") { out = out n; i++; continue }
            out = out c; continue
          }
          if (c == "\"") break
          out = out c
        }
        print out
      } else if (substr(line, 1, 1) == "\047") {
        out = ""
        for (i = 2; i <= length(line); i++) {
          c = substr(line, i, 1)
          if (c == "\047") break
          out = out c
        }
        print out
      } else {
        # Unquoted: a `#` after whitespace starts a comment, as in a shell.
        sub(/[[:space:]]+#.*$/, "", line)
        sub(/[[:space:]]+$/, "", line)
        print line
      }
    }'
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

# PKCS12 keystores have exactly one password: keytool prints "Different store
# and key passwords not supported for PKCS12 KeyStores. Ignoring user-specified
# -keypass value" and exits 0 whatever `-keypass` says. So a `-keypass` check
# cannot fail, and HS_KEY_PASS was verified nowhere — it passed the parser, the
# pre-flight, play-api-check and release.yml's keystore_check, and failed four
# minutes into the Gradle build (#143). Asserting the two are equal is the only
# honest check available, and it is the truth for a keystore this project made.
[ "$KEY_PASS" = "$KEYSTORE_PASS" ] || {
  echo "set_ci_secrets: HS_KEY_PASS differs from HS_KEYSTORE_PASS." >&2
  echo "  A PKCS12 keystore has one password; keytool ignores a separate key" >&2
  echo "  password, so a mismatch here cannot be caught later and would fail" >&2
  echo "  the release build instead. Check $CREDENTIALS." >&2
  exit 2
}

[ -r "$KEYSTORE_PATH" ] || {
  echo "set_ci_secrets: the keystore named in the credentials file is not readable:" >&2
  echo "  $KEYSTORE_PATH" >&2
  exit 2
}

# Pre-flight: prove the parsed password and alias actually open the keystore
# before any of it leaves this machine. Without this, a mis-parsed value is
# uploaded happily and only fails minutes into a release build, where the cause
# is invisible (#126). `-storepass:env` keeps the password off the command line
# and out of the process table.
#
# Resolving keytool is the same dance as tools/verify_upload_cert.sh, and for
# the same reason: `/usr/bin/keytool` on macOS is a stub that exists, is
# executable, and cannot run. Trusting `command -v` here would make the
# pre-flight refuse every correct credentials file on the owner's own machine.
KEYTOOL="${HS_KEYTOOL:-/opt/homebrew/opt/openjdk@21/bin/keytool}"
if [ ! -x "$KEYTOOL" ] && command -v keytool > /dev/null 2>&1; then
  KEYTOOL="$(command -v keytool)"
fi
KEYTOOL_PROBE=""
[ -x "$KEYTOOL" ] && KEYTOOL_PROBE="$("$KEYTOOL" -help 2>&1 || true)"
case "${KEYTOOL_PROBE:-none}" in
none | *"Unable to locate a Java Runtime"*)
  echo "set_ci_secrets: no usable keytool, so the keystore pre-flight is SKIPPED." >&2
  echo "  Set HS_KEYTOOL to a real one to have the password checked before upload." >&2
  ;;
*)
  HS_PASS_PROBE="$KEYSTORE_PASS" "$KEYTOOL" -list \
    -keystore "$KEYSTORE_PATH" \
    -storetype PKCS12 \
    -storepass:env HS_PASS_PROBE \
    -alias "$KEY_ALIAS" > /dev/null 2>&1 || {
    echo "set_ci_secrets: the parsed password and alias do not open the keystore." >&2
    echo "  Nothing was uploaded. Check $CREDENTIALS for stray quoting," >&2
    echo "  a carriage return, or an alias that is not the one in the keystore." >&2
    exit 2
  }
  ;;
esac

# Base64 on one line: `gh secret set` takes the value on stdin, and a newline
# inside it would survive into the runner's decode.
base64 < "$KEYSTORE_PATH" | tr -d '\n' | gh secret set HS_KEYSTORE_B64 -R "$REPO"
printf '%s' "$KEYSTORE_PASS" | gh secret set HS_KEYSTORE_PASS -R "$REPO"
printf '%s' "$KEY_ALIAS" | gh secret set HS_KEY_ALIAS -R "$REPO"
printf '%s' "$KEY_PASS" | gh secret set HS_KEY_PASS -R "$REPO"

echo "set: HS_KEYSTORE_B64 HS_KEYSTORE_PASS HS_KEY_ALIAS HS_KEY_PASS"
echo "  in $REPO"
echo "(PLAY_SERVICE_ACCOUNT_JSON is set by tools/setup_play_ci.sh)"
