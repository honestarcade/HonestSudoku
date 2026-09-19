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
API="https://androidpublisher.googleapis.com/androidpublisher/v3/applications"

die_args() {
  echo "play_promote: $1" >&2
  exit 2
}

die_api() {
  echo "play_promote: $1" >&2
  exit 5
}

is_allowed() {
  case " $ALLOWED_TRACKS " in
  *" $1 "*) return 0 ;;
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
  if [ -n "$body" ]; then
    status="$(curl -sS -o "$out" -w '%{http_code}' -X "$method" "${auth[@]}" "${json[@]}" -d "$body" "$path")"
  else
    status="$(curl -sS -o "$out" -w '%{http_code}' -X "$method" "${auth[@]}" "$path")"
  fi
  if [ "${status:0:1}" != "2" ]; then
    echo "play_promote: $method $path returned $status" >&2
    sed -n '1,20p' "$out" >&2
    rm -f "$out"
    return 1
  fi
  cat "$out"
  rm -f "$out"
}

EDIT_ID=""
cleanup() {
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

# The newest completed release's version codes. Read with sed rather than jq,
# which is not on stock macOS; the shape is `"status": "completed"` inside a
# release object carrying `"versionCodes": ["123"]`.
CODES="$(printf '%s' "$SOURCE" |
  tr -d ' \n' |
  sed -n 's/.*"versionCodes":\[\([^]]*\)\][^}]*"status":"completed".*/\1/p' |
  tr -d '"' | head -1)"
if [ -z "$CODES" ]; then
  CODES="$(printf '%s' "$SOURCE" |
    tr -d ' \n' |
    sed -n 's/.*"status":"completed"[^}]*"versionCodes":\[\([^]]*\)\].*/\1/p' |
    tr -d '"' | head -1)"
fi
[ -n "$CODES" ] || die_api "no completed release on $FROM"

CODES_JSON="[$(printf '%s' "$CODES" | sed 's/[^0-9,]//g' | sed 's/\([0-9][0-9]*\)/"\1"/g')]"

promote_with_status() {
  local release_status="$1"
  api PUT "$API/$PACKAGE/edits/$EDIT_ID/tracks/$TO" \
    "{\"track\":\"$TO\",\"releases\":[{\"versionCodes\":$CODES_JSON,\"status\":\"$release_status\"}]}"
}

STATUS_USED="completed"
if ! promote_with_status completed > /dev/null 2>&1; then
  # A draft app cannot have a completed release on a testing track until its
  # first release is published. Retrying as a draft is the documented path, and
  # it is said out loud rather than silently substituted.
  echo "play_promote: a completed release was refused; retrying as a draft (the app is not yet published)" >&2
  promote_with_status draft > /dev/null || die_api "the '$TO' track refused both completed and draft"
  STATUS_USED="draft"
fi

api POST "$API/$PACKAGE/edits/$EDIT_ID:commit" '{}' > /dev/null ||
  die_api "the edit was refused at commit"
EDIT_ID=""   # committed: cleanup must not delete it

READBACK_EDIT="$(api POST "$API/$PACKAGE/edits" '{}' |
  sed -n 's/.*"id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)" ||
  die_api "promoted, but could not open an edit to read the result back"
EDIT_ID="$READBACK_EDIT"
TARGET="$(api GET "$API/$PACKAGE/edits/$EDIT_ID/tracks/$TO")" ||
  die_api "promoted, but could not read the '$TO' track back"
printf '%s' "$TARGET" | tr -d ' \n' | grep -q '"versionCodes"' ||
  die_api "the '$TO' track reads back with no version codes"

echo "promoted=$CODES"
echo "from=$FROM"
echo "to=$TO"
echo "status=$STATUS_USED"
