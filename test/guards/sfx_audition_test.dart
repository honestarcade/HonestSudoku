@Tags(['guard'])
library;

// Guard for `tools/sfx.py --audition` (#63): the loop that stages each sound
// candidate into assets/audio/ and runs a release build on the phone. The
// property that matters is the one nobody listens for: however the loop
// ends, assets/audio/ is left exactly as it was, so a candidate can never be
// committed or shipped by accident.
//
// The script is copied into a temporary tree and run there, so ROOT (the
// script's own parent's parent) is the temporary tree and the repository's
// assets are never touched. `flutter` is a stub on PATH that records its
// arguments and what it found staged.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'leak_scan.dart';
import 'repo_files.dart';

const _fakeFlutter = r'''#!/bin/sh
n=$(($(cat "$HS_FAKE_DIR/calls" 2>/dev/null || echo 0) + 1))
echo "$n" > "$HS_FAKE_DIR/calls"
# Reads a line, as `flutter run` does, so stdin left open eats a keypress.
read -r _ || true
if [ -f assets/audio/place.wav ]; then
  staged=$(cksum < assets/audio/place.wav)
else
  staged=none
fi
echo "$* | $staged" >> "$HS_FAKE_DIR/log"
[ "$n" = "${HS_FAKE_FAIL_ON:-0}" ] && exit 1
exit 0
''';

/// A temporary tree holding the script, the placeholder and three takes.
class _Tree {
  _Tree() : dir = Directory.systemTemp.createTempSync('hs-sfx-audition') {
    Directory('${dir.path}/tools').createSync();
    File('${repoRoot.path}/tools/sfx.py').copySync('${dir.path}/tools/sfx.py');
    Directory('${dir.path}/assets/audio').createSync(recursive: true);
    Directory('${dir.path}/takes').createSync();
    Directory('${dir.path}/fake').createSync();
    Directory('${dir.path}/bin').createSync();
    File('${dir.path}/bin/flutter').writeAsStringSync(_fakeFlutter);
    makeExecutable('${dir.path}/bin/flutter');
    placeholder.writeAsBytesSync(_audio('placeholder-place.wav'));
    // Three different takes, numbered so that v10 must sort after v2.
    _take('place-v1.wav', _audio('placeholder-place.wav'));
    _take('place-v2.wav', _audio('placeholder-mistake.wav'));
    _take('place-v10.wav', _audio('placeholder-solve.wav'));
  }

  final Directory dir;

  File get placeholder =>
      File('${dir.path}/assets/audio/placeholder-place.wav');
  File get staged => File('${dir.path}/assets/audio/place.wav');
  File get selections => File('${dir.path}/takes/selections.json');

  static List<int> _audio(String name) =>
      File('${repoRoot.path}/assets/audio/$name').readAsBytesSync();

  void _take(String name, List<int> bytes) =>
      File('${dir.path}/takes/$name').writeAsBytesSync(bytes);

  /// The stub's log: one line per `flutter` call.
  List<String> get calls {
    final log = File('${dir.path}/fake/log');
    return log.existsSync()
        ? log.readAsLinesSync().where((l) => l.isNotEmpty).toList()
        : const [];
  }

  /// Runs `--audition` with [input] on stdin.
  ({int code, String out, String err}) run(
    String input, {
    List<String> args = const ['--audition', 'place'],
    int failOn = 0,
  }) {
    final r = runSealed(
      '/bin/bash',
      [
        '-c',
        r'printf %s "$1" | python3 "$2" "${@:3}"',
        'bash',
        input,
        '${dir.path}/tools/sfx.py',
        ...args,
        '--dir',
        '${dir.path}/takes',
        '--device',
        'SERIAL-7',
      ],
      workingDirectory: dir.path,
      environment: {
        'PATH': '${dir.path}/bin:${Platform.environment['PATH'] ?? ''}',
        'HS_FAKE_DIR': '${dir.path}/fake',
        'HS_FAKE_FAIL_ON': '$failOn',
      },
    );
    return (
      code: r.exitCode,
      out: r.stdout.toString(),
      err: r.stderr.toString(),
    );
  }

