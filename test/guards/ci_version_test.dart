@Tags(['guard'])
library;

// Guard for #20: a tag either maps to exactly one version, or it is refused
// before anything is built.
//
// The refusals are the substance. A release workflow that guesses at a
// malformed tag ships something nobody asked for, under a number nobody chose,
// to a track real testers read — and a version code cannot be withdrawn once
// Play has seen it. So every refusal asserts BOTH a non-zero exit and empty
// stdout: a caller that reads stdout must get nothing rather than a partial
// line it might parse.
//
// What this does NOT cover: whether the codes it computes are actually
// monotonic on Play. That depends on run numbers rising, which is GitHub's
// guarantee, not this script's.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'repo_files.dart';

const _script = 'tools/ci_version.sh';

({int code, String out, String err}) _run(List<String> args) {
  // chokepoint-exempt: runs ci_version.sh with a tag and two run numbers;
  // no secret is passed and its output is a version name and code.
  final r = Process.runSync(
    _script,
    args,
    workingDirectory: repoRoot.path,
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

  group('accepts', () {
    for (final entry in const {
      'v1.2.3': '1.2.3',
      'v0.1.0': '0.1.0',
      'v10.20.30': '10.20.30',
      'v0.9.0-rc.1': '0.9.0-rc.1',
      'v1.0.0-beta': '1.0.0-beta',
    }.entries) {
      test('${entry.key} maps to ${entry.value}', () {
        final r = _run([entry.key, '7', '1']);
        expect(r.code, 0, reason: 'accept-${entry.key}: ${r.err}');
        expect(r.out, contains('name=${entry.value}'));
      });
    }

    test('the code is 1000 + run*10 + attempt', () {
      expect(_run(['v1.0.0', '1', '1']).out, contains('code=1011'));
      expect(_run(['v1.0.0', '7', '2']).out, contains('code=1072'));
      expect(_run(['v1.0.0', '123', '9']).out, contains('code=2239'));
    });

    test('a re-run of a failed run ships a higher code', () {
      // The reason the formula has an attempt term at all.
      int codeOf(String o) =>
          int.parse(RegExp(r'code=(\d+)').firstMatch(o)!.group(1)!);
      final first = codeOf(_run(['v1.0.0', '40', '1']).out);
      final retry = codeOf(_run(['v1.0.0', '40', '2']).out);
      final nextRun = codeOf(_run(['v1.0.0', '41', '1']).out);
      expect(retry, greaterThan(first));
      expect(
        nextRun,
        greaterThan(retry),
        reason: 'codes must rise across runs as well as attempts',
      );
    });
  });

  group('refuses, silently on stdout', () {
    for (final bad in const [
      'v1.2',
      '1.2.3',
      'release-1',
      'v1.2.3.4',
      'va.b.c',
      'v1.2.3-',
      '',
      'vv1.2.3',
      'v1.2.3 ',
      // A newline used to pass: `grep -qE '^...$'` anchors each line, not the
      // whole string, so only the first line was validated and the rest rode
      // into `name=` and on into \$GITHUB_OUTPUT (#138).
      'v1.2.3\nv9.9.9',
      'v1.2.3\n',
      // Leading zeros are not semver, and shipped as name `01.2.3`.
      'v01.2.3',
      'v1.02.3',
      'v1.2.03',
    ]) {
      test('the ref `$bad`', () {
        final r = _run([bad, '7', '1']);
        expect(r.code, 2, reason: 'refuse-ref: `$bad` was accepted');
        expect(
          r.out.trim(),
          isEmpty,
          reason:
              'refuse-ref: `$bad` printed to stdout; a caller reading stdout '
              'must get nothing rather than something it might parse',
        );
      });
    }

    for (final entry in const {
      'run number 0': ['v1.0.0', '0', '1'],
      'run number -1': ['v1.0.0', '-1', '1'],
      'run number x': ['v1.0.0', 'x', '1'],
      'attempt 0': ['v1.0.0', '1', '0'],
      'attempt 10': ['v1.0.0', '1', '10'],
      // The arithmetic overflowed to a negative version code before this
      // bound existed; Android's ceiling is 2100000000 (#138).
      // The newline guard covered `ref` only; `run` and `attempt` kept the
      // per-line anchoring the header said was fixed, one screen below it.
      // `7\n8` exited 1 with a raw bash arithmetic error (#159).
      'run number with a trailing newline': ['v1.0.0', '7\n', '1'],
      'run number with a leading newline': ['v1.0.0', '\n7', '1'],
      'run number split by a newline': ['v1.0.0', '7\n8', '1'],
      'attempt with a trailing newline': ['v1.0.0', '7', '1\n'],
      'attempt split by a newline': ['v1.0.0', '7', '1\n2'],
      'run number of 9 digits': ['v1.0.0', '100000000', '1'],
      'run number that overflows': ['v1.0.0', '922337203685477581', '1'],
      'attempt x': ['v1.0.0', '1', 'x'],
    }.entries) {
      test(entry.key, () {
        final r = _run(entry.value);
        expect(r.code, 2, reason: '${entry.key} was accepted');
        expect(r.out, isEmpty);
      });
    }

    test('attempt 10 is refused because it would collide', () {
      // 1000 + N*10 + 10 equals 1000 + (N+1)*10 + 0. The bound is not
      // cosmetic, and a comment in the script says so.
      final r = _run(['v1.0.0', '1', '10']);
      expect(r.code, 2);
      expect(r.err.toLowerCase(), contains('attempt'));
    });

    for (final args in const [
      <String>[],
      ['v1.0.0'],
      ['v1.0.0', '1'],
    ]) {
      test('${args.length} argument(s)', () {
        final r = _run(args);
        expect(r.code, 2);
        expect(r.out, isEmpty);
      });
    }
  });

  group('the prerelease is validated to semver, not just to shape', () {
    // The ref pattern accepts any run of alphanumerics, dots and hyphens
    // after the `-`, and the leading-zero guard covers only the core triple.
    // So these three were accepted as version names (#180).
    for (final bad in const ['v1.2.3-rc.01', 'v1.2.3-00', 'v1.2.3-rc.1.']) {
      test('$bad is refused', () {
        final r = _run([bad, '7', '1']);
        expect(r.code, 2, reason: 'ci_version: $bad must be refused');
        expect(r.out, isEmpty, reason: 'nothing may reach stdout');
      });
    }

    // The complement: a validator that also refuses valid input is not a
    // working validator.
    for (final good in const [
      'v1.2.3',
      'v1.2.3-rc.1',
      'v1.2.3-alpha.beta.1',
      'v1.2.3-0',
      'v1.2.3-rc-1',
    ]) {
      test('$good is accepted', () {
        final r = _run([good, '7', '1']);
        expect(
          r.code,
          0,
          reason: 'ci_version: $good must be accepted: ${r.err}',
        );
        expect(r.out, contains('name=${good.substring(1)}'));
      });
    }
  });
}
