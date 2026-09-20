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

/// The steps of a workflow job, as raw text blocks in file order.
///
/// A block starts at a `- ` list item under `steps:` and runs to the next one.
/// Reading whole blocks rather than grepping `- id:` lines is what makes the
/// assertions below survive a step that has no `id:`, a duplicate `id:`, and
/// an `if:` that disables it — all three defeated the line-scan version with
/// a green suite (#146).
List<String> _stepBlocks(String workflow) {
  final lines = workflow.split('\n');
  final start = lines.indexWhere((l) => RegExp(r'^    steps:\s*$').hasMatch(l));
  if (start < 0) return const [];
  final blocks = <String>[];
  final buffer = StringBuffer();
  for (var i = start + 1; i < lines.length; i++) {
    final line = lines[i];
    if (line.trim().isEmpty) {
      if (buffer.isNotEmpty) buffer.writeln(line);
      continue;
    }
    final indent = line.length - line.trimLeft().length;
    if (indent <= 4) break; // left the steps: block
    if (RegExp(r'^      - ').hasMatch(line)) {
      if (buffer.isNotEmpty) blocks.add(buffer.toString());
      buffer.clear();
    }
    buffer.writeln(line);
  }
  if (buffer.isNotEmpty) blocks.add(buffer.toString());
  return blocks;
}

String? _stepId(String block) => RegExp(
  r'^\s*-?\s*id:\s*(\S+)',
  multiLine: true,
).firstMatch(block)?.group(1);

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

  test(
    'the refusal is the first step, runs unconditionally, and is unique',
    () {
      final workflow = readFile('.github/workflows/play-promote.yml');
      final blocks = _stepBlocks(workflow);
      final ids = blocks.map(_stepId).toList();

      expect(
        blocks,
        isNotEmpty,
        reason: 'step-order: no steps parsed; has the layout changed?',
      );
      expect(
        _stepId(blocks.first),
        'refuse',
        reason:
            'step-order: the first step must be the refusal — including a step '
            'with no `id:`, which would still mint a credential. Found: $ids',
      );
      expect(
        ids.where((id) => id == 'refuse').length,
        1,
        reason:
            'step-order: exactly one step may be `refuse`; a decoy first and '
            'the real one last passes any check that only reads the first id. '
            'Found: $ids',
      );
      expect(
        RegExp(r'^\s+if:', multiLine: true).hasMatch(blocks.first),
        isFalse,
        reason:
            'step-order: the refusal must not be conditional — `if: false` '
            'leaves it first and stops it running',
      );
      expect(
        blocks.first,
        contains('exit 1'),
        reason: 'step-order: the first step does not refuse anything',
      );
      for (final later in const ['token', 'promote']) {
        expect(
          ids.indexOf(later),
          greaterThan(0),
          reason:
              'step-order: `$later` must run after the refusal, or a refused '
              'track reaches a credential. Found: $ids',
        );
      }
    },
  );

  test('the step-order rule catches each way it was defeated', () {
    // Every one of these passed the line-scan version with a green suite.
    const head = 'jobs:\n  a:\n    steps:\n';
    const refuse = '      - id: refuse\n        run: exit 1\n';
    const token = '      - id: token\n        run: mint\n';
    const promote = '      - id: promote\n        run: go\n';

    // 1. Disabled in place.
    const disabled =
        '$head      - id: refuse\n        if: false\n'
        '        run: exit 1\n$token$promote';
    expect(
      RegExp(r'^\s+if:', multiLine: true).hasMatch(_stepBlocks(disabled).first),
      isTrue,
      reason: 'step-order-negative: an `if:` on the refusal must be visible',
    );

    // 2. An id-less step slipped in front.
    const idless =
        '$head      - name: mint early\n        run: gcloud auth\n'
        '$refuse$token$promote';
    expect(
      _stepId(_stepBlocks(idless).first),
      isNot('refuse'),
      reason: 'step-order-negative: an id-less first step must not be missed',
    );

    // 3. A decoy carrying the same id, with the real refusal last.
    const decoy =
        '$head      - id: refuse\n        run: echo ok\n'
        '$token$promote      - id: refuse_real\n        run: exit 1\n';
    expect(
      _stepBlocks(decoy).map(_stepId).where((id) => id == 'refuse').length,
      1,
      reason: 'sanity: the decoy fixture has exactly one `refuse`',
    );
    expect(
      _stepBlocks(decoy).first,
      isNot(contains('exit 1')),
      reason: 'step-order-negative: a decoy that refuses nothing must be seen',
    );

    // And the shape that should pass.
    expect(_stepId(_stepBlocks('$head$refuse$token$promote').first), 'refuse');
  });
}
