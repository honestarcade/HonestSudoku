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

need() {
  command -v "$1" > /dev/null 2>&1 || {
    echo "setup_play_ci: $1 is not on PATH" >&2
    exit 3
  }
}
need gcloud
need gh

if ! gcloud auth list --filter=status:ACTIVE --format='value(account)' 2> /dev/null | grep -q .; then
  echo "setup_play_ci: no active gcloud login." >&2
  echo "  Run: gcloud auth login" >&2
  echo "  Then run this script again; nothing here needs doing by hand." >&2
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
if gh secret list --json name --jq '.[].name' 2> /dev/null | grep -qx "$SECRET"; then
  echo "    already set, skipping (delete it first to rotate)"
else
  mkdir -p "$(dirname "$KEY_PATH")"
  chmod 700 "$(dirname "$KEY_PATH")"
  umask 077
  gcloud iam service-accounts keys create "$KEY_PATH" \
    --iam-account "$SA_EMAIL" --project "$PROJECT" --quiet
  gh secret set "$SECRET" < "$KEY_PATH"
  rm -f "$KEY_PATH"
  echo "    set from a key that has been deleted from disk"
fi

echo
echo "Done. One step is yours and cannot be automated:"
echo "  In the Play Console, Users and permissions, invite"
echo "    $SA_EMAIL"
echo "  with app-level permissions for Honest Sudoku:"
echo "    - Release to testing tracks"
echo "    - View app information and download bulk reports"
echo "  and nothing else. No production release. No store-listing edit."
