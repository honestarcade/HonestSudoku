#!/usr/bin/env bash
# Move the newest completed build from one testing track to another.
#
# It never builds anything and it never touches production. Production is a
# human act in the Play Console (owner's call, 2026-09-18), and the service
# account's Console permission set is the real barrier — but that set is
# granted by a human who can change it, so this is the barrier that lives in
# the repository, where a change to it shows up in a diff.
#
# Argument checks come BEFORE the token check, deliberately. Every refusal is
# then provable with no Play access at all, on a laptop or in a fork. A refusal
# that can only be tested by someone holding the production credential is a
# refusal nobody tests.
#
# Usage:  tools/play_promote.sh <package> <from_track> <to_track>
#         PLAY_TOKEN must hold an OAuth access token for the Play Developer API.
# Exit:   0  promoted, and read back from the target track
#         2  a refused argument, or no token (stdout empty)
#         5  the Play API refused or the track held nothing to promote
set -euo pipefail
export LC_ALL=C

# Closed testing is `alpha` and open testing is `beta` in the API's vocabulary.
# `production` is absent on purpose, and its absence is the point of this list.
ALLOWED_TRACKS="internal alpha beta"
# Overridable so the promotion path can be exercised against a mock, the way
# HS_UPLOAD_CERT makes verify_upload_cert.sh's match path testable. Everything
# below the argument checks was unreachable in a test before this, which is
# where #128, #129 and #133 all lived.
API="${HS_PLAY_API:-https://androidpublisher.googleapis.com/androidpublisher/v3/applications}"

die_args() {
  echo "play_promote: $1" >&2
  exit 2
}

die_api() {
  echo "play_promote: $1" >&2
  exit 5
}

is_allowed() {
  # Matched whole, not as a substring of the list. ` internal alpha beta `
  # with a `*" $1 "*` pattern accepted "alpha beta" as one track, which then
  # reached the API instead of being refused (#133).
  case "$1" in
  internal | alpha | beta) return 0 ;;
  *) return 1 ;;
  esac
}

# ---- arguments, before anything else ----------------------------------------

[ "$#" -eq 3 ] || die_args "expected 3 arguments (package from_track to_track), got $#"

PACKAGE="$1"
FROM="$2"
TO="$3"

[ -n "$PACKAGE" ] || die_args "package name is empty"

for track in "$FROM" "$TO"; do
  if [ "$track" = "production" ]; then
    die_args "production is a human act in the Play Console; this script refuses it"
  fi
  if ! is_allowed "$track"; then
    die_args "'$track' is not one of: $ALLOWED_TRACKS"
  fi
done

[ "$FROM" != "$TO" ] || die_args "source and target are the same track ('$FROM')"

# ---- credential --------------------------------------------------------------

[ -n "${PLAY_TOKEN:-}" ] || die_args "PLAY_TOKEN is not set"

# ---- the edits flow ----------------------------------------------------------

auth=(-H "Authorization: Bearer $PLAY_TOKEN")
json=(-H "Content-Type: application/json")

api() {
  # method, path, optional body. Prints the response body; a non-2xx status is
  # a hard failure naming the path, because a silently-ignored error here
  # leaves a half-finished edit on the account.
  local method="$1" path="$2" body="${3:-}"
  local out status
  out="$(mktemp)"
  API_BODY_FILE="$out"
  if [ -n "$body" ]; then
    status="$(curl -sS -o "$out" -w '%{http_code}' -X "$method" "${auth[@]}" "${json[@]}" -d "$body" "$path")"
  else
    status="$(curl -sS -o "$out" -w '%{http_code}' -X "$method" "${auth[@]}" "$path")"
  fi
  if [ "${status:0:1}" != "2" ]; then
    echo "play_promote: $method $path returned $status" >&2
    sed -n '1,20p' "$out" >&2
    # Left on disk on purpose: the caller decides what the refusal means, and
    # the draft retry has to read it (#129). cleanup() removes it.
    return 1
  fi
  cat "$out"
  rm -f "$out"
  API_BODY_FILE=""
}

EDIT_ID=""
API_BODY_FILE=""
cleanup() {
  [ -n "$API_BODY_FILE" ] && rm -f "$API_BODY_FILE"
  # Any edit that was not committed is deleted, so a failed run leaves no
  # pending change on the account.
  if [ -n "$EDIT_ID" ]; then
    curl -sS -o /dev/null -X DELETE "${auth[@]}" \
      "$API/$PACKAGE/edits/$EDIT_ID" 2>/dev/null || true
  fi
}
trap cleanup EXIT

EDIT_ID="$(api POST "$API/$PACKAGE/edits" '{}' |
  sed -n 's/.*"id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)" ||
  die_api "could not open an edit (is PLAY_TOKEN valid for $PACKAGE?)"
[ -n "$EDIT_ID" ] || die_api "the edits endpoint returned no id"

SOURCE="$(api GET "$API/$PACKAGE/edits/$EDIT_ID/tracks/$FROM")" ||
  die_api "could not read the '$FROM' track"

# The newest completed release's version codes, chosen by a real JSON parse.
# This was a regex over flattened JSON and got it wrong twice: a release
# carrying release notes was invisible, so a populated track reported "no
# completed release"; and with two completed releases it picked the last
# listed rather than the newest (#128).
CODES_HELPER="$(dirname "$0")/play_release_codes.py"
[ -x "$CODES_HELPER" ] || die_api "missing $CODES_HELPER"
command -v python3 > /dev/null 2>&1 || die_api "python3 is not on PATH"

