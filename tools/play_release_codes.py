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
    # CPython refuses to parse an integer beyond 4300 digits, and the
    # resulting ValueError escaped as exit 1 — the documented code for "no
    # release with that status", so a crash was reported as an empty track
    # (#163). Raising the ceiling to 100000 did not fix that: above the new
    # threshold the behaviour was bit-for-bit the original bug, and below it
    # a 99999-digit "version code" was printed and PUT to the target track.
    # The limit is a backstop, and so is the handler: the length check below
    # refuses anything over ten digits first, so the ValueError can no longer
    # be raised at all. Both are kept against a change to that check, and
    # both are documented as unreachable rather than described as working —
    # the shape #180 was filed for, and which this file did not do (#196).
    # The ValueError is still CAUGHT below, and a version
    # code is length-checked against what Android actually accepts (#178).
    if hasattr(sys, "set_int_max_str_digits"):
        sys.set_int_max_str_digits(100000)
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
            # A malformed container used to be skipped silently, so the caller
            # was told the track was empty for a track that holds a release
            # the parser could not read (#163).
            print(
                "play_release_codes: release is not an object: %r" % (release,),
                file=sys.stderr,
            )
            return 2
        if release.get("status") != want_status:
            continue
        # `or []` flattened 0, false, null and {} to "no codes" and exited
        # 1 — malformed input reported as an empty track, the class #163
        # named — while the string "101" reached the isinstance check and
        # exited 2. Absent is the only thing that may mean empty (#178).
        # Key presence, not `.get()`: an explicit `"versionCodes": null` is
        # malformed input that the API would never send, and `.get()` cannot
        # tell it from an absent key. Absent is the one spelling that may
        # still mean an empty track (#178).
        codes = [] if "versionCodes" not in release else release["versionCodes"]
        if not isinstance(codes, list):
            print(
                "play_release_codes: versionCodes is not a list: %r" % (codes,),
                file=sys.stderr,
            )
            return 2
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
            # No sign: `-5` passed the "strict digits" check and was promoted
            # as a version code, which is the plausible-wrong-code case the
            # check exists to refuse (#163).
            if not re.fullmatch(r"[0-9]+", text):
                print(
                    "play_release_codes: version code is not a number: %r" % (code,),
                    file=sys.stderr,
                )
                return 2
            # Android's versionCode is a signed 32-bit int, so it cannot
            # exceed 2100000000 and can never be more than ten digits. A
            # longer run of digits is malformed input, not a large version,
            # and refusing it here is what keeps the int() below away from
            # CPython's digit ceiling in the first place (#178).
            if len(text) > 10:
                print(
                    "play_release_codes: version code has %d digits; Android's"
                    " versionCode is a 32-bit int" % (len(text),),
                    file=sys.stderr,
                )
                return 2
            try:
                value = int(text)
            except ValueError as exc:
                # Caught rather than allowed to escape: an uncaught
                # ValueError exits 1, which is the documented code for "no
                # release with that status", so a crash read as an empty
                # track (#163, #178).
                print(
                    "play_release_codes: could not read version code %r: %s"
                    % (code, exc),
                    file=sys.stderr,
                )
                return 2
            if value > 2100000000:
                print(
                    "play_release_codes: version code %d exceeds Android's"
                    " maximum of 2100000000" % (value,),
                    file=sys.stderr,
                )
                return 2
            numeric.append(value)
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
