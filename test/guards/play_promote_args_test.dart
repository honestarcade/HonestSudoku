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

const _script = 'tools/play_promote.sh';
const _package = 'com.honestarcade.sudoku';

({int code, String out, String err}) _run(List<String> args, {String? token}) {
  final r = Process.runSync(
    _script,
    args,
    workingDirectory: repoRoot.path,
    includeParentEnvironment: false,
    environment: {
      'PATH': Platform.environment['PATH'] ?? '/usr/bin:/bin',
      'PLAY_TOKEN': ?token,
    },
    stdoutEncoding: utf8,
    stderrEncoding: utf8,
  );
  return (code: r.exitCode, out: r.stdout.toString(), err: r.stderr.toString());
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
    // stopped working.
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

  test('the refusal is the first step, and precedes the credential', () {
    // Ordering is the whole claim — "production is refused before any API
    // call" is worth nothing if the refusal runs after the token is minted.
    // Asserting only that the file contains the words survived moving the
    // step to last, with the suite still green (#136).
    final workflow = readFile('.github/workflows/play-promote.yml');
    final stepIds = RegExp(
      r'^      - id: (\w+)',
      multiLine: true,
    ).allMatches(workflow).map((m) => m.group(1)!).toList();

    expect(
      stepIds,
      isNotEmpty,
      reason: 'step-order: no `- id:` steps found; has the layout changed?',
    );
    expect(
      stepIds.first,
      'refuse',
      reason: 'step-order: the refusal must be the first step. Found: $stepIds',
    );
    for (final later in const ['token', 'promote']) {
      expect(
        stepIds.indexOf(later),
        greaterThan(stepIds.indexOf('refuse')),
        reason:
            'step-order: `$later` must run after `refuse`, or a refused '
            'track reaches a credential. Found: $stepIds',
      );
    }
  });

  test('the step-order rule can fail', () {
    // The complement: a rule that cannot fail is exactly what #136 was.
    const moved =
        '      - id: token\n'
        '        run: mint\n'
        '      - id: refuse\n'
        '        run: exit 1\n'
        '      - id: promote\n'
        '        run: go\n';
    final stepIds = RegExp(
      r'^      - id: (\w+)',
      multiLine: true,
    ).allMatches(moved).map((m) => m.group(1)!).toList();
    expect(stepIds, ['token', 'refuse', 'promote']);
    expect(
      stepIds.first,
      isNot('refuse'),
      reason: 'step-order-negative: the fixture must violate the rule',
    );
    expect(stepIds.indexOf('token'), lessThan(stepIds.indexOf('refuse')));
  });
}
