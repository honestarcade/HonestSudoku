#!/usr/bin/env bash
# Map a git tag and a run identity to exactly one version name and code.
#
# This runs before anything is built, and its refusals are the point. A release
# workflow that guesses at a malformed tag ships something nobody asked for,
# under a number nobody chose, to a track real testers read — and a version
# code cannot be withdrawn once Play has seen it. So a bad input exits non-zero
# and prints NOTHING on stdout: a caller reading stdout gets nothing rather
# than a partial line it might parse.
#
# Usage:  tools/ci_version.sh <ref_name> <run_number> <run_attempt>
# Output: name=<semver>
#         code=<1000 + run_number*10 + run_attempt>
# Exit:   0  both printed
#         2  a refused argument (message on stderr, stdout empty)
#
# Why that formula. The code must rise strictly across runs AND across attempts
# of one run, because Play refuses a code it has already seen and a re-run of a
# failed release must be able to ship. Ten slots per run gives the attempt term
# room; the attempt is therefore bounded at 9, because attempt 10 of run N
# would equal attempt 0 of run N+1. The 1000 offset leaves room below for any
# codes uploaded by hand before this existed.
set -euo pipefail
export LC_ALL=C

die() {
  echo "ci_version: $1" >&2
  exit 2
}

[ "$#" -eq 3 ] || die "expected 3 arguments (ref_name run_number run_attempt), got $#"

ref="$1"
run="$2"
attempt="$3"

# `v<major>.<minor>.<patch>` with an optional `-<prerelease>`.
#
# `grep -qE '^...$'` anchors each LINE, not the whole string, so a ref
# containing a newline matched on its first line and the rest was carried into
# `name=` — and from there into $GITHUB_OUTPUT, one `tee` away from injecting a
# second line (#138). Unreachable through git, which refuses control characters
# in a ref, but the header claimed anchoring it did not have. Rejecting any
# newline first restores the claim.
# Counted, not pattern-matched: `case $ref in *"$(printf '\n')"*)` looks right
# and matches every string, because command substitution strips the trailing
# newline and leaves an empty needle.
[ "$(printf '%s' "$ref" | tr -cd '\n' | wc -c | tr -d ' ')" -eq 0 ] ||
  die "ref contains a newline"

printf '%s' "$ref" | grep -qE '^v[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z][0-9A-Za-z.-]*)?$' ||
  die "ref '$ref' is not v<major>.<minor>.<patch>[-prerelease]"

# The prerelease, to semver's own rules. The pattern above accepts any run of
# alphanumerics, dots and hyphens, so `v1.2.3-rc.01`, `v1.2.3-00` and
# `v1.2.3-rc.1.` all passed — a numeric identifier may not carry a leading
# zero, and an identifier may not be empty. The leading-zero guard below
# covers only the core triple (#180).
case "$ref" in
*-*)
  pre="${ref#*-}"
  printf '%s' "$pre" |
    grep -qE '^(0|[1-9][0-9]*|[0-9]*[A-Za-z-][0-9A-Za-z-]*)(\.(0|[1-9][0-9]*|[0-9]*[A-Za-z-][0-9A-Za-z-]*))*$' ||
    die "ref '$ref' has an invalid prerelease '$pre': identifiers must be non-empty, and a numeric one may not have a leading zero"
  ;;
esac

# No leading zeros: `v01.2.3` is not semver, and it would ship as name 01.2.3.
printf '%s' "$ref" | grep -qE '^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(-|$)' ||
  die "ref '$ref' has a leading zero in a version component"

# Same counting guard as the ref above, for the same reason: `grep -qE '^…$'`
# anchors each LINE, so a newline in either number passed, and `7\n8` died with
# a raw bash arithmetic error instead of the documented exit 2 (#159).
has_newline() {
  [ "$(printf '%s' "$1" | tr -cd '\n' | wc -c | tr -d ' ')" -ne 0 ]
}
has_newline "$run" && die "run number contains a newline"
has_newline "$attempt" && die "run attempt contains a newline"

printf '%s' "$run" | grep -qE '^[1-9][0-9]*$' ||
  die "run number '$run' is not a positive integer"

# Android refuses a versionCode above 2100000000. The bound that does the
# work is this one: eight digits caps the code at 1000 + 99999999*10 + 9 =
# 1000000999, which is under half Android's maximum, so the check after the
# arithmetic can never fire. It is kept as a backstop against a future change
# to the formula, and it is documented as one rather than described as
# working with this bound (#180).
[ "${#run}" -le 8 ] ||
  die "run number '$run' is implausibly large; the version code would overflow"

printf '%s' "$attempt" | grep -qE '^[1-9]$' ||
  die "run attempt '$attempt' is outside 1-9; attempt 10 of run N would collide with attempt 1 of run N+1"

name="${ref#v}"
code=$((1000 + run * 10 + attempt))

# Unreachable with the eight-digit bound above, deliberately: a backstop for
# a change to the formula, not a check that fires today (#180).
[ "$code" -gt 0 ] && [ "$code" -le 2100000000 ] ||
  die "computed version code $code is outside Android's 1..2100000000"

echo "name=$name"
echo "code=$code"