set +e
CODES="$(printf '%s' "$SOURCE" | python3 "$CODES_HELPER")"
CODES_RC=$?
set -e
case "$CODES_RC" in
0) ;;
1) die_api "no completed release on $FROM" ;;
*) die_api "could not read the '$FROM' track's releases" ;;
esac
[ -n "$CODES" ] || die_api "no completed release on $FROM"

# The helper prints them space separated and numeric; the API wants strings.
CODES_JSON="[$(printf '%s' "$CODES" | tr ' ' '\n' | sed 's/^/"/; s/$/"/' | paste -sd, -)]"

# The read-only edit has served its purpose. Delete it now rather than leaving
# it for the trap: each attempt below opens its own edit and overwrites
# EDIT_ID, so the trap would only ever see the last one and this one would be
# left pending on the account.
curl -sS -o /dev/null -X DELETE "${auth[@]}" "$API/$PACKAGE/edits/$EDIT_ID" 2> /dev/null || true
EDIT_ID=""

# One attempt is open-edit -> PUT -> commit, because the draft-app rule can be
# refused at EITHER step and the acceptance criterion names the commit. A
# refused commit also spends the edit, so the retry needs a fresh one rather
# than reusing the one that just failed.
REFUSAL=""
last_refusal() {
  REFUSAL=""
  if [ -n "$API_BODY_FILE" ] && [ -r "$API_BODY_FILE" ]; then
    REFUSAL="$(tr '[:upper:]' '[:lower:]' < "$API_BODY_FILE" | tr -d '\n')"
  fi
}

is_draft_app_rule() {
  case "$REFUSAL" in
  *"draft app"* | *"draft_app"* | *"only releases with status draft"*) return 0 ;;
  *) return 1 ;;
  esac
}

attempt_promotion() {
  # $1 = release status. Returns 0 on a committed promotion, 1 otherwise,
  # leaving REFUSAL set to the lowercased body of whatever refused it.
  local release_status="$1"

  EDIT_ID="$(api POST "$API/$PACKAGE/edits" '{}' |
    sed -n 's/.*"id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)" || {
    last_refusal
    return 1
  }
  [ -n "$EDIT_ID" ] || die_api "the edits endpoint returned no id"

  api PUT "$API/$PACKAGE/edits/$EDIT_ID/tracks/$TO" \
    "{\"track\":\"$TO\",\"releases\":[{\"versionCodes\":$CODES_JSON,\"status\":\"$release_status\"}]}" \
    > /dev/null || {
    last_refusal
    return 1
  }

  api POST "$API/$PACKAGE/edits/$EDIT_ID:commit" '{}' > /dev/null || {
    last_refusal
    return 1
  }

  EDIT_ID="" # committed: cleanup must not delete it
  return 0
}

STATUS_USED="completed"
if ! attempt_promotion completed; then
  # Only the draft-app rule earns a retry. This used to retry on ANY failure of
  # the PUT, so a 403 became "the app is not yet published", the release was
  # quietly downgraded to draft, and the run exited 0 — a permission denial
  # reported as a success. It also did not retry on the one refusal the
  # criterion actually names, which arrives at commit (#129).
  if is_draft_app_rule; then
    echo "play_promote: the app is not yet published, so a completed release is" >&2
    echo "  refused; retrying the same version codes as a draft release." >&2
    attempt_promotion draft || die_api "the '$TO' track refused the draft retry too"
    STATUS_USED="draft"
  else
    die_api "the '$TO' track refused the promotion, and not for the draft-app rule"
  fi
fi


READBACK_EDIT="$(api POST "$API/$PACKAGE/edits" '{}' |
  sed -n 's/.*"id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)" ||
  die_api "promoted, but could not open an edit to read the result back"
EDIT_ID="$READBACK_EDIT"
TARGET="$(api GET "$API/$PACKAGE/edits/$EDIT_ID/tracks/$TO")" ||
  die_api "promoted, but could not read the '$TO' track back"
# Compared, not merely present. `grep -q '"versionCodes"'` passed whenever the
# target track already held any release at all, so a promotion that did nothing
# read back as a success (#133).
set +e
TARGET_CODES="$(printf '%s' "$TARGET" | python3 "$CODES_HELPER")"
TARGET_RC=$?
set -e
if [ "$TARGET_RC" != 0 ] && [ "$STATUS_USED" = "completed" ]; then
  die_api "the '$TO' track reads back with no completed release"
fi
if [ "$STATUS_USED" = "completed" ] && [ "$TARGET_CODES" != "$CODES" ]; then
  die_api "the '$TO' track reads back as [$TARGET_CODES], not the promoted [$CODES]"
fi
if [ "$STATUS_USED" = "draft" ]; then
  # A draft release is not a completed one, so the helper will not find it.
  # Fall back to asserting each promoted code appears in the track's JSON.
  FLAT="$(printf '%s' "$TARGET" | tr -d ' \n')"
  for code in $CODES; do
    case "$FLAT" in
    *"\"$code\""*) ;;
    *) die_api "the '$TO' track reads back without the promoted code $code" ;;
    esac
  done
fi

echo "promoted=$CODES"
echo "from=$FROM"
echo "to=$TO"
echo "status=$STATUS_USED"
