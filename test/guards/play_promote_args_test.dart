@Tags(['guard'])
library;

// Guard for #21: the promote script refuses what it must, without a credential.
//
// The refusals are checked before the token is, deliberately, so that every
// one of them can be proven here — on a laptop, in CI, on a fork — with no
// Play access at all. A refusal that can only be tested by someone holding the
// production credential is a refusal nobody tests.
//
// The one that matters most is `production`. The service account's Console
// permission set is the real barrier and it is granted by a human who can
// change it; this script is the barrier that lives in the repository, where a
// change to it shows up in a diff.
//
// What this does NOT cover: anything past the argument checks. A fake token
// proves the script reaches the API and stops there; it proves nothing about
// the edits flow, which needs real credentials and is verified by dispatch.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'repo_files.dart';
import 'workflow_yaml.dart';

const _script = 'tools/play_promote.sh';
const _package = 'com.honestarcade.sudoku';

/// A loopback port nothing listens on, so the API layer is reached and
/// refused without leaving the machine.
///
/// The exit-5 test used to let the script hit the real Play API, so
/// `flutter test` — and therefore `tools/gate.sh`, and therefore every CI
/// run — made an unauthenticated request to Google on every invocation, in a
/// project whose first invariant is no network (#147). It also made the
/// assertion weaker than it read: offline it passed for a different reason.
/// Pointing it here keeps the discriminator (still 5, still distinct from an
/// argument refusal's 2) and means the same thing on every machine.
const _unreachableApi = 'http://127.0.0.1:1';

({int code, String out, String err}) _run(List<String> args, {String? token}) {
  final r = Process.runSync(
    _script,
    args,
    workingDirectory: repoRoot.path,
    includeParentEnvironment: false,
    environment: {
      'PATH': Platform.environment['PATH'] ?? '/usr/bin:/bin',
      'PLAY_TOKEN': ?token,
      'HS_PLAY_API': _unreachableApi,
    },
    stdoutEncoding: utf8,
    stderrEncoding: utf8,
  );
  return (code: r.exitCode, out: r.stdout.toString(), err: r.stderr.toString());
}

/// The refusal must be reached, unconditionally, before anything that could
/// mint a credential — in every job of the file, not just the first.
/// Runs a refusal step's `run:` body under bash with the dispatch inputs set,
/// and returns its exit code. The body is pure shell — no external command —
/// so this needs no stubs and no network.
int _runRefusal(String script, String fromTrack, String toTrack) {
  final dir = Directory.systemTemp.createTempSync('hs-refusal');
  try {
    final file = File('${dir.path}/refuse.sh')..writeAsStringSync(script);
    final r = Process.runSync(
      '/bin/bash',
      [file.path],
      includeParentEnvironment: false,
      environment: {
        'PATH': '/usr/bin:/bin',
        'FROM_TRACK': fromTrack,
        'TO_TRACK': toTrack,
      },
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
    );
    return r.exitCode;
  } finally {
    dir.deleteSync(recursive: true);
  }
}

