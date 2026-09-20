@Tags(['guard'])
library;

// Guard for tools/play_release_codes.py, which had no test at all.
//
// It replaced a regex that got the job wrong two ways (#128), and then three
// more holes were found in the replacement (#163) — a negative code promoted
// as a version code, a malformed container reported as "no completed release",
// and a >4300-digit number crashing with the exit code that means "empty
// track". None of that was visible to `flutter test`, because nothing ran it.
//
// The contract, from the script's own docstring:
//   0  codes printed, space separated
//   1  no release with that status  (stdout empty)
//   2  stdin was not the JSON this expects  (stdout empty)

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'repo_files.dart';

String get _script => '${repoRoot.path}/tools/play_release_codes.py';

/// Runs the script with [json] on stdin, which `Process.runSync` cannot do
/// directly — so the JSON is piped in by a shell.
({int code, String out, String err}) _pipe(String json, {String? status}) {
  final r = Process.runSync(
    '/bin/bash',
    [
      '-c',
      'printf %s "\$1" | python3 "\$2" \$3',
      'bash',
      json,
      _script,
      status ?? '',
    ],
    stdoutEncoding: utf8,
    stderrEncoding: utf8,
  );
  return (code: r.exitCode, out: r.stdout.toString(), err: r.stderr.toString());
}

void main() {
  group('picks the newest release with the requested status', () {
    test('a release carrying release notes is not invisible', () {
      // The regex this replaced could not cross the `}` closing a nested
      // object, so a populated track reported "no completed release" (#128).
      final r = _pipe(
        '{"track":"internal","releases":[{"name":"1 (0.1.0)",'
        '"versionCodes":["101"],'
        '"releaseNotes":[{"language":"en-US","text":"hi"}],'
        '"status":"completed"}]}',
      );
      expect(r.code, 0, reason: r.err);
      expect(r.out.trim(), '101');
    });

    test('the newest is chosen, in either document order', () {
      const a =
          '{"releases":[{"versionCodes":["102"],"status":"completed"},'
          '{"versionCodes":["101"],"status":"completed"}]}';
      const b =
          '{"releases":[{"versionCodes":["101"],"status":"completed"},'
          '{"versionCodes":["102"],"status":"completed"}]}';
      expect(_pipe(a).out.trim(), '102');
      expect(_pipe(b).out.trim(), '102');
    });

    test('a status argument selects the draft release', () {
      const json =
          '{"releases":['
          '{"versionCodes":["101"],"status":"draft"},'
          '{"versionCodes":["9"],"status":"completed"}]}';
      expect(_pipe(json).out.trim(), '9');
      expect(_pipe(json, status: 'draft').out.trim(), '101');
    });

    test('every version code of the chosen release is printed, sorted', () {
      final r = _pipe(
        '{"releases":[{"versionCodes":["103","101","102"],"status":"completed"}]}',
      );
      expect(r.out.trim(), '101 102 103');
    });

    test('integer codes are accepted as well as strings', () {
      expect(
        _pipe('{"releases":[{"versionCodes":[101,102],"status":"completed"}]}')
            .out
            .trim(),
        '101 102',
      );
    });
  });

  group('refuses, with nothing on stdout', () {
    // The contract's whole point: a caller reading stdout must get nothing it
    // could mistake for a version code.
    void expectRefused(
      String why,
      String json,
      int expected, {
      String? status,
    }) {
      final r = _pipe(json, status: status);
      expect(r.code, expected, reason: '$why: ${r.err}');
      expect(
        r.out,
        isEmpty,
        reason: '$why: printed `${r.out}` on stdout while refusing',
      );
    }

    test('no release with the requested status is exit 1', () {
      expectRefused('no releases key', '{"kind":"x"}', 1);
      expectRefused('empty list', '{"releases":[]}', 1);
      expectRefused(
        'only a draft',
        '{"releases":[{"versionCodes":["9"],"status":"draft"}]}',
        1,
      );
      expectRefused(
        'no status field',
        '{"releases":[{"versionCodes":["9"]}]}',
        1,
      );
      expectRefused(
        'an empty code list',
        '{"releases":[{"versionCodes":[],"status":"completed"}]}',
        1,
      );
    });

    test('a negative code is refused, not promoted', () {
      // `-?[0-9]+` accepted `-5`, and it was PUT to the target track — the
      // plausible-wrong-code case the strict check exists to refuse (#163).
      expectRefused(
        'negative',
        '{"releases":[{"versionCodes":["-5"],"status":"completed"}]}',
        2,
      );
    });

    test('a malformed container is refused, not read as an empty track', () {
      // These used to `continue`, so the caller was told the track held
      // nothing when it held something unreadable (#163).
      expectRefused(
        'versionCodes is a string',
        '{"releases":[{"versionCodes":"101","status":"completed"}]}',
        2,
      );
      expectRefused('a release is a list', '{"releases":[[1,2]]}', 2);
      expectRefused('releases is an object', '{"releases":{}}', 2);
    });

    test('a code that is not a plain number is refused', () {
      for (final code in const [
        '"1_0_1"',
        '"１０１"',
        'true',
        '" 101 "',
        '101.0',
        '"0x65"',
        '"1e2"',
        '"+101"',
        'null',
      ]) {
        expectRefused(
          'code $code',
          '{"releases":[{"versionCodes":[$code],"status":"completed"}]}',
          2,
        );
      }
    });

    test('input that is not the expected JSON is exit 2', () {
      expectRefused('empty', '', 2);
      expectRefused('whitespace', '   ', 2);
      expectRefused('not json', 'not json', 2);
      expectRefused('a top-level array', '[1,2,3]', 2);
      expectRefused('trailing junk', '{"releases":[]}x', 2);
    });

    test('a very long number does not crash', () {
      // CPython refuses to parse an integer past 4300 digits, and the
      // ValueError escaped as exit 1 — the code meaning "no release with that
      // status", so a crash was reported as an empty track (#163).
      final huge = '1' * 5000;
      final r = _pipe(
        '{"releases":[{"versionCodes":["$huge"],"status":"completed"}]}',
      );
      expect(
        r.err,
        isNot(contains('Traceback')),
        reason: 'huge: crashed instead of answering',
      );
      expect(r.code, anyOf(0, 2), reason: 'huge: ${r.err}');
    });
  });
}
