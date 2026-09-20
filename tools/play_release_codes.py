#!/usr/bin/env python3
"""Pick the version codes of the newest release on a Play track.

Reads the Play Developer API's track JSON on stdin. Prints the chosen
release's version codes, space separated, on one line.

Usage: play_release_codes.py [status]      (default: completed)

The status argument exists so the draft path can be confirmed the same way
the completed path is. Without it the draft read-back fell back to a
substring match over the flattened JSON, which accepted any pre-existing
release — and accepted a release whose *name* happened to be the version
code (#145).

This exists because the job was being done by a regex over flattened JSON,
which got it wrong two ways (#128): `[^}]*` between `versionCodes` and
`status` could not cross the `}` closing a nested object, so a release
carrying release notes was invisible and the track was reported empty; and a
greedy `.*` selected the *last* release in document order rather than the
newest, so with two completed releases it promoted the older one.

"Newest" is the release whose highest version code is highest. Play lists
releases newest-first, but that is a presentation detail, not a guarantee,
and version codes are required to rise (see tools/ci_version.sh).

Exit: 0  codes printed
      1  no release with that status (stdout empty)
      2  stdin was not the JSON this expects (stdout empty)
"""
import json
import re
import sys


def main() -> int:
    want_status = sys.argv[1] if len(sys.argv) > 1 else "completed"
    if len(sys.argv) > 2:
        print("play_release_codes: expected at most one argument", file=sys.stderr)
        return 2
    raw = sys.stdin.read()
    try:
        doc = json.loads(raw)
    except (ValueError, TypeError):
        print("play_release_codes: stdin is not valid JSON", file=sys.stderr)
        return 2
    if not isinstance(doc, dict):
        print("play_release_codes: expected a JSON object", file=sys.stderr)
        return 2

    releases = doc.get("releases")
    if releases is None:
        releases = []
    if not isinstance(releases, list):
        print("play_release_codes: 'releases' is not a list", file=sys.stderr)
        return 2

    best = None
    for release in releases:
        if not isinstance(release, dict):
            continue
        if release.get("status") != want_status:
            continue
        codes = release.get("versionCodes") or []
        if not isinstance(codes, list):
            continue
        # The API sends them as strings; accept ints too rather than trust that.
        numeric = []
        for code in codes:
            # Strict, because bare `int()` accepts things JSON does not mean:
            # "1_0_1" -> 101, fullwidth "１０１" -> 101, True -> 1, " 101 " ->
            # 101. Each of those would become a plausible *wrong* code and be
            # PUT to the target track, rather than refused (#150).
            if isinstance(code, bool) or not isinstance(code, (int, str)):
                print(
                    "play_release_codes: version code is not a number: %r" % (code,),
                    file=sys.stderr,
                )
                return 2
            text = code if isinstance(code, str) else str(code)
            if not re.fullmatch(r"-?[0-9]+", text):
                print(
                    "play_release_codes: version code is not a number: %r" % (code,),
                    file=sys.stderr,
                )
                return 2
            numeric.append(int(text))
        if not numeric:
            continue
        if best is None or max(numeric) > max(best):
            best = numeric

    if best is None:
        return 1
    print(" ".join(str(code) for code in sorted(best)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