void _assertPromoteShape(Workflow wf) {
  expect(wf.problem, isNull, reason: 'refusal: ${wf.problem}');
  expect(wf.jobs, isNotEmpty, reason: 'refusal: no jobs parsed');

  for (final job in wf.jobs) {
    // A job with no steps used to `continue`, so a reusable-workflow job was
    // invisible to every check below — and `secrets: inherit` hands it the
    // service-account key. That is precisely what the failure message one
    // line down warns about, so skipping it was the hole (#171).
    expect(
      job.uses,
      isNull,
      reason:
          'refusal: job `${job.name}` calls the reusable workflow '
          '`${job.uses}`, whose steps are not in this file and cannot be '
          'checked. A job without a refusal can mint the credential and '
          'promote unchecked',
    );
    expect(
      job.steps,
      isNotEmpty,
      reason: 'refusal: job `${job.name}` has no steps',
    );
    expect(
      job.continueOnError,
      isFalse,
      reason:
          'refusal: job `${job.name}` carries `continue-on-error`, so its '
          'refusal failing would not stop what depends on it',
    );

    final refuse = job.steps.first;

    // Behaviour, not text. `refuse.run.contains('exit 1')` was satisfied by
    // any `exit 1` that never executes: inside a shell comment, inside an
    // uncalled function, inside `if false; then … fi`. All three were green
    // while the workflow promoted whatever the script allowed (#171). So the
    // step is RUN, with the dispatch inputs set, and judged by its exit code.
    expect(
      refuse.run,
      isNotNull,
      reason:
          'refusal: the first step of `${job.name}` is '
          '`${refuse.uses ?? refuse.id}`, not a refusal that runs',
    );
    for (final probe in const [
      (from: 'internal', to: 'production', shouldPass: false),
      (from: 'production', to: 'alpha', shouldPass: false),
      (from: 'internal', to: 'nonsense', shouldPass: false),
      (from: 'alpha', to: 'alpha', shouldPass: false),
      (from: 'internal', to: 'alpha', shouldPass: true),
    ]) {
      final code = _runRefusal(refuse.run!, probe.from, probe.to);
      if (probe.shouldPass) {
        expect(
          code,
          0,
          reason:
              'refusal: `${probe.from} -> ${probe.to}` is a legitimate '
              'promotion and was refused — a refusal that blocks everything '
              'is not a working guard',
        );
      } else {
        expect(
          code,
          isNot(0),
          reason:
              'refusal: `${probe.from} -> ${probe.to}` was ACCEPTED by the '
              'refusal step in `${job.name}`',
        );
      }
    }

    expect(
      refuse.isUnconditional,
      isTrue,
      reason:
          'refusal: the refusal in `${job.name}` is conditional '
          '(if: ${refuse.ifExpression}, continue-on-error: '
          '${refuse.continueOnError}) — it would be skipped or ignored',
    );

    // Every step that ACTS must be unconditional. Only the first step was
    // checked, so `if: always()` on `promote` was green and the "a failed
    // refusal stops the run" guarantee was gone (#171). The reporting and
    // cleanup steps are the deliberate exceptions: they exist to run on the
    // refusal path, and they are named rather than pattern-matched.
    const mayAlwaysRun = {'summary', 'forget'};
    for (final step in job.steps) {
      if (mayAlwaysRun.contains(step.id)) {
        expect(
          step.ifExpression,
          'always()',
          reason:
              'refusal: `${step.id}` is allowed to run after a refusal only '
              'as `if: always()`',
        );
        continue;
      }
      expect(
        step.isUnconditional,
        isTrue,
        reason:
            'refusal: step `${step.id ?? step.index}` of `${job.name}` is '
            'conditional (if: ${step.ifExpression}, continue-on-error: '
            '${step.continueOnError}), so it can run although the refusal '
            'failed',
      );
    }
  }
}

