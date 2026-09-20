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
void _assertPromoteShape(Workflow wf) {
  expect(wf.problem, isNull, reason: 'refusal: ${wf.problem}');
  expect(wf.jobs, isNotEmpty, reason: 'refusal: no jobs parsed');

  for (final job in wf.jobs) {
    if (job.steps.isEmpty) continue;
    final refusals = job.steps
        .where((s) => (s.run ?? '').contains('exit 1'))
        .toList();
    expect(
      refusals,
      isNotEmpty,
      reason:
          'refusal: job `${job.name}` has no step that refuses. A job '
          'without one can mint the credential and promote unchecked',
    );
    final refuse = job.steps.first;
    expect(
      refuse.run ?? '',
      contains('exit 1'),
      reason:
          'refusal: the first step of job `${job.name}` must be the '
          'refusal; found `${refuse.id ?? refuse.name}`',
    );
    expect(
      refuse.isUnconditional,
      isTrue,
      reason:
          'refusal: the refusal in `${job.name}` is conditional '
          '(if: ${refuse.ifExpression}, continue-on-error: '
          '${refuse.continueOnError}) — it would be skipped or ignored',
    );
    expect(
      refuse.run,
      contains('production'),
      reason:
          'refusal: the first step of `${job.name}` does not mention the '
          'track it exists to refuse',
    );
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
      'the refusal stops refusing': (t) => t.replaceFirst(
        RegExp(r'^(\s*)exit 1$', multiLine: true),
        r'$1: # exit 1',
      ),
    };
    mutations.forEach((why, mutate) {
      final mutated = mutate(text);
      expect(mutated, isNot(text), reason: 'sanity: "$why" changed nothing');
      expect(
        () => _assertPromoteShape(Workflow.parse('play-promote.yml', mutated)),
        throwsA(isA<TestFailure>()),
        reason: 'refusal-negative: "$why" was not caught',
      );
    });
  });
}