  /// assets/audio/ holds exactly the placeholder, byte for byte.
  void expectRestored(String rule, {List<int>? staged}) {
    final names = Directory('${dir.path}/assets/audio')
        .listSync()
        .map((e) => e.uri.pathSegments.last)
        .toSet();
    expect(
      names,
      staged == null
          ? {'placeholder-place.wav'}
          : {'placeholder-place.wav', 'place.wav'},
      reason: '$rule left assets/audio/ holding $names',
    );
    expect(
      placeholder.readAsBytesSync(),
      _audio('placeholder-place.wav'),
      reason: '$rule changed placeholder-place.wav',
    );
    if (staged != null) {
      expect(
        this.staged.readAsBytesSync(),
        staged,
        reason: '$rule did not put the existing place.wav back byte for byte',
      );
    }
  }
}

void main() {
  late _Tree tree;
  setUp(() => tree = _Tree());
  tearDown(() => tree.dir.deleteSync(recursive: true));

  test('each candidate is built in turn, then the pick is recorded', () {
    final r = tree.run('\n\n\n2\n');
    expect(r.code, 0, reason: 'sfx-audition: exited ${r.code}: ${r.err}');

    final calls = tree.calls;
    expect(calls, hasLength(3), reason: 'sfx-audition: $calls');
    for (final call in calls) {
      expect(
        call,
        startsWith('run --release --no-resident -d SERIAL-7 | '),
        reason: 'sfx-audition: not a release build on the named device: $call',
      );
    }
    final seen = [for (final c in calls) c.split(' | ').last];
    expect(
      seen,
      everyElement(isNot('none')),
      reason: 'sfx-audition: a build ran with no candidate staged: $calls',
    );
    expect(
      seen.toSet(),
      hasLength(3),
      reason: 'sfx-audition: the three builds did not each stage a new take',
    );
    final order = RegExp(r'now playing (place-v\d+\.wav)')
        .allMatches(r.out)
        .map((m) => m[1])
        .toList();
    expect(order, [
      'place-v1.wav',
      'place-v2.wav',
      'place-v10.wav',
    ], reason: 'sfx-audition: candidates out of variant order: $order');

    expect(
      tree.selections.existsSync()
          ? jsonDecode(tree.selections.readAsStringSync())
          : null,
      {'place': 'place-v2.wav'},
      reason: 'sfx-audition: the pick was not recorded: ${r.out}',
    );
    tree.expectRestored('sfx-audition: a finished audition');
  });

  test('a failed build stops the loop and still restores the tree', () {
    final r = tree.run('\n\n\n2\n', failOn: 2);
    expect(r.code, 1, reason: 'sfx-audition: a failed build exited ${r.code}');
    expect(tree.calls, hasLength(2), reason: 'sfx-audition: ${tree.calls}');
    expect(tree.selections.existsSync(), isFalse);
    tree.expectRestored('sfx-audition: a failed build');
  });

  test('stopping early, or stdin closing, still restores the tree', () {
    expect(tree.run('q\n').code, 0);
    expect(tree.calls, hasLength(1));
    tree.expectRestored('sfx-audition: q after the first take');

    expect(tree.run('').code, 0);
    expect(tree.calls, hasLength(2));
    tree.expectRestored('sfx-audition: stdin closed');
    expect(tree.selections.existsSync(), isFalse);
  });

  test('a clip already installed is put back byte for byte', () {
    final real = List<int>.of(tree.placeholder.readAsBytesSync())..[60] ^= 1;
    tree.staged.writeAsBytesSync(real);
    expect(tree.run('\n\n\n\n').code, 0);
    tree.expectRestored(
      'sfx-audition: an audition over an installed clip',
      staged: real,
    );
  });

  test('a pick that was not heard is refused and not recorded', () {
    final r = tree.run('\n\n\n7\n');
    expect(r.code, 1, reason: 'sfx-audition: accepted an unheard pick');
    expect(tree.selections.existsSync(), isFalse);
    tree.expectRestored('sfx-audition: a refused pick');
  });

  test('bad arguments are refused before anything is staged or built', () {
    for (final (why, args) in [
      ('an unknown clip', ['--audition', 'beep']),
      (
        '--audition with --install',
        ['--audition', 'place', '--install', 'place', 'x.wav'],
      ),
      ('a clip with no candidates', ['--audition', 'lose']),
    ]) {
      final r = tree.run('\n', args: args);
      expect(r.code, 2, reason: 'sfx-audition-args: $why exited ${r.code}');
      expect(
        tree.calls,
        isEmpty,
        reason: 'sfx-audition-args: $why still ran flutter',
      );
      tree.expectRestored('sfx-audition-args: $why');
    }
  });
}