void main() {
  test('the script exists and is executable', () {
    expect(pathExists(_script), isTrue);
    final mode = File('${repoRoot.path}/$_script').statSync().mode;
    expect(mode & 0x40, isNot(0), reason: '$_script is not executable');
  });

  group('refuses before it ever looks for a token', () {
    test('production as the target', () {
      // Checked with a valid token present, so the refusal cannot be
      // attributed to the missing credential.
      final r = _run([_package, 'internal', 'production'], token: 'fake');
      expect(r.code, 2, reason: 'production-refused: ${r.err}');
      expect(r.out.trim(), isEmpty);
      expect(r.err.toLowerCase(), contains('production'));
    });

    test('production as the source', () {
      final r = _run([_package, 'production', 'alpha'], token: 'fake');
      expect(r.code, 2);
      expect(r.out.trim(), isEmpty);
    });

    for (final track in const ['internal', 'alpha', 'beta']) {
      test('$track to itself', () {
        final r = _run([_package, track, track], token: 'fake');
        expect(r.code, 2, reason: 'same-track: $track to $track was allowed');
        expect(r.out.trim(), isEmpty);
      });
    }

    for (final bad in const ['staging', 'Internal', 'prod', '']) {
      test('the unknown track `$bad`', () {
        final r = _run([_package, 'internal', bad], token: 'fake');
        expect(r.code, 2, reason: 'allowlist: `$bad` was allowed');
        expect(r.out.trim(), isEmpty);
      });
    }

    test('a missing package argument', () {
      expect(_run(['', 'internal', 'alpha'], token: 'fake').code, 2);
      expect(_run(const [], token: 'fake').code, 2);
      expect(_run([_package, 'internal'], token: 'fake').code, 2);
    });
  });

  test('a missing token is refused, with valid arguments', () {
    // The order matters and is asserted: arguments first, token second.
    final r = _run([_package, 'internal', 'alpha']);
    expect(r.code, 2, reason: 'no-token: ${r.err}');
    expect(r.out.trim(), isEmpty);
    expect(r.err.toUpperCase(), contains('PLAY_TOKEN'));
  });

  test('valid arguments and a fake token reach the API and stop', () {
    // Exit 5 is the API layer, distinct from 2. If this ever returns 2 the
    // argument checks have started rejecting something they should accept,
    // and the refusal tests above would still pass while the script had
    // stopped working. The API is a closed loopback port, not Google — see
    // _unreachableApi.
    final r = _run([_package, 'internal', 'alpha'], token: 'not-a-real-token');
    expect(
      r.code,
      5,
      reason:
          'api-reached: expected the API failure code, not an argument '
          'refusal.\n${r.err}',
    );
  });

  test('the workflow refuses at its own layer too', () {
    // Two barriers at different layers: the workflow exits 1 before any API
    // call, the script exits 2. Either alone would be enough; both means a
    // change to one does not silently remove the guarantee.
    final workflow = readFile('.github/workflows/play-promote.yml');
    expect(workflow, contains('production'));
    expect(
      workflow,
      contains('exit 1'),
      reason:
          'workflow-refusal: the dispatch step must refuse before the '
          'script is ever called',
    );
  });

  test('the refusal is first, unconditional, and nothing else mints a credential', () {
    // Parsed, not grepped. The line-scan version was defeated four ways with a
    // green suite: `exit 1` present only in a comment, `continue-on-error` on
    // the refusal, `if: always()` on the steps after it, and an entire second
    // job with no refusal at all (#154).
    _assertPromoteShape(
      Workflow.parse(
        '.github/workflows/play-promote.yml',
        readFile('.github/workflows/play-promote.yml'),
      ),
    );
  });

  test('the refusal rule catches each way it was defeated', () {
    final text = readFile('.github/workflows/play-promote.yml');
    final mutations = <String, String Function(String)>{
      'refusal moved to last': (t) {
        final blocks = t.split(RegExp(r'^(?=      - )', multiLine: true));
        final refuse = blocks.firstWhere(
          (b) => b.startsWith('      - id: refuse'),
        );
        final rest = blocks.where((b) => b != refuse).toList();
        return rest.join() + refuse;
      },
      'refusal disabled with if: false': (t) => t.replaceFirst(
        '      - id: refuse\n',
        '      - id: refuse\n        if: false\n',
      ),
      'refusal made advisory with continue-on-error': (t) => t.replaceFirst(
        '      - id: refuse\n',
        '      - id: refuse\n        continue-on-error: true\n',
      ),
      'an id-less step mints the credential first': (t) => t.replaceFirst(
        '      - id: refuse\n',
        '      - name: mint early\n'
            '        run: gcloud auth activate-service-account\n'
            '      - id: refuse\n',
      ),
      'a second job with no refusal': (t) =>
          '$t\n  sneaky:\n    runs-on: ubuntu-latest\n    steps:\n'
          '      - id: token\n        run: gcloud auth activate-service-account\n'
          '      - id: promote\n        run: tools/play_promote.sh pkg internal production\n',
      // #171: the four remaining defeats of the text-matching version.
      'every exit 1 becomes a shell comment': (t) => t.replaceAllMapped(
        RegExp(r'^(\s*)exit 1$', multiLine: true),
        (m) => '${m[1]}: # exit 1',
      ),
      'exit 1 survives only inside an uncalled function': (t) => t
          .replaceAllMapped(
            RegExp(r'^(\s*)exit 1$', multiLine: true),
            (m) => '${m[1]}:',
          )
          .replaceFirst(
            '          set -euo pipefail\n',
            '          set -euo pipefail\n'
                '          never_called() { exit 1; }\n',
          ),
      'exit 1 survives only inside if false': (t) => t
          .replaceAllMapped(
            RegExp(r'^(\s*)exit 1$', multiLine: true),
            (m) => '${m[1]}:',
          )
          .replaceFirst(
            '          set -euo pipefail\n',
            '          set -euo pipefail\n'
                '          if false; then exit 1; fi\n',
          ),
      'if: always() on the promote step': (t) => t.replaceFirst(
        '      - id: promote\n',
        '      - id: promote\n        if: always()\n',
      ),
      'continue-on-error as a quoted string': (t) => t.replaceFirst(
        '      - id: refuse\n',
        '      - id: refuse\n        continue-on-error: "true"\n',
      ),
      'a reusable-workflow job with no steps': (t) =>
          '$t\n  sneaky:\n    uses: ./.github/workflows/evil.yml\n'
          '    secrets: inherit\n',
      // There is no 'first exit 1 commented out' entry, and that is a
      // finding rather than an omission. The entry that used to be here
      // passed `r'$1: # exit 1'` to replaceFirst, which inserts it
      // LITERALLY: a `$1` landed at column 0, terminated the block scalar,
      // and the shape assertion threw on `expect(wf.problem, isNull)`. The
      // battery scored that as a catch, so the one entry that would have
      // found #171's shell-comment defeat reported a pass while it was live
      // (#172).
      //
      // Written correctly it does not defeat anything: the refusal rejects
      // production twice — once by name, once by falling through the `case`
      // to `*)` — so neutering the first `exit 1` leaves production refused.
      // The honest mutation is the one below, which neuters them all.
    };
    mutations.forEach((why, mutate) {
      final mutated = mutate(text);
      expect(mutated, isNot(text), reason: 'sanity: "$why" changed nothing');
      expect(
        Workflow.parse('play-promote.yml', mutated).problem,
        isNull,
        reason: 'sanity: "$why" produced YAML that does not parse',
      );
      expect(
        () => _assertPromoteShape(Workflow.parse('play-promote.yml', mutated)),
        throwsA(isA<TestFailure>()),
        reason: 'refusal-negative: "$why" was not caught',
      );
    });
  });
}
