#!/usr/bin/env bash
# Create the Google Cloud project, service account and key that let CI talk to
# the Play Developer API, and load the key into the repository secret.
#
# Idempotent: every step checks for what it would create and skips it, so a
# re-run after a partial failure finishes the job rather than erroring or
# duplicating. The key is written with umask 077, uploaded, and deleted in the
# same run — it is never left on disk and never printed.
#
# A separate Cloud project per app, matching Frog Across's, so revoking one
# app's automation never touches the other.
#
# Needs the owner's `gcloud` login. Everything after that is automated; if this
# refuses for want of a login, log in and run it again rather than doing any of
# it by hand.
#
# Usage: tools/setup_play_ci.sh
set -euo pipefail
export LC_ALL=C
cd "$(dirname "$0")/.."

PROJECT="honestsudoku-ci"
SA_NAME="sudoku-ci"
SA_EMAIL="$SA_NAME@$PROJECT.iam.gserviceaccount.com"
KEY_PATH="$HOME/HonestArcadeApps/secrets/honestsudoku-ci.json"
SECRET="PLAY_SERVICE_ACCOUNT_JSON"
# Named, not inferred, for the reason in tools/set_ci_secrets.sh: `gh` resolves
# the repository from `git remote`, so a fork clone would receive the key (#134).
REPO="honestarcade/HonestSudoku"

need() {
  command -v "$1" > /dev/null 2>&1 || {
    echo "setup_play_ci: $1 is not on PATH" >&2
    exit 3
  }
}
need gcloud
need gh

ACTIVE_ACCOUNT="$(gcloud auth list --filter=status:ACTIVE --format='value(account)' 2> /dev/null | head -1)"
if [ -z "$ACTIVE_ACCOUNT" ]; then
  echo "setup_play_ci: no active gcloud login." >&2
  echo "  Run: gcloud auth login" >&2
  echo "  Then run this script again; nothing here needs doing by hand." >&2
  exit 4
fi

# Which account matters: this creates a Cloud project and a service account, and
# the wrong active login puts them under the wrong Google account with no
# obvious symptom (#134). The script cannot know which account is the Play
# Console owner, so it names the one it found and asks, rather than guessing.
# HS_PLAY_ACCOUNT skips the prompt for a re-run or a non-interactive shell.
if [ -n "${HS_PLAY_ACCOUNT:-}" ]; then
  if [ "$HS_PLAY_ACCOUNT" != "$ACTIVE_ACCOUNT" ]; then
    echo "setup_play_ci: active gcloud account is $ACTIVE_ACCOUNT," >&2
    echo "  but HS_PLAY_ACCOUNT says $HS_PLAY_ACCOUNT. Refusing." >&2
    exit 4
  fi
elif [ -t 0 ]; then
  echo "This will create Cloud resources under: $ACTIVE_ACCOUNT"
  printf 'Is that the Play Console owner account? [y/N] '
  read -r reply
  case "$reply" in
  y | Y | yes | YES) ;;
  *)
    echo "setup_play_ci: stopped. Run gcloud auth login with the right account," >&2
    echo "  or set HS_PLAY_ACCOUNT to confirm non-interactively." >&2
    exit 4
    ;;
  esac
else
  echo "setup_play_ci: no terminal to confirm the account on." >&2
  echo "  Active account is $ACTIVE_ACCOUNT; set HS_PLAY_ACCOUNT to it to proceed." >&2
  exit 4
fi

step() { echo "==> $1"; }

step "project $PROJECT"
if gcloud projects describe "$PROJECT" > /dev/null 2>&1; then
  echo "    exists, skipping"
else
  gcloud projects create "$PROJECT" --name="Honest Sudoku CI" --quiet
fi

step "androidpublisher API"
if gcloud services list --enabled --project "$PROJECT" --format='value(config.name)' 2> /dev/null |
  grep -q '^androidpublisher\.googleapis\.com$'; then
  echo "    already enabled, skipping"
else
  gcloud services enable androidpublisher.googleapis.com --project "$PROJECT" --quiet
fi

step "service account $SA_EMAIL"
if gcloud iam service-accounts describe "$SA_EMAIL" --project "$PROJECT" > /dev/null 2>&1; then
  echo "    exists, skipping"
else
  # No IAM roles, deliberately. Play access is granted in the Play Console, not
  # in Cloud IAM, and a role here would be authority nobody needs.
  gcloud iam service-accounts create "$SA_NAME" \
    --project "$PROJECT" \
    --display-name "Honest Sudoku CI" \
    --quiet
fi

step "repository secret $SECRET"
if gh secret list -R "$REPO" --json name --jq '.[].name' 2> /dev/null | grep -qx "$SECRET"; then
  echo "    already set, skipping (delete it first to rotate)"
else
  mkdir -p "$(dirname "$KEY_PATH")"
  chmod 700 "$(dirname "$KEY_PATH")"
  umask 077

  # The key is deleted however this exits. Without the trap, a failed upload
  # left a live private key sitting in the secrets directory, and because
  # idempotence keys off `gh secret list`, the next run minted a second one
  # (#134). A trap is the only form that survives `set -e`.
  cleanup_key() { rm -f "$KEY_PATH"; }
  trap cleanup_key EXIT INT TERM

  # An existing key file means a previous run died between creation and upload.
  # Reusing it would upload a key whose fate we cannot vouch for; deleting it
  # here is the same thing the trap would have done.
  [ -e "$KEY_PATH" ] && rm -f "$KEY_PATH"

  EXISTING_KEYS="$(gcloud iam service-accounts keys list \
    --iam-account "$SA_EMAIL" --project "$PROJECT" \
    --managed-by user --format='value(name)' 2> /dev/null | grep -c . || true)"
  if [ "${EXISTING_KEYS:-0}" -gt 0 ]; then
    echo "    note: $EXISTING_KEYS user-managed key(s) already exist on this" >&2
    echo "    service account. A new one is being added, not replacing them." >&2
    echo "    List:   gcloud iam service-accounts keys list --iam-account $SA_EMAIL" >&2
    echo "    Delete: gcloud iam service-accounts keys delete <id> --iam-account $SA_EMAIL" >&2
  fi

  gcloud iam service-accounts keys create "$KEY_PATH" \
    --iam-account "$SA_EMAIL" --project "$PROJECT" --quiet
  KEY_ID="$(sed -n 's/.*"private_key_id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$KEY_PATH" | head -1)"
  gh secret set "$SECRET" -R "$REPO" < "$KEY_PATH"
  cleanup_key
  trap - EXIT INT TERM
  echo "    set in $REPO from a key that has been deleted from disk"
  # The id is public — it names the key, it is not the key. Recording it is what
  # lets the owner tell which key to revoke later (#139).
  echo "    key id: ${KEY_ID:-unknown} — record this in .n8/memory/play-console.md"
fi

echo
echo "Done. One step is yours and cannot be automated:"
echo "  In the Play Console, Users and permissions, invite"
echo "    $SA_EMAIL"
echo "  with app-level permissions for Honest Sudoku:"
echo "    - Release to testing tracks"
echo "    - View app information and download bulk reports"
echo "  and nothing else. No production release. No store-listing edit."
