@Tags(['guard'])
library;

// Guards on the guard: `leak_scan.dart` is where every process a guard starts
// is scanned or sealed, so what is asserted here is that it can see a leak on
// each channel it claims to read, that a sealed call really is sealed, and
// that nothing under `test/` starts a process anywhere else.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'leak_scan.dart';
import 'repo_files.dart';

/// Files that still start a process outside `leak_scan.dart`, with how many
/// starts each holds. The rule below asserts the offenders EQUAL this map, so
/// a new start anywhere fails, and so does a migrated one whose entry was not
/// brought down.
const pendingMigration = <String, int>{
  'test/guards/bundle_scan_test.dart': 5,
  'test/guards/ci_version_test.dart': 1,
  'test/guards/fonts_guard_test.dart': 1,
  'test/guards/guard_hygiene_test.dart': 1,
  'test/guards/play_promote_args_test.dart': 9,
  'test/guards/play_release_codes_test.dart': 1,
  'test/guards/repo_files.dart': 1,
  'test/guards/signing_guard_test.dart': 7,
  'test/guards/workflow_guard_test.dart': 5,
};

/// The functions in `leak_scan.dart` allowed to start a process, each found
/// by the line that opens it.
const _chokepoints = {
  'LeakScan.run': 'LeakRun run(',
  'runSealed': 'ProcessResult runSealed(',
  'makeExecutable': 'void makeExecutable(',
};

/// A process start: the class itself, a tear-off, a typedef alias or an
/// `io.`-prefixed use, but not the result, exception, signal or mode types.
final _startsProcess = RegExp(
  r'\bProcess\b(?!Result|Exception|Signal|StartMode|Info)',
);
final _processPackage = RegExp(r'''import\s+['"]package:process/''');

late Directory _tmp;

/// Distinctive, and long enough for every transformed form to be searched.
const _canary = 'CANARY-s3cret-9x7q';
const _isolation = 'ISOLATION-s3cret-4k2m';

final _scan = LeakScan(
  roots: () => ['${_tmp.path}/root'],
  argvLogs: {'probe.log': () => '${_tmp.path}/probe.log'},
  scratch: () => '${_tmp.path}/scratch',
);

