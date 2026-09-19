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

# `v<major>.<minor>.<patch>` with an optional `-<prerelease>`. Anchored at both
# ends, so a trailing space or a fourth component is refused rather than
# silently trimmed.
printf '%s' "$ref" | grep -qE '^v[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z][0-9A-Za-z.-]*)?$' ||
  die "ref '$ref' is not v<major>.<minor>.<patch>[-prerelease]"

printf '%s' "$run" | grep -qE '^[1-9][0-9]*$' ||
  die "run number '$run' is not a positive integer"

printf '%s' "$attempt" | grep -qE '^[1-9]$' ||
  die "run attempt '$attempt' is outside 1-9; attempt 10 of run N would collide with attempt 1 of run N+1"

name="${ref#v}"
code=$((1000 + run * 10 + attempt))

echo "name=$name"
echo "code=$code"