void main() {
  setUp(() {
    _tmp = Directory.systemTemp.createTempSync('hs-leak-scan');
    Directory('${_tmp.path}/root').createSync();
  });
  tearDown(() => _tmp.deleteSync(recursive: true));

  group('the scan sees a secret on every channel it reads', () {
    /// Runs [script] with the canary bound to a secret-shaped name and
    /// asserts the scan fails naming [where].
    void canary(
      String channel,
      String where,
      String script, {
      List<String> extraArgs = const [],
      bool fromRoot = false,
    }) {
      test('on $channel', () {
        if (fromRoot) {
          addTearDown(() {
            final left = File('${repoRoot.path}/hs-leak-canary.txt');
            if (left.existsSync()) left.deleteSync();
          });
        }
        expect(
          () => _scan.run(
            '/bin/sh',
            ['-c', script, 'sh', ...extraArgs],
            environment: {
              'PATH': '/usr/bin:/bin',
              'HS_CANARY_PASS': _canary,
              'HS_ROOT': '${_tmp.path}/root',
              'HS_LOG': '${_tmp.path}/probe.log',
            },
            workingDirectory: fromRoot ? repoRoot.path : _tmp.path,
            why: 'canary',
          ),
          throwsA(
            isA<TestFailure>().having(
              (f) => f.message,
              'message',
              contains('reached $where'),
            ),
          ),
          reason:
              'leak-canary: $channel — a secret written there was not found, '
              'so the scan has stopped reading that channel',
        );
      });
    }

    canary('stdout', 'stdout', r'echo "$HS_CANARY_PASS"');
    canary('stderr', 'stderr', r'echo "$HS_CANARY_PASS" >&2');
    canary('file bytes', 'file ', r'echo "$HS_CANARY_PASS" > "$HS_ROOT/x"');
    canary('file name', 'the name of ', r'touch "$HS_ROOT/$HS_CANARY_PASS"');
    canary(
      'untracked workspace file',
      r'file $GITHUB_WORKSPACE/hs-leak-canary.txt',
      r'echo "$HS_CANARY_PASS" > "$PWD/hs-leak-canary.txt"',
      fromRoot: true,
    );
    canary(
      'argv log',
      'probe.log (recorded argv)',
      r'echo "stub $HS_CANARY_PASS" >> "$HS_LOG"',
    );
    canary('own argv', 'its own command line', ':', extraArgs: [_canary]);
  });

  group('runSealed', () {
    test('hands the child nothing it was not given', () {
      final parent = Platform.environment.keys
          .where((k) => k != 'PATH' && k != 'HOME')
          .toList();
      expect(
        parent,
        isNotEmpty,
        reason:
            'leak-sealed: this process has no environment beyond PATH and '
            'HOME, so nothing here can show whether a sealed child inherits',
      );
      final r = runSealed('/usr/bin/env', const []);
      final got = {
        for (final line in r.stdout.toString().split('\n'))
          if (line.contains('=')) line.substring(0, line.indexOf('=')),
      };
      expect(
        got.intersection(parent.toSet()),
        isEmpty,
        reason:
            'leak-sealed: runSealed passed the parent environment through. '
            "On CI that includes the guard job's token",
      );
    });

    test('refuses a secret-shaped name', () {
      expect(
        () => runSealed(
          '/usr/bin/env',
          const [],
          environment: const {'HS_PROBE_TOKEN': 'not-a-real-token'},
        ),
        throwsA(
          isA<TestFailure>().having(
            (f) => f.message,
            'message',
            contains('leak-sealed'),
          ),
        ),
        reason:
            'leak-sealed: runSealed accepted a secret-shaped environment '
            'name, so a secret can reach a call nothing scans',
      );
    });
  });

  group('sentinels are per test', () {
    test('a sentinel declared here is live here', () {
      _scan.declare(const {'HS_ISOLATION_PASS': _isolation});
      expect(
        _scan.isLive(_isolation),
        isTrue,
        reason: 'sentinel-isolation: declare did not make the value live',
      );
    });

    test('and is gone in the next test', () {
      expect(
        _scan.isLive(_isolation),
        isFalse,
        reason:
            'sentinel-isolation: the previous test left its sentinel live, '
            'so its value would read as a leak in unrelated output',
      );
    });
  });

  test('a fixture too short for the transformed forms is refused', () {
    // The floor is asserted at its boundary: seven refused, eight accepted.
    expect(
      () => _scan.declare(const {'a probe': 'seven77'}),
      throwsA(
        isA<TestFailure>().having(
          (f) => f.message,
          'message',
          contains('leak-fixture'),
        ),
      ),
      reason:
          'fixture-floor: a seven-character fixture was accepted as a '
          'sentinel, and only its verbatim form will ever be searched',
    );
    _scan.declare(const {'a probe': 'eight888'});
    expect(
      _scan.isLive('eight888'),
      isTrue,
      reason: 'fixture-floor: an eight-character fixture was refused',
    );
  });

  test('every allowance is registered, reasoned and used exactly once', () {
    final used = <String, List<String>>{};
    for (final file in _dartFilesUnderTest()) {
      final relative = file.path.substring(repoRoot.path.length + 1);
      final source = stripDartComments(file.readAsStringSync());
      for (final m in RegExp(r'allow:\s*\[([^\]]*)\]').allMatches(source)) {
        for (final id in RegExp(r'''['"]([^'"]+)['"]''').allMatches(m[1]!)) {
          (used[id[1]!] ??= []).add(relative);
        }
      }
    }
    final problems = <String>[
      for (final MapEntry(key: id, value: files) in used.entries)
        if (!leakAllowances.containsKey(id))
          '`$id` is used in ${files.join(', ')} and is not registered'
        else if (files.length != 1 || files.single != leakAllowances[id]!.file)
          '`$id` is registered for ${leakAllowances[id]!.file} and used in '
              '${files.join(', ')}',
      for (final MapEntry(key: id, value: a) in leakAllowances.entries) ...[
        if (!used.containsKey(id)) '`$id` is registered and used nowhere',
        if (a.reason.trim().length < 20)
          '`$id` gives no reason for letting a secret through',
        if (!const {
          'stdout',
          'stderr',
          'argv',
          'log',
          'file',
          'name',
          'workspace',
        }.contains(a.channel))
          '`$id` names `${a.channel}`, which is not a channel',
      ],
    ];
    expect(
      problems,
      isEmpty,
      reason:
          'leak-allowance: an allowance lets one secret through on one '
          'channel of one call, so the registry and the calls must agree:\n'
          '${problems.join('\n')}',
    );
  });

  test('nothing under test/ starts a process except through leak_scan.dart', () {
    const helper = 'test/guards/leak_scan.dart';
    final offenders = <String, List<int>>{};
    for (final file in _dartFilesUnderTest()) {
      final relative = file.path.substring(repoRoot.path.length + 1);
      final source = stripDartComments(file.readAsStringSync());
      final lines = source.split('\n');
      final exempt = relative == helper ? _measuredBodies(lines) : <int>{};
      for (var i = 0; i < lines.length; i++) {
        if (exempt.contains(i)) continue;
        final hits =
            _startsProcess.allMatches(lines[i]).length +
            _processPackage.allMatches(lines[i]).length;
        for (var n = 0; n < hits; n++) {
          (offenders[relative] ??= []).add(i + 1);
        }
      }
    }
    expect(
      {for (final e in offenders.entries) e.key: e.value.length},
      equals(pendingMigration),
      reason:
          'leak-chokepoint: these start a process outside LeakScan.run, '
          'runSealed and makeExecutable, so nothing derives their secrets or '
          'scans their output, and a comment beside one exempts nothing. '
          'Route the call through leak_scan.dart, or bring its '
          'pendingMigration entry down when it has been:\n'
          '${offenders.entries.map((e) => '  ${e.key} lines ${e.value.join(', ')}').join('\n')}',
    );
  });
}

Iterable<File> _dartFilesUnderTest() =>
    Directory('${repoRoot.path}/test')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'));

/// The line indices of each chokepoint's body, measured from the line that
/// opens it to the first line closing at the same indentation.
Set<int> _measuredBodies(List<String> lines) {
  final body = <int>{};
  _chokepoints.forEach((name, opening) {
    final start = lines.indexWhere((l) => l.contains(opening));
    expect(
      start,
      isNot(-1),
      reason: 'leak-chokepoint: `$name` is gone from leak_scan.dart',
    );
    final indent = RegExp(r'^\s*').stringMatch(lines[start])!;
    final end = lines.indexWhere((l) => l == '$indent}', start);
    expect(
      end,
      isNot(-1),
      reason: 'leak-chokepoint: could not find the end of `$name`',
    );
    for (var i = start; i <= end; i++) {
      body.add(i);
    }
  });
  return body;
}
