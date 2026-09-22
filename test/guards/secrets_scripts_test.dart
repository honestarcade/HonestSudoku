@Tags(['guard'])
library;

// Guard for #19's three artefacts: the two credential scripts and the Play
// API check workflow.
//
// None of them had a test. #126 said so in its own "why it survived"
// paragraph, the fix added none, and the next round found three more defects
// in the same surface (#143's trailing-comment corruption, the PKCS12 keypass
// no-op, the empty-tracks failure). The harnesses that found those were built
// for a review and thrown away, so every round started from nothing (#149).
//
// Everything here runs against a fake `HOME`, stub `gh`/`gcloud` on `PATH`,
// and — where a keystore is needed — a throwaway one this test creates. No
// real credential is read, and nothing leaves the machine. The stubs record
// byte LENGTHS, never values.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'repo_files.dart';
import 'workflow_yaml.dart';

late Directory _tmp;

String get _home => '${_tmp.path}/home';
String get _credentials =>
    '$_home/HonestArcadeApps/secrets/sudoku-signing-credentials.txt';
String get _ghLog => '${_tmp.path}/gh.log';

/// Scratch space handed to every script, inside the scanned tree.
String get _scratch => '${_tmp.path}/scratch';

void _writeExecutable(String path, String body) {
  File(path)
    ..createSync(recursive: true)
    ..writeAsStringSync(body);
  Process.runSync('chmod', ['+x', path]);
}

/// Values that must never appear anywhere a script can write.
///
/// **Derived, not registered.** The previous version asked each test to call
/// `_plant`, and `_plant` was called in exactly two places — so `_run` scanned
/// on every invocation over an empty set for every other test, and rows 3 and
/// 4 of #176's table survived in a group that planted nothing. "A test cannot
/// forget to check" was true of the scan and false of the planting (#200).
///
/// So the sentinels come from the environment the script is actually handed,
/// plus the credentials file it is pointed at. A test that passes a secret is
/// scanned for that secret because it passed it, and there is no separate
/// step to leave out.
final Set<String> _sentinels = {};

/// Sentinels whose home IS the credentials file.
///
/// That file exists to hold these values, so finding them there is not a
/// leak. The previous version excluded the whole file unconditionally, which
/// any script could write any other secret into (#200) — this excludes the
/// values that came from it and nothing else, so a private key appended to
/// the same file is still caught.
final Set<String> _credentialSentinels = {};

/// Environment variable names whose VALUES are secrets.
///
/// Anything ending in these, so `HS_KEYSTORE_PASS`, `KEYSTORE_PASS` and
/// `HS_STUB_PASS` are all covered without listing each.
const _secretSuffixes = [
  'PASS',
  'PASSWORD',
  'SECRET',
  'TOKEN',
  'KEY',
  'B64',
  'JSON',
];

// Deliberately NOT here: ALIAS. The upload key's alias is public by design —
// android/signing/README.md publishes it beside the certificate fingerprint,
// and keytool takes it on the command line because it is not a secret.
// Treating it as one made every legitimate `-alias upload` a leak (#200).

bool _looksSecret(String name) {
  final upper = name.toUpperCase();
  return _secretSuffixes.any(upper.endsWith);
}

/// Adds every secret-shaped value in [env], and the contents of the
/// credentials file if one exists, to the scan set.
/// The variables the credentials file exists to carry.
///
/// A value derived from one of these is at home in that file. Anything else
/// found there — a service-account private key, say — is a leak, so the
/// exclusion cannot be abused by appending to it (#200).
const _credentialHomed = {
  'HS_KEYSTORE_PASS',
  'HS_KEY_PASS',
  'HS_KEY_ALIAS',
  'HS_KEYSTORE_PATH',
};

void _deriveSentinels(Map<String, String> env) {
  for (final entry in env.entries) {
    if (!_looksSecret(entry.key)) continue;
    _addSentinel(entry.value, entry.key);
    if (_credentialHomed.contains(entry.key.toUpperCase())) {
      _credentialSentinels.add(entry.value.trim());
    }
  }
  final creds = File(_credentials);
  if (creds.existsSync()) {
    // Four spellings, not one. The previous pattern required a double quote
    // immediately before end-of-line, so a single-quoted value, an unquoted
    // value and a value followed by a trailing comment all derived NOTHING —
    // and the three tests written for those spellings scanned an empty
    // sentinel set and passed by asserting about nothing (#208).
    for (final m in RegExp(
      r'''^\s*export\s+(\w+)=(?:"([^"]*)"|'([^']*)'|([^\s#]+))''',
      multiLine: true,
    ).allMatches(creds.readAsStringSync())) {
      // By NAME, like the environment above. The file also carries
      // HS_KEYSTORE_PATH, which is a path the scripts print in error
      // messages on purpose — treating every exported value as a secret made
      // "the keystore named here is not readable: /nonexistent" a leak.
      if (!_looksSecret(m.group(1)!)) continue;
      final value = m.group(2) ?? m.group(3) ?? m.group(4) ?? '';
      _addSentinel(value, 'credentials file');
      if (_credentialHomed.contains(m.group(1)!.toUpperCase())) {
        _credentialSentinels.add(value.trim());
      }
    }
  }
}

/// A value too short to search for is a hole, not a pass.
///
/// `_plant` silently dropped anything under six characters, and the pre-flight
/// group's fixture password is `"pw"` — so that group's scan was doubly dead.
/// A fixture that cannot be scanned for now fails loudly rather than
/// disabling the check it was written for (#200).
void _addSentinel(String value, String where) {
  final v = value.trim();
  if (v.isEmpty) return;
  // Eight, to match `_leakForms`: below eight only the verbatim form is
  // searched, so a seven-character fixture piped through `base64` would walk
  // past the scan while the fixture looked covered. The floor here was four
  // — long enough that a verbatim match means something, and exactly the gap
  // #220 demonstrated and asked to close (#230).
  if (v.length < 8) {
    fail(
      'leak-fixture: the value of `$where` is ${v.length} character(s); the '
      'transformed forms are searched from eight. Give the fixture a longer '
      'distinctive value — a short one silently disables most of the leak '
      'scan for this test',
    );
  }
  _sentinels.add(v);
}

/// Every form of [secret] a script could emit instead of the literal.
///
/// A leak does not have to be faithful to be a leak. The previous set was five
/// fixed forms, so rot13, gzip, URL-encoding, case folding, the LAST eight
/// characters and a value split across two writes all walked past it (#200).
///
/// This cannot be complete — no fixed set can be — so the forms here are the
/// ones reachable with a single shell builtin or a command these scripts
/// already use. The honest statement of scope is in the issue, not in a
/// comment claiming the property is general.
Iterable<({String form, String how})> _leakForms(String secret) sync* {
  yield (form: secret, how: 'verbatim');
  // Transformed forms only for values long enough that a match means
  // something. A four-character password is searched verbatim, but its
  // LOWERCASED form is four ordinary letters: `Pass` lowercased matched
  // `-storepass:env` in recorded keytool argv and failed eight tests that
  // had nothing to do with a leak. Lowering the floor from six to four made
  // that strictly more likely, and the guard broke on a real short password
  // rather than on a real leak (#208).
  if (secret.length < 8) return;
  yield (form: base64.encode(utf8.encode(secret)), how: 'base64');
  yield (form: secret.split('').reversed.join(), how: 'reversed');
  yield (
    form: utf8
        .encode(secret)
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join(),
    how: 'hex',
  );
  yield (form: secret.toLowerCase(), how: 'lowercased');
  yield (form: secret.toUpperCase(), how: 'uppercased');
  yield (form: _rot13(secret), how: 'rot13');
  yield (form: Uri.encodeComponent(secret), how: 'URL-encoded');
  // A slice is only evidence if the slice itself is distinctive. The tail of
  // `S3CRET-store-password` is the word `password`, which appears in the
  // keystore step's own English explanation — so the slice matched ordinary
  // prose and reported a leak that had not happened (#208). Requiring a
  // digit or punctuation in the slice keeps it a fingerprint rather than a
  // dictionary lookup.
  bool distinctive(String f) => RegExp(r'[^A-Za-z]').hasMatch(f);
  if (secret.length >= 8) {
    final head = secret.substring(0, 8);
    final tail = secret.substring(secret.length - 8);
    if (distinctive(head)) {
      yield (form: head, how: 'its first 8 characters');
    }
    if (distinctive(tail)) {
      yield (form: tail, how: 'its last 8 characters');
    }
  }
}

String _rot13(String s) => String.fromCharCodes(
  s.codeUnits.map((c) {
    if (c >= 0x41 && c <= 0x5A) return (c - 0x41 + 13) % 26 + 0x41;
    if (c >= 0x61 && c <= 0x7A) return (c - 0x61 + 13) % 26 + 0x61;
    return c;
  }),
);

/// Everything a script wrote that a human or another process could read.
///
/// `$HOME` alone was not enough: `$RUNNER_TEMP` is where these workflows put
/// the decoded keystore, `/tmp` is where a debugging dump naturally lands, and
/// the scripts `cd` to the repository root (#200).
List<({String where, String text, String path})> _channels(
  String out,
  String err,
) {
  final channels = <({String where, String text, String path})>[
    (where: 'stdout', text: out, path: ''),
    (where: 'stderr', text: err, path: ''),
  ];
  for (final log in const ['gh.log', 'keytool.log', 'gcloud.log', 'curl.log']) {
    final f = File('${_tmp.path}/$log');
    if (f.existsSync()) {
      channels.add((
        where: '$log (recorded argv)',
        text: f.readAsStringSync(),
        path: f.path,
      ));
    }
  }
  // The repository root is the scripts' WORKING DIRECTORY — `_exec` passes it
  // — and it was not scanned, though this list's own comment cited "the
  // scripts cd to the repository root" as a reason for the list. A password
  // written to `$PWD` was invisible, and on CI that directory is
  // $GITHUB_WORKSPACE, which upload-artifact and actions/cache sweep (#208).
  //
  // Only files the run CREATED are read: the repository is full of committed
  // text, and reading all of it would be slow and would match on prose.
  for (final dir in [_home, _scratch, '${_tmp.path}/runner', _tmp.path]) {
    // `$RUNNER_TEMP/play-sa.json` is where the play step is SUPPOSED to put
    // the service-account key: written with umask 077 and removed by the
    // workflow's `forget` step, which `if: always()` guarantees runs. That
    // file being there is the step working, not a leak — the same
    // distinction the credentials file gets, and drawn by path identity so
    // nothing else can hide behind it (#208).
    _collectFiles(Directory(dir), channels);
  }
  _collectWorkspaceLeaks(channels);
  return channels;
}

/// Files a run left in the repository root, which is its working directory.
///
/// `_exec` passes `workingDirectory: repoRoot.path`, and that directory was
/// not scanned though `_channels`'s own comment cited "the scripts cd to the
/// repository root" as a reason for its list. A password written to `$PWD`
/// was invisible, and on CI that directory is $GITHUB_WORKSPACE, which
/// upload-artifact and actions/cache sweep (#208).
///
/// Only the TOP LEVEL, and only files git does not already track: the
/// repository is full of committed text that would match on prose, and
/// `build/` alone is tens of megabytes. A script that writes a secret into
/// the workspace writes it where it is standing.
void _collectWorkspaceLeaks(
  List<({String where, String text, String path})> channels,
) {
  // Computed HERE, per scan, not once for the whole suite (#227).
  final unmodified = _unmodifiedAtRoot();
  for (final entity in repoRoot.listSync()) {
    if (entity is! File) continue;
    final name = entity.path.substring(repoRoot.path.length + 1);
    if (unmodified.contains(name)) continue;
    // latin1 over the bytes, like the `$RUNNER_TEMP` scan below and for the
    // same reason: `readAsStringSync` throws on the first byte that is not
    // valid UTF-8, and skipping the file then hides everything else in it —
    // a secret plus one junk byte is invisible. The sibling scan learned
    // this in #200; this one still had the swallow at #236.
    final text = latin1.decode(entity.readAsBytesSync(), allowInvalid: true);
    channels.add((
      where: 'file \$GITHUB_WORKSPACE/$name',
      text: text,
      path: entity.path,
    ));
  }
}

/// Top-level files whose content still matches the index, AT SCAN TIME.
///
/// The previous version was a lazy `final`: both git queries ran ONCE, on
/// first use, before any script under test had modified anything. So a file a
/// script overwrote DURING the run was not modified yet when the set was
/// built, stayed in the skip set, and was never read — while the docstring
/// claimed the opposite (#227).
///
/// Measured: on a clean tree the leak was invisible, and the same tree went
/// red on a second run purely because the first run's debris made the file
/// modified before the set was computed. A guard whose verdict depends on
/// leftover state is worse than no guard, because it looks like one.
///
/// A function, therefore, called per scan. `git ls-files --modified` is a
/// stat-and-hash over a dozen root files; that cost is not worth a cache that
/// is wrong.
Set<String> _unmodifiedAtRoot() {
  Set<String> topLevel(String out) => {
    for (final line in out.split('\n'))
      if (!line.contains('/') && line.isNotEmpty) line,
  };
  // chokepoint-exempt: reads the git index to tell a committed file from one
  // a script created or overwrote; passes no secret and its output is a list
  // of file names.
  final tracked = Process.runSync(
    'git',
    ['ls-files'],
    workingDirectory: repoRoot.path,
    stdoutEncoding: utf8,
  );
  // chokepoint-exempt: reads which tracked files differ from the index, so a
  // committed file a run overwrote is scanned rather than skipped; handles no
  // secret and its output is a list of names.
  final modified = Process.runSync(
    'git',
    ['ls-files', '--modified'],
    workingDirectory: repoRoot.path,
    stdoutEncoding: utf8,
  );
  return topLevel(tracked.stdout.toString())
    ..removeAll(topLevel(modified.stdout.toString()));
}

void _collectFiles(
  Directory dir,
  List<({String where, String text, String path})> channels,
) {
  if (!dir.existsSync()) return;
  for (final entity in dir.listSync(recursive: true)) {
    if (entity is! File) continue;
    // Skip the harness's own fixtures. `bin/` holds the stub executables this
    // file writes, and a stub that echoes a value it was given is the test
    // working, not a script leaking.
    if (entity.path.startsWith('${_tmp.path}/bin/')) continue;
    // The blanket `.sh` exemption this replaces was an unbounded suffix rule
    // justified as "the harness's own fixtures": a secret written to
    // `$RUNNER_TEMP/dump.sh` anywhere in the tree was exempt (#208). Scope it
    // to the directory the fixtures are actually in.
    if (entity.path.startsWith('${_tmp.path}/fixtures/')) continue;
    String text;
    try {
      text = entity.readAsStringSync();
    } catch (_) {
      // Not UTF-8. Read the BYTES instead of skipping: the previous version
      // skipped any unreadable file, so two junk bytes in front of a secret
      // hid it completely, while the comment claimed only keystores were
      // skipped (#200).
      try {
        text = latin1.decode(entity.readAsBytesSync(), allowInvalid: true);
      } catch (_) {
        continue;
      }
    }
    // PATH IDENTITY, which is what the comment above already claimed. The
    // suffix form exempted `$RUNNER_TEMP/keep/play-sa.json` too — a copy the
    // workflow's `forget` step does not remove, so it survives the job (#208).
    if (entity.path == '${_tmp.path}/runner/play-sa.json') continue;
    if (entity.path == '$_scratch/runner/play-sa.json') continue;
    channels.add((
      where: 'file ${entity.path.replaceFirst(_home, r'$HOME')}',
      text: text,
      path: entity.path,
    ));
  }
}

/// Fails if any derived value, in any of its forms, reached any channel.
void _assertNoLeak(String out, String err, String why) {
  final channels = _channels(out, err);
  for (final secret in _sentinels) {
    final ownHome = _credentialSentinels.contains(secret);
    for (final form in _leakForms(secret)) {
      if (form.form.length < 4) continue;
      for (final channel in channels) {
        // The credentials file is this value's own home, and only for values
        // that came from it.
        // Compared on the real path: `where` is rewritten for display, so
        // matching on it silently never fired.
        // The file holds an escaped spelling, so the raw value and the
        // written one differ as strings — match on the value's home, not on
        // the exact bytes.
        if (ownHome && channel.path == _credentials) continue;
        expect(
          channel.text,
          isNot(contains(form.form)),
          reason:
              'leak: $why — a secret reached ${channel.where}'
              '${form.how == 'verbatim' ? '' : ' (as ${form.how})'}',
        );
      }
    }
  }
}

/// The ONE way this file starts a process that handles a secret.
///
/// #200 moved the leak scan into `_run` and claimed "there is no registration
/// step left to leave out". There was: `_run` is not how the workflow steps
/// are tested. Four groups built their own `Process.runSync` and never
/// reached the scan, so `PLAY_SERVICE_ACCOUNT_JSON` echoed into
/// `$GITHUB_STEP_SUMMARY` — rendered, retained, downloadable — passed with
/// 404 green (#208).
///
/// The hole did not close; it moved from "a test can forget to plant" to
/// "a test can forget to use `_run`". So the scan now lives at the single
/// point where a process is started, and `no raw Process.runSync starts a
/// script` asserts that nothing bypasses it. That test is the reason this
/// one cannot quietly stop covering things: the bypass became detectable
/// rather than merely discouraged.
({int code, String out, String err}) _exec(
  String executable,
  List<String> arguments, {
  Map<String, String>? environment,
  String? workingDirectory,
  String? why,
}) {
  final env = environment == null
      ? null
      : {
          // Scratch space inside the scanned tree, for every runner — not
          // only `_run`'s. $RUNNER_TEMP is where the workflows put the
          // decoded keystore.
          'TMPDIR': _scratch,
          'RUNNER_TEMP': '$_scratch/runner',
          ...environment,
        };
  Directory('$_scratch/runner').createSync(recursive: true);
  _deriveSentinels(env ?? const {});
  final r = Process.runSync(
    executable,
    arguments,
    workingDirectory: workingDirectory,
    includeParentEnvironment: environment == null,
    environment: env ?? const {},
    stdoutEncoding: utf8,
    stderrEncoding: utf8,
  );
  final out = r.stdout.toString();
  final err = r.stderr.toString();
  // ALWAYS. The scan used to be conditional on `environment` being passed,
  // so `_exec(...)` with the argument omitted went THROUGH the chokepoint
  // and silently derived nothing and scanned nothing — a bypass no amount of
  // strengthening the source rule could have caught, because it was in the
  // chokepoint's own signature (#208). A call that handles no secret loses
  // nothing by being scanned; a call that handles one must not be able to
  // opt out by leaving an argument off.
  //
  // Re-derive first: the credentials file may have been written BY this run.
  _deriveSentinels(const {});
  _assertNoLeak(out, err, why ?? executable);
  return (code: r.exitCode, out: out, err: err);
}

({int code, String out, String err}) _run(
  String script, {
  Map<String, String> env = const {},
}) {
  final environment = {
    'PATH':
        '${_tmp.path}/bin:${Platform.environment['PATH'] ?? '/usr/bin:/bin'}',
    'HOME': _home,
    'GH_LOG': _ghLog,
    ...env,
  };
  // Derived from what this run is actually handed, before it runs. No test
  // has to remember to register anything (#200).
  return _exec(
    '/bin/bash',
    [script],
    workingDirectory: repoRoot.path,
    environment: environment,
    why: script,
  );
}

/// Sentinels are per-test; a value planted by one group must not make another
/// group's unrelated output look like a leak.
void _clearSentinels() {
  _sentinels.clear();
  _credentialSentinels.clear();
}

void _writeCredentials(String text) {
  File(_credentials)
    ..createSync(recursive: true)
    ..writeAsStringSync(text);
}

/// The argv of every recorded `gh` invocation.
List<String> _uploadedArgv() {
  final f = File(_ghLog);
  if (!f.existsSync()) return const [];
  return f
      .readAsLinesSync()
      .where((l) => l.startsWith('SET '))
      .map((l) => l.split('argv=').last)
      .toList();
}

List<int> _uploadedLengths() {
  final f = File(_ghLog);
  if (!f.existsSync()) return const [];
  return f
      .readAsLinesSync()
      .where((l) => l.startsWith('SET '))
      .map((l) => int.parse(l.split('bytes=')[1].split(' ').first))
      .toList();
}

/// The `read_credential` function, lifted from the script so a test can parse a
/// credentials file exactly as `set_ci_secrets.sh` does, without running the
/// upload path.
String _readCredentialFunction() {
  final text = readFile('tools/set_ci_secrets.sh');
  final start = text.indexOf('read_credential() {');
  final end = text.indexOf('\n}\n', start) + 3;
  return text.substring(start, end);
}

void main() {
  setUp(() {
    _tmp = Directory.systemTemp.createTempSync('hs-secrets-guard');
    Directory('$_home/HonestArcadeApps/secrets').createSync(recursive: true);
    // Records the name and byte length of what it is given. Never the value.
    _writeExecutable('${_tmp.path}/bin/gh', '''#!/bin/sh
if [ "\$1 \$2" = "secret list" ]; then exit 0; fi
n=\$(wc -c | tr -d ' ')
# argv as well as the byte count: recording only the length made the
# DESTINATION of an upload invisible, so REPO="attacker/Evil" and dropping
# -R both survived the mutation battery (#160).
echo "SET bytes=\$n argv=\$*" >> "\$GH_LOG"
''');
    File(_ghLog).writeAsStringSync('');
    // `cd "$(dirname "$0")/.."` runs before any check, so the narrowed PATH
    // used by the no-gcloud test still needs this one binary.
    for (final tool in const ['dirname']) {
      final found = Process.runSync('command', [
        '-v',
        tool,
      ], runInShell: true).stdout.toString().trim();
      if (found.isNotEmpty) {
        Link('${_tmp.path}/bin/$tool').createSync(found);
      }
    }
  });

  tearDown(() => _tmp.deleteSync(recursive: true));

  group('set_ci_secrets.sh', () {
    test('a missing credentials file is refused, with nothing uploaded', () {
      final r = _run('tools/set_ci_secrets.sh');
      expect(r.code, 2, reason: 'creds-missing: ${r.err}');
      expect(_uploadedLengths(), isEmpty);
    });

    test('a credentials file is never executed', () {
      final marker = '${_tmp.path}/PWNED';
      _writeCredentials(
        'export HS_KEYSTORE_PATH="/nonexistent"\n'
        'export HS_KEYSTORE_PASS="pw\$(touch $marker)end"\n'
        'export HS_KEY_ALIAS="upload"\n'
        'export HS_KEY_PASS="pw\$(touch $marker)end"\n',
      );
      final r = _run('tools/set_ci_secrets.sh');
      expect(
        File(marker).existsSync(),
        isFalse,
        reason: 'creds-exec: the credentials file ran a command substitution',
      );
      expect(r.code, isNot(0));
      expect(_uploadedLengths(), isEmpty);
    });

    test('HS_KEY_PASS differing from HS_KEYSTORE_PASS is refused', () {
      // PKCS12 has one password and keytool ignores a separate -keypass, so a
      // mismatch is catchable only here — it used to reach the release build
      // and fail there with no earlier warning (#143).
      _writeCredentials(
        'export HS_KEYSTORE_PATH="/nonexistent"\n'
        'export HS_KEYSTORE_PASS="MISMATCH-ONE-7k"\n'
        'export HS_KEY_ALIAS="upload"\n'
        'export HS_KEY_PASS="MISMATCH-TWO-9p"\n',
      );
      final r = _run('tools/set_ci_secrets.sh');
      expect(r.code, 2, reason: 'keypass-mismatch: ${r.err}');
      expect(r.err, contains('HS_KEY_PASS differs'));
      expect(_uploadedLengths(), isEmpty);
    });

    test('every secret is uploaded to this repository, named explicitly', () {
      // `gh` resolves the repository from `git remote` when -R is absent, so a
      // fork clone or a repointed origin would receive the real keystore. The
      // stub recorded only byte counts, so both `REPO="attacker/Evil"` and
      // dropping -R survived (#160).
      final keystore = '${_tmp.path}/fake.keystore';
      File(keystore).writeAsStringSync('not a real keystore');
      // Records argv. The stub logged nothing, so the argv channel could
      // not be searched even though #176's Fix line named it — and
      // set_ci_secrets.sh:130 asserts `-storepass:env` keeps the password
      // "off the command line and out of the process table" (#190).
      _writeExecutable(
        '${_tmp.path}/bin/keytool',
        '#!/bin/sh\n'
            'printf "%s\\n" "\$*" >> "${_tmp.path}/keytool.log"\n'
            'echo "Key and Certificate Management"\n'
            'exit 0\n',
      );
      _writeCredentials(
        'export HS_KEYSTORE_PATH="$keystore"\n'
        'export HS_KEYSTORE_PASS="PREFLIGHT-PASS-8fJ2"\n'
        'export HS_KEY_ALIAS="upload"\n'
        'export HS_KEY_PASS="PREFLIGHT-PASS-8fJ2"\n',
      );
      final r = _run(
        'tools/set_ci_secrets.sh',
        env: {'HS_KEYTOOL': '${_tmp.path}/bin/keytool'},
      );
      expect(r.code, 0, reason: 'destination: ${r.err}');

      final argv = _uploadedArgv();
      expect(argv, hasLength(4));
      for (final call in argv) {
        expect(
          call,
          contains('-R honestarcade/HonestSudoku'),
          reason: 'destination: an upload did not name this repository: $call',
        );
      }
    });

    test('an empty value is refused rather than uploaded', () {
      _writeCredentials(
        'export HS_KEYSTORE_PATH=""\n'
        'export HS_KEYSTORE_PASS="PREFLIGHT-PASS-8fJ2"\n'
        'export HS_KEY_ALIAS="upload"\n'
        'export HS_KEY_PASS="PREFLIGHT-PASS-8fJ2"\n',
      );
      final r = _run('tools/set_ci_secrets.sh');
      expect(r.code, 2);
      expect(_uploadedLengths(), isEmpty);
    });
  });

  group('the credentials parser', () {
    // Each case uploads four secrets; the third length is the alias, the
    // fourth is HS_KEY_PASS. Asserting LENGTHS keeps the value out of the
    // test output while still catching the corruption class (#126, #143):
    // a quote or a comment absorbed into the secret changes its length.
    const password = 'p@ss w0rd'; // 9 bytes
    const alias = 'upload'; // 6 bytes

    void expectParsed(String body, String why) {
      final keystore = '${_tmp.path}/fake.keystore';
      File(keystore).writeAsStringSync('not a real keystore');
      _writeCredentials(body.replaceAll('<KS>', keystore));
      // A keytool stub that accepts, so the parse is tested on its own.
      //
      // Pointing HS_KEYTOOL at a nonexistent path is not enough: the script
      // then falls back to `command -v keytool`, which finds nothing usable
      // on this machine but finds a real one on a CI runner with setup-java —
      // so these passed locally and failed in CI against a fake keystore.
      // Controlling the pre-flight is the only way to test the parser alone.
      _writeExecutable(
        '${_tmp.path}/bin/keytool',
        '#!/bin/sh\necho "Key and Certificate Management"\nexit 0\n',
      );
      final r = _run(
        'tools/set_ci_secrets.sh',
        env: {'HS_KEYTOOL': '${_tmp.path}/bin/keytool'},
      );
      expect(r.code, 0, reason: '$why: ${r.err}');
      final lengths = _uploadedLengths();
      expect(lengths, hasLength(4), reason: why);
      expect(lengths[2], alias.length, reason: '$why: alias length');
      expect(lengths[3], password.length, reason: '$why: HS_KEY_PASS length');
    }

    test('plain double quotes', () {
      expectParsed(
        'export HS_KEYSTORE_PATH="<KS>"\n'
            'export HS_KEYSTORE_PASS="$password"\n'
            'export HS_KEY_ALIAS="$alias"\n'
            'export HS_KEY_PASS="$password"\n',
        'plain',
      );
    });

    test('a trailing comment after the closing quote', () {
      expectParsed(
        'export HS_KEYSTORE_PATH="<KS>" # where it lives\n'
            'export HS_KEYSTORE_PASS="$password" # store\n'
            'export HS_KEY_ALIAS="$alias" # alias\n'
            'export HS_KEY_PASS="$password" # the key one\n',
        'trailing comment',
      );
    });

    test('trailing whitespace and CRLF', () {
      expectParsed(
        'export HS_KEYSTORE_PATH="<KS>"   \r\n'
            'export HS_KEYSTORE_PASS="$password"\t\r\n'
            'export HS_KEY_ALIAS="$alias"  \r\n'
            'export HS_KEY_PASS="$password"   \r\n',
        'whitespace and CRLF',
      );
    });

    test('single quotes and no quotes', () {
      expectParsed(
        'export HS_KEYSTORE_PATH=<KS>\n'
            "export HS_KEYSTORE_PASS='$password'\n"
            'export HS_KEY_ALIAS=$alias\n'
            "export HS_KEY_PASS='$password'\n",
        'mixed quoting',
      );
    });
  });

  group('the keystore pre-flight', () {
    test('a keytool that refuses stops the upload', () {
      final keystore = '${_tmp.path}/fake.keystore';
      File(keystore).writeAsStringSync('not a real keystore');
      _writeCredentials(
        'export HS_KEYSTORE_PATH="$keystore"\n'
        'export HS_KEYSTORE_PASS="PREFLIGHT-PASS-8fJ2"\n'
        'export HS_KEY_ALIAS="upload"\n'
        'export HS_KEY_PASS="PREFLIGHT-PASS-8fJ2"\n',
      );
      // Answers `-help` so the probe accepts it as a real keytool, and
      // refuses everything else — a wrong password or alias, in effect.
      _writeExecutable(
        '${_tmp.path}/bin/keytool',
        '#!/bin/sh\n'
            'if [ "\$1" = "-help" ]; then echo "Key and Certificate Management"; exit 0; fi\n'
            'exit 1\n',
      );
      final r = _run(
        'tools/set_ci_secrets.sh',
        env: {'HS_KEYTOOL': '${_tmp.path}/bin/keytool'},
      );
      expect(r.code, 2, reason: 'preflight: ${r.err}');
      expect(r.err, contains('do not open the keystore'));
      expect(_uploadedLengths(), isEmpty);
    });

    test('the macOS keytool stub is detected and skipped, loudly', () {
      // /usr/bin/keytool on macOS exists, is executable and cannot run.
      // Believing it would refuse every correct credentials file.
      final keystore = '${_tmp.path}/fake.keystore';
      File(keystore).writeAsStringSync('not a real keystore');
      _writeCredentials(
        'export HS_KEYSTORE_PATH="$keystore"\n'
        'export HS_KEYSTORE_PASS="PREFLIGHT-PASS-8fJ2"\n'
        'export HS_KEY_ALIAS="upload"\n'
        'export HS_KEY_PASS="PREFLIGHT-PASS-8fJ2"\n',
      );
      _writeExecutable(
        '${_tmp.path}/bin/keytool',
        '#!/bin/sh\necho "Unable to locate a Java Runtime" >&2\nexit 1\n',
      );
      final r = _run(
        'tools/set_ci_secrets.sh',
        env: {'HS_KEYTOOL': '${_tmp.path}/bin/keytool'},
      );
      expect(r.code, 0, reason: 'stub-keytool: ${r.err}');
      expect(r.err, contains('pre-flight is SKIPPED'));
      expect(_uploadedLengths(), hasLength(4));
    });
  });

  group('no script ever prints a secret value', () {
    // Both #19 criteria say so ("prints only the secret names it set", "never
    // prints the key") and nothing asserted it: adding `echo "$KEY_PASS"` to
    // one script and `cat "$KEY_PATH"` — the whole service-account private key
    // — to the other passed all 290 tests (#155).
    //
    // The values below are distinctive so a partial or transformed leak is
    // still caught, and every run's stdout AND stderr is searched, including
    // the failure paths, which is where a debugging echo survives longest.
    const password = 'PW-S3CRET-abcdefghijklmnop';
    const alias = 'AL-S3CRET-qrstuvwx';
    const keyBody = 'PK-S3CRET-yz0123456789';

    // The private key is minted by a stub INTO A FILE, so it never appears in
    // the environment `_run` derives from — and deriving instead of
    // registering silently dropped it. Declared here for the same reason
    // make_upload_key declares its password: what a stub plants, the stub's
    // test declares (#200).
    setUp(() => _deriveSentinels(const {'STUB_PRIVATE_KEY': keyBody}));

    // Registered, not searched here: `_run` scans every channel on every
    // invocation, so a path this group never thought to list is covered
    // anyway. That is the difference between #155's three chosen cases and
    // what #176 asked for (#190).
    // No registration step. `_run` derives the sentinels from the
    // environment it passes, and these three values reach the scripts
    // through the credentials file and through env (#200).
    tearDown(_clearSentinels);

    void expectNoLeak(({int code, String out, String err}) r, String why) {
      // `_run` already asserted. Kept as a named call so the tests below
      // still read as leak tests rather than as exit-code tests.
      _assertNoLeak(r.out, r.err, why);
    }

    test('set_ci_secrets.sh prints names, never values', () {
      final keystore = '${_tmp.path}/fake.keystore';
      File(keystore).writeAsStringSync('not a real keystore');
      _writeExecutable(
        '${_tmp.path}/bin/keytool',
        '#!/bin/sh\necho "Key and Certificate Management"\nexit 0\n',
      );

      // The happy path, and every refusal that can be reached with a file.
      final cases = <String, String>{
        'the happy path':
            'export HS_KEYSTORE_PATH="$keystore"\n'
            'export HS_KEYSTORE_PASS="$password"\n'
            'export HS_KEY_ALIAS="$alias"\n'
            'export HS_KEY_PASS="$password"\n',
        'a mismatched key password':
            'export HS_KEYSTORE_PATH="$keystore"\n'
            'export HS_KEYSTORE_PASS="$password"\n'
            'export HS_KEY_ALIAS="$alias"\n'
            'export HS_KEY_PASS="${password}x"\n',
        'an unreadable keystore':
            'export HS_KEYSTORE_PATH="/nonexistent"\n'
            'export HS_KEYSTORE_PASS="$password"\n'
            'export HS_KEY_ALIAS="$alias"\n'
            'export HS_KEY_PASS="$password"\n',
      };
      cases.forEach((why, credentials) {
        _writeCredentials(credentials);
        final r = _run(
          'tools/set_ci_secrets.sh',
          env: {'HS_KEYTOOL': '${_tmp.path}/bin/keytool'},
        );
        expectNoLeak(r, why);
      });

      // And the complement: the harness must be able to see a leak, or it is
      // asserting nothing.
      // chokepoint-exempt: this call exists TO leak, so the scan would fail
      // it by design. It is the guard on the guard.
      final leaky = Process.runSync(
        '/bin/bash',
        ['-c', 'echo "pass: \$HS_LEAK"'],
        environment: {'HS_LEAK': password},
        stdoutEncoding: utf8,
      );
      expect(
        leaky.stdout.toString(),
        contains(password),
        reason: 'leak-harness: the search cannot see a value it should',
      );
    });

    test('setup_play_ci.sh never prints the key it uploads', () {
      _writeExecutable('${_tmp.path}/bin/gcloud', '''#!/bin/sh
case "\$1 \$2" in "auth list") echo "owner@example.com"; exit 0 ;; esac
case "\$1 \$2 \$3 \$4" in
  "iam service-accounts keys create")
     printf '{"private_key_id":"KEYID","private_key":"$keyBody"}' > "\$5"; exit 0 ;;
esac
exit 0
''');
      final r = _run(
        'tools/setup_play_ci.sh',
        env: {'HS_PLAY_ACCOUNT': 'owner@example.com'},
      );
      expectNoLeak(r, 'setup_play_ci.sh');
      expect(
        r.out,
        contains('key id: KEYID'),
        reason: 'leak: the key ID is public and should still be reported',
      );
    });
  });

  group('setup_play_ci.sh', () {
    void stubGcloud(String account) {
      _writeExecutable('${_tmp.path}/bin/gcloud', '''#!/bin/sh
case "\$1 \$2" in "auth list") echo "$account"; exit 0 ;; esac
exit 0
''');
    }

    test('no gcloud on PATH is refused', () {
      // Only the stub directory: this machine may have a real gcloud, and
      // ubuntu-latest ships the Google Cloud SDK in /usr/bin, so any wider
      // PATH tests the login check instead of this one. The script's first
      // action is `command -v gcloud`, which needs nothing else.
      final r = _run(
        'tools/setup_play_ci.sh',
        env: {'PATH': '${_tmp.path}/bin'},
      );
      expect(r.code, 3, reason: 'no-gcloud: ${r.err}');
      expect(r.err, contains('gcloud'));
    });

    test('no active login is refused', () {
      _writeExecutable('${_tmp.path}/bin/gcloud', '#!/bin/sh\nexit 0\n');
      final r = _run('tools/setup_play_ci.sh');
      expect(r.code, 4, reason: 'no-login: ${r.err}');
    });

    test('the wrong confirmed account is refused', () {
      stubGcloud('someone@example.com');
      final r = _run(
        'tools/setup_play_ci.sh',
        env: {'HS_PLAY_ACCOUNT': 'owner@example.com'},
      );
      expect(r.code, 4, reason: 'wrong-account: ${r.err}');
      expect(r.err, contains('someone@example.com'));
    });

    test('no terminal and no confirmation is refused', () {
      stubGcloud('owner@example.com');
      final r = _run('tools/setup_play_ci.sh');
      expect(r.code, 4, reason: 'no-tty: ${r.err}');
    });
  });

  group('make_upload_key.sh quoting', () {
    // #108 wrapped the credential values in double quotes, which stops a space
    // and a semicolon and does not stop command substitution. The file is
    // written by a heredoc, so `$(...)` expanded when it was written AND again
    // when it was sourced: the recorded password was the expanded form, and it
    // did not open the keystore that had just been made with the literal one
    // (#119).
    //
    // The fixture that missed it asserted the line *contains* `export NAME="`
    // — which is exactly the shape that was wrong. This one writes, sources,
    // parses and then opens the keystore.

    /// A real keytool, resolved the way the scripts do: the pinned path first,
    /// then PATH (which is where a CI runner's setup-java puts it).
    String resolveKeytool() {
      const pinned = '/opt/homebrew/opt/openjdk@21/bin/keytool';
      if (File(pinned).existsSync()) return pinned;
      final found = Process.runSync('command', [
        '-v',
        'keytool',
      ], runInShell: true).stdout.toString().trim();
      expect(
        found,
        isNotEmpty,
        reason: 'no keytool available; this test needs a real one',
      );
      return found;
    }

    test('a fixture too short for the transformed forms is refused', () {
      // #230 item 3. `_leakForms` searches base64, reversed, hex and the rest
      // only from eight characters, and `_addSentinel` accepted four — so a
      // fixture of five to seven characters was searched verbatim only, the
      // exact hole #220 demonstrated, with nothing saying so. The floor is
      // asserted at its boundary: seven refused, eight accepted.
      expect(
        () => _addSentinel('seven77', 'a probe'),
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
      _addSentinel('eight888', 'a probe');
      expect(
        _sentinels,
        contains('eight888'),
        reason: 'fixture-floor: an eight-character fixture was refused',
      );
      _sentinels.remove('eight888');
    });

    test('the overwrite refusal sees the committed certificate from any '
        'directory', () {
      // #230 item 8. Two comments in the script said it cd's to the
      // repository root; it did not, so `CERT_OUT`'s default resolved
      // against the caller's directory and the refusal protecting the
      // committed `android/signing/upload_certificate.pem` checked a path
      // that does not exist when the script is run from anywhere else. Run
      // it from a scratch directory with the default output: it must refuse,
      // and name the file.
      final elsewhere = Directory('$_home/elsewhere')
        ..createSync(recursive: true);
      addTearDown(() => elsewhere.deleteSync(recursive: true));
      final r = _exec(
        '/bin/bash',
        ['${repoRoot.path}/tools/make_upload_key.sh'],
        workingDirectory: elsewhere.path,
        environment: {
          'PATH': Platform.environment['PATH'] ?? '/usr/bin:/bin',
          'HOME': elsewhere.path,
          'HS_KEYSTORE_PASS': 'irrelevant-but-long-enough',
          'HS_KEYTOOL': '/nonexistent/keytool',
        },
        why: 'make_upload_key.sh overwrite refusal from another directory',
      );
      expect(
        r.code,
        2,
        reason:
            'cert-cwd: run from outside the repository, the script did not '
            'refuse over the committed certificate. Exit ${r.code}; stderr: '
            '${r.err}',
      );
      expect(
        r.err,
        contains('upload_certificate.pem already exists'),
        reason: 'cert-cwd: the refusal does not name the committed certificate',
      );
    });

    test('a password too short for the leak scan is refused', () {
      // The leak scan searches TRANSFORMED forms — base64, reversed, the
      // slices — only for values of eight characters or more, because a
      // lowercased four-letter password matches English prose. That threshold
      // is a guarantee only if short passwords cannot exist, and nothing
      // asserted the script enforcing it: deleting the whole length check
      // left the suite at its baseline count (#230).
      //
      // Executed, not read. The boundary is the assertion.
      final home = Directory('$_home/shortpw')..createSync(recursive: true);
      addTearDown(() => home.deleteSync(recursive: true));

      ({int code, String err}) attempt(String password) {
        final r = _exec(
          '/bin/bash',
          ['tools/make_upload_key.sh'],
          workingDirectory: repoRoot.path,
          environment: {
            'PATH': Platform.environment['PATH'] ?? '/usr/bin:/bin',
            'HOME': home.path,
            'HS_KEYSTORE_PASS': password,
            // A keytool that cannot run: this test is about the refusal that
            // happens before any key is made, and a real one would mint a
            // throwaway keystore for nothing.
            'HS_KEYTOOL': '/nonexistent/keytool',
            'HS_UPLOAD_CERT_OUT': '${home.path}/cert.pem',
          },
          why: 'make_upload_key.sh length check',
        );
        return (code: r.code, err: r.err);
      }

      final short = attempt('elevenchars');
      expect(
        short.code,
        // 2, not `isNot(0)`: the fixture hands the script a keytool that
        // does not exist, so a script with NO length check still exits
        // non-zero — this assertion passed either way and only the message
        // check below was load-bearing (#241).
        2,
        reason:
            'password-length: an 11-character password was not refused with '
            'the exit code the refusal uses. The leak scan can only search a '
            'short password verbatim, so a base64 copy of it in a job '
            'summary would not be found',
      );
      expect(
        short.err,
        contains('12'),
        reason: 'password-length: the refusal does not say what the minimum is',
      );

      // The positive control: one character longer must get PAST the length
      // check. It still fails — the keytool path is deliberately bogus — but
      // it must fail for that reason and not for its length.
      final long = attempt('twelvechars1');
      expect(
        long.err,
        isNot(contains('is 12 characters')),
        reason:
            'password-length: a 12-character password was refused for its '
            'length, so the boundary is off by one and the check would '
            'reject something it should allow',
      );
    });

    test('a password full of shell metacharacters survives the round trip', () {
      final keytool = resolveKeytool();
      final marker = '${_tmp.path}/PWNED';
      // Command substitution, a backtick, a double quote, a backslash, a
      // single quote and a space — every character that has bitten this file.
      final password =
          'p4ss\$(touch $marker)w`touch ${marker}2`d "q" \\b \'s\' end';
      // make_upload_key.sh was outside the leak group entirely — the last row
      // of #176's table — and it is the only script that holds the plaintext
      // password as an environment variable (#190).
      addTearDown(_clearSentinels);

      final made = _exec(
        '/bin/bash',
        ['tools/make_upload_key.sh'],
        workingDirectory: repoRoot.path,
        environment: {
          'PATH': Platform.environment['PATH'] ?? '/usr/bin:/bin',
          'HOME': _home,
          'HS_KEYSTORE_PASS': password,
          'HS_KEYTOOL': keytool,
          // Or the throwaway key's certificate is written over the
          // committed one: CERT_OUT defaults to a path relative to the
          // repository root, which the script cd's to, and a fake $HOME does
          // not move it (#123).
          'HS_UPLOAD_CERT_OUT': '$_home/cert.pem',
        },
        why: 'make_upload_key.sh',
      );
      expect(made.code, 0, reason: 'make: ${made.err}');
      // No hand-rolled scan any more: `_exec` derives from the environment
      // it passed and scans afterwards, for this call exactly as for every
      // other. That is the point of the chokepoint (#208).

      // 2. Nothing runs if someone sources it anyway, and the value comes back
      //    whole.
      // chokepoint-exempt: deliberately sources the credentials file to
      // prove nothing in it executes; the value it prints is the assertion.
      final sourced = Process.runSync('/bin/bash', [
        '-c',
        'set -a; . "\$1"; set +a; printf %s "\$HS_KEYSTORE_PASS"',
        'bash',
        _credentials,
      ], stdoutEncoding: utf8);
      expect(
        File(marker).existsSync() || File('${marker}2').existsSync(),
        isFalse,
        reason: 'source: the password executed on a dot-source',
      );
      expect(
        sourced.stdout,
        password,
        reason: 'source: the value came back changed',
      );

      // 3. The supported path — parsing — gives the same value.
      // chokepoint-exempt: reads the credentials file with the script's own
      // awk parser to prove the value round-trips; it is the parser under
      // test, not a script handling a secret.
      final parsed = Process.runSync('/bin/bash', [
        '-c',
        'CREDENTIALS="\$1"\n'
            '${_readCredentialFunction()}\n'
            'read_credential HS_KEYSTORE_PASS',
        'bash',
        _credentials,
      ], stdoutEncoding: utf8);
      expect(
        parsed.stdout.toString().trimRight(),
        password,
        reason: 'parse: the value came back changed',
      );

      // 4. And the value actually opens the keystore that was just made — the
      //    check that would have caught #119 on its own.
      final opens = _exec(
        keytool,
        [
          '-list',
          '-keystore',
          '$_home/HonestArcadeApps/secrets/sudoku-upload.keystore',
          '-storetype',
          'PKCS12',
          '-storepass:env',
          'HSP',
          '-alias',
          'upload',
        ],
        environment: {'HSP': password},
        why: 'keytool -list on the produced keystore',
      );
      expect(
        opens.code,
        0,
        reason: 'keystore: the recorded password does not open the key',
      );
    });

    test('it refuses to overwrite either file', () {
      // #93: refusing on the keystore alone meant a run with the keystore
      // moved aside silently replaced the password of a key that still exists.
      final keytool = resolveKeytool();
      Directory('$_home/HonestArcadeApps/secrets').createSync(recursive: true);
      for (final existing in [
        '$_home/HonestArcadeApps/secrets/sudoku-upload.keystore',
        _credentials,
      ]) {
        File(existing).writeAsStringSync('in the way');
        final r = _exec(
          '/bin/bash',
          ['tools/make_upload_key.sh'],
          workingDirectory: repoRoot.path,
          environment: {
            'PATH': Platform.environment['PATH'] ?? '/usr/bin:/bin',
            'HOME': _home,
            'HS_KEYSTORE_PASS': 'irrelevant-but-long-enough',
            'HS_KEYTOOL': keytool,
            'HS_UPLOAD_CERT_OUT': '$_home/cert.pem',
          },
          why: 'make_upload_key.sh overwrite refusal',
        );
        expect(r.code, 2, reason: 'overwrite: ${r.err}');
        expect(r.err, contains('refusing to overwrite'));
        File(existing).deleteSync();
      }
    });
  });

  group('setup_play_ci.sh past the confirmation gate', () {
    // The four refusal tests all stopped at the account gate, so nothing ever
    // exercised a line below it — which is where the #134 trap, the key
    // deletion and the IAM behaviour live. All three survived the mutation
    // battery (#160).
    late String gcloudLog;

    void stubGcloud({
      bool keysCreateFails = false,
      bool serviceAccountExists = true,
    }) {
      gcloudLog = '${_tmp.path}/gcloud.log';
      File(gcloudLog).writeAsStringSync('');
      _writeExecutable('${_tmp.path}/bin/gcloud', '''#!/bin/sh
echo "\$*" >> "$gcloudLog"
case "\$1 \$2" in
  "auth list") echo "owner@example.com"; exit 0 ;;
  "projects describe") exit 0 ;;
  "services list") echo "androidpublisher.googleapis.com"; exit 0 ;;
esac
case "\$1 \$2 \$3" in
  "iam service-accounts describe") ${serviceAccountExists ? 'exit 0' : 'exit 1'} ;;
  "iam service-accounts keys")
     if [ "\$4" = "list" ]; then exit 0; fi
     if [ "\$4" = "create" ]; then
       ${keysCreateFails ? 'exit 1' : r"""printf '{"private_key_id":"KEYID99","private_key":"PRIVATE"}' > "$5"; exit 0"""}
     fi ;;
esac
exit 0
''');
    }

    String keyPath() => '$_home/HonestArcadeApps/secrets/honestsudoku-ci.json';

    test('the happy path uploads to this repository and leaves no key', () {
      stubGcloud();
      final r = _run(
        'tools/setup_play_ci.sh',
        env: {'HS_PLAY_ACCOUNT': 'owner@example.com'},
      );
      expect(r.code, 0, reason: 'setup-happy: ${r.err}');
      expect(
        File(keyPath()).existsSync(),
        isFalse,
        reason: 'setup-happy: the service-account key is still on disk',
      );
      expect(_uploadedArgv(), hasLength(1));
      expect(
        _uploadedArgv().single,
        allOf(
          contains('PLAY_SERVICE_ACCOUNT_JSON'),
          contains('-R honestarcade/HonestSudoku'),
        ),
        reason: 'setup-happy: the key must go to this repository, named',
      );
      expect(r.out, contains('key id: KEYID99'));
    });

    test('a failed upload still leaves no key on disk', () {
      // Without the trap the key survived, and because idempotence keys off
      // `gh secret list`, the next run minted a second one (#134).
      stubGcloud();
      _writeExecutable('${_tmp.path}/bin/gh', '''#!/bin/sh
if [ "\$1 \$2" = "secret list" ]; then exit 0; fi
echo "boom" >&2
exit 1
''');
      final r = _run(
        'tools/setup_play_ci.sh',
        env: {'HS_PLAY_ACCOUNT': 'owner@example.com'},
      );
      expect(r.code, isNot(0), reason: 'setup-fail: should have failed');
      expect(
        File(keyPath()).existsSync(),
        isFalse,
        reason: 'setup-fail: the trap did not delete the key',
      );
    });

    test('no IAM role is ever granted to the service account', () {
      // Play access is granted in the Console, not in Cloud IAM. A role here
      // would be authority nobody needs, and `--role roles/owner` passed the
      // whole suite (#160).
      // The stub must report the account as ABSENT. With `describe`
      // exiting 0 the script skips the whole create block — the one
      // `--role roles/owner` is inserted into — so the assertions below
      // passed over a command that never ran, and both sanity checks were
      // satisfied by `describe` and `keys create` (#176).
      stubGcloud(serviceAccountExists: false);
      _run(
        'tools/setup_play_ci.sh',
        env: {'HS_PLAY_ACCOUNT': 'owner@example.com'},
      );
      final calls = File(gcloudLog).readAsStringSync();
      expect(
        calls,
        contains('iam service-accounts create'),
        reason:
            'sanity: the service account was never created, so no --role '
            'could appear whatever the script says',
      );
      expect(
        calls,
        isNot(contains('add-iam-policy-binding')),
        reason: 'iam: a policy binding was created',
      );
      expect(
        calls,
        isNot(contains('--role')),
        reason: 'iam: a role was granted',
      );
      // Sanity: the log must show the script actually ran past the gate,
      // or the two assertions above pass on an empty file.
      expect(
        calls,
        contains('iam service-accounts'),
        reason: 'sanity: the stub recorded no service-account calls at all',
      );
      expect(
        calls,
        contains('keys create'),
        reason: 'sanity: the run never reached the key-minting step',
      );
    });
  });

  group('the Play access step, as the workflow actually writes it', () {
    // Extracted from the YAML and executed, rather than retyped into a Dart
    // string. The retyped version asserted against a copy: deleting `|| true`
    // from the real file — the literal #127 regression — left every test green
    // (#160).
    late String stepScript;

    setUp(() {
      final workflow = Workflow.parse(
        '.github/workflows/play-api-check.yml',
        readFile('.github/workflows/play-api-check.yml'),
      );
      expect(workflow.problem, isNull);
      final play = workflow.jobs.single.stepById('play');
      expect(play, isNotNull, reason: 'the `play` step has gone');
      stepScript = play!.run!;

      // gcloud: activate and mint a token, printing nothing sensitive.
      //
      // It RECORDS ITS ARGV, and that is the whole point. The `gcloud.log`
      // channel existed but was never populated for the one step that holds
      // the service-account key, so putting the entire key on gcloud's
      // command line — where it is the process table, readable by any later
      // step or `ps` — passed all 47 tests (#208). A stub that does not log
      // argv makes the argv channel decorative.
      File('${_tmp.path}/gcloud.log').writeAsStringSync('');
      _writeExecutable('${_tmp.path}/bin/gcloud', '''#!/bin/sh
echo "gcloud \$*" >> "${_tmp.path}/gcloud.log"
case "\$1 \$2" in
  "auth activate-service-account") exit 0 ;;
  "auth print-access-token") echo "ya29.FAKE-TOKEN"; exit 0 ;;
esac
exit 0
''');
      // curl: answers from files the test plants, so each HTTP status and body
      // is the scenario's choice.
      File('${_tmp.path}/curl.log').writeAsStringSync('');
      _writeExecutable(
        '${_tmp.path}/bin/curl',
        '''#!/bin/sh
echo "curl \$*" >> "${_tmp.path}/curl.log"
'''
            r'''out=""; kind="edits"
while [ $# -gt 0 ]; do
  case "$1" in
    -o) out="$2"; shift ;;
    -X) [ "$2" = "DELETE" ] && kind="delete"; shift ;;
    *tracks) kind="tracks" ;;
  esac
  shift
done
case "$kind" in
  edits)  [ -n "$out" ] && cat "$HS_EDIT_BODY" > "$out"; printf '%s' "$HS_EDIT_STATUS" ;;
  tracks) [ -n "$out" ] && cat "$HS_TRACKS_BODY" > "$out"; printf '%s' "$HS_TRACKS_STATUS" ;;
  delete) : ;;
esac
exit 0
''',
      );
    });

    ({int code, String out, String err, String summary}) runStep({
      required String tracksBody,
      String tracksStatus = '200',
      String editBody = '{"id":"E1"}',
      String editStatus = '200',
      String serviceAccount = '{"fake":"key"}',
    }) {
      final script = '${_tmp.path}/play_step.sh';
      File(script).writeAsStringSync(stepScript);
      final runnerTemp = '${_tmp.path}/runner';
      Directory(runnerTemp).createSync(recursive: true);
      final summary = '${_tmp.path}/summary.md';
      File(summary).writeAsStringSync('');
      File('${_tmp.path}/tracks.json').writeAsStringSync(tracksBody);
      File('${_tmp.path}/edit.json').writeAsStringSync(editBody);

      final r = _exec(
        '/bin/bash',
        [script],
        workingDirectory: repoRoot.path,
        environment: {
          'PATH': '${_tmp.path}/bin:/usr/bin:/bin',
          'RUNNER_TEMP': runnerTemp,
          'GITHUB_STEP_SUMMARY': summary,
          'PLAY_SERVICE_ACCOUNT_JSON': serviceAccount,
          'PACKAGE': 'com.honestarcade.sudoku',
          'HS_TRACKS_BODY': '${_tmp.path}/tracks.json',
          'HS_TRACKS_STATUS': tracksStatus,
          'HS_EDIT_BODY': '${_tmp.path}/edit.json',
          'HS_EDIT_STATUS': editStatus,
        },
      );
      return (
        code: r.code,
        out: r.out,
        err: r.err,
        summary: File(summary).readAsStringSync(),
      );
    }

    test('an app with no tracks passes — the state at first dispatch', () {
      final r = runStep(
        tracksBody: '{"kind":"androidpublisher#tracksListResponse"}',
      );
      expect(r.code, 0, reason: 'empty-tracks: ${r.err}');
      expect(r.summary, contains('none yet'));
    });

    test('a populated track list is reported', () {
      final r = runStep(
        tracksBody: '{"tracks":[{"track":"internal"},{"track":"alpha"}]}',
      );
      expect(r.code, 0, reason: 'tracks: ${r.err}');
      expect(r.summary, contains('alpha internal'));
    });

    test('a 403 on the tracks call is distinguished from an empty app', () {
      final r = runStep(
        tracksBody: '{"error":{"code":403,"message":"no permission"}}',
        tracksStatus: '403',
      );
      expect(r.code, isNot(0), reason: 'tracks-403 must fail');
      expect(r.err, contains('403'));
      expect(
        r.err,
        contains('not the same as an app with no tracks yet'),
        reason: 'tracks-403: the message must separate the two cases',
      );
    });

    test('a 403 on the edit call names the likely cause', () {
      final r = runStep(
        tracksBody: '{}',
        editBody: '{"error":{"code":403}}',
        editStatus: '403',
      );
      expect(r.code, isNot(0));
      expect(r.err, contains('has not been invited'));
    });

    test('a missing service-account secret refuses before any call', () {
      final r = runStep(tracksBody: '{}', serviceAccount: '');
      expect(r.code, isNot(0));
      expect(r.err, contains('PLAY_SERVICE_ACCOUNT_JSON is not set'));
    });

    test('the argv channels are actually recorded', () {
      // The complement of the stubs' argv logging, which the fix that added
      // it called "the whole point".
      //
      // Deleting `echo "gcloud $*" >> gcloud.log` from the stub left the file
      // 47/47 green: nothing asserted either log was ever written, so the
      // channel that catches a service-account key on a command line could be
      // switched off in silence (#220). A channel nobody checks is a channel
      // that does not exist.
      runStep(tracksBody: '{"tracks":[]}');
      for (final log in const ['gcloud.log', 'curl.log']) {
        final file = File('${_tmp.path}/$log');
        expect(
          file.existsSync(),
          isTrue,
          reason:
              'argv: $log was never created, so the recorded-argv channel is '
              'empty for every test that relies on it',
        );
        expect(
          file.readAsStringSync().trim(),
          isNotEmpty,
          reason:
              'argv: $log is empty after a run that invokes it. The stub '
              'stopped recording, and a secret on that command line would '
              'now be invisible',
        );
      }
    });

    test('the token is masked and never printed', () {
      final r = runStep(tracksBody: '{}');
      expect(r.out, contains('::add-mask::'));
      final masked = RegExp(r'::add-mask::(\S+)').firstMatch(r.out)!.group(1)!;
      expect(
        r.summary,
        isNot(contains(masked)),
        reason: 'the access token must not reach the summary',
      );
    });
  });

  group('the keystore step of play-api-check, as the workflow writes it', () {
    // #160 taught the suite to extract a `run:` body and execute it, and was
    // applied to exactly one step. This is the other one — the step with the
    // most acceptance-criterion text attached, and the one that handles the
    // keystore password. Six mutations of it were green, including
    // `if false` in place of the alias assertion and a line putting
    // $HS_KEYSTORE_PASS into the job summary (#173).
    late String stepScript;

    setUp(() {
      final workflow = Workflow.parse(
        '.github/workflows/play-api-check.yml',
        readFile('.github/workflows/play-api-check.yml'),
      );
      expect(workflow.problem, isNull);
      final keystore = workflow.jobs.single.stepById('keystore');
      expect(keystore, isNotNull, reason: 'the `keystore` step has gone');
      stepScript = keystore!.run!;

      // Records every invocation so a test can assert what the step ASKED
      // for, not only what it did with the answer: dropping `-alias` from
      // `keytool -list` changes the question, and the answer looks the same.
      _writeExecutable('${_tmp.path}/bin/keytool', r"""#!/bin/sh
printf '%s\n' "$*" >> "$HS_KEYTOOL_CALLS"
case "$1" in
  -list)
    # Faithful to keytool: with -alias it exits 1 when the keystore holds
    # no such entry, and otherwise echoes back the REQUESTED spelling
    # rather than the stored one. That is why the step needs no explicit
    # alias comparison — and why one was dead code (#180).
    want=""
    prev=""
    for a in "$@"; do
      if [ "$prev" = "-alias" ]; then want="$a"; fi
      prev="$a"
    done
    lc_want=$(printf '%s' "$want" | tr '[:upper:]' '[:lower:]')
    lc_have=$(printf '%s' "$HS_STUB_ALIAS" | tr '[:upper:]' '[:lower:]')
    if [ -n "$want" ] && [ "$lc_want" != "$lc_have" ]; then
      printf 'keytool error: java.lang.Exception: Alias <%s> does not exist\n' "$want" >&2
      exit 1
    fi
    printf 'Alias name: %s\n' "$want"
    printf 'SHA256: %s\n' "$HS_STUB_KS_FP"
    ;;
  -printcert)
    printf 'SHA256: %s\n' "$HS_STUB_PEM_FP"
    ;;
  -certreq) printf 'CERTREQ\n' ;;
esac
exit 0
""");
    });

    ({int code, String out, String err, String summary, String calls}) runStep({
      String b64 = 'a2V5c3RvcmU=',
      String pass = 'correct horse',
      String alias = 'upload',
      String? keyPass,
      String stubAlias = 'upload',
      String ksFp = 'AA:BB',
      String pemFp = 'AA:BB',
    }) {
      final script = '${_tmp.path}/keystore_step.sh';
      File(script).writeAsStringSync(stepScript);
      final runnerTemp = '${_tmp.path}/runner';
      Directory(runnerTemp).createSync(recursive: true);
      final summary = '${_tmp.path}/ks_summary.md';
      File(summary).writeAsStringSync('');
      final calls = '${_tmp.path}/keytool_calls.txt';
      File(calls).writeAsStringSync('');

      final r = _exec(
        '/bin/bash',
        [script],
        workingDirectory: repoRoot.path,
        environment: {
          'PATH': '${_tmp.path}/bin:/usr/bin:/bin',
          'RUNNER_TEMP': runnerTemp,
          'GITHUB_STEP_SUMMARY': summary,
          'HS_KEYSTORE_B64': b64,
          'HS_KEYSTORE_PASS': pass,
          'HS_KEY_ALIAS': alias,
          'HS_KEY_PASS': keyPass ?? pass,
          'HS_KEYTOOL_CALLS': calls,
          'HS_STUB_ALIAS': stubAlias,
          'HS_STUB_KS_FP': ksFp,
          'HS_STUB_PEM_FP': pemFp,
        },
      );
      return (
        code: r.code,
        out: r.out,
        err: r.err,
        summary: File(summary).readAsStringSync(),
        calls: File(calls).readAsStringSync(),
      );
    }

    test('a matching keystore, alias and fingerprint pass', () {
      final r = runStep();
      expect(r.code, 0, reason: 'keystore-happy: ${r.err}');
      expect(r.out, contains('matches the committed certificate'));
    });

    test('an alias that is not the configured one is refused', () {
      // keytool itself refuses: `-alias` makes it exit 1 for an absent
      // entry, and `set -euo pipefail` ends the step there. What this
      // asserts is that the step lets that failure through — the explicit
      // comparison that used to follow could never fire, because with
      // `-alias` keytool echoes back the requested spelling (#173, #180).
      final r = runStep(alias: 'upload', stubAlias: 'someone-else');
      expect(r.code, isNot(0), reason: 'wrong alias must fail');
      expect(r.err, contains('does not exist'));
    });

    test('the alias comparison ignores case, as keytool lowercases', () {
      final r = runStep(alias: 'Upload', stubAlias: 'upload');
      expect(r.code, 0, reason: 'alias-case: ${r.err}');
    });

    test('keytool -list is asked for the configured alias', () {
      // Without `-alias`, keytool lists the whole keystore and the step reads
      // the FIRST entry, so a multi-entry keystore passes here and fails in
      // release.yml (#165). The answer is identical either way; only the
      // question differs, so the question is what is asserted.
      final r = runStep();
      final listCall = r.calls
          .split('\n')
          .firstWhere((l) => l.startsWith('-list'), orElse: () => '');
      expect(
        listCall,
        contains('-alias upload'),
        reason: 'keytool -list must be scoped to the configured alias',
      );
    });

    test('a key password that differs from the store password is refused', () {
      // #143. PKCS12 has one password, so this is the only checkable form.
      final r = runStep(pass: 'STORE-PASS-one', keyPass: 'KEY-PASS-two');
      expect(r.code, isNot(0), reason: 'mismatched passwords must fail');
      expect(r.err, contains('HS_KEY_PASS differs'));
    });

    test('a keystore that is not the committed certificate is refused', () {
      final r = runStep(ksFp: 'AA:BB', pemFp: 'CC:DD');
      expect(r.code, isNot(0), reason: 'fingerprint mismatch must fail');
      expect(r.err, contains('NOT the one this repository committed'));
    });

    for (final missing in const [
      'HS_KEYSTORE_B64',
      'HS_KEYSTORE_PASS',
      'HS_KEY_ALIAS',
      'HS_KEY_PASS',
    ]) {
      test('an empty $missing refuses before touching the keystore', () {
        final r = runStep(
          b64: missing == 'HS_KEYSTORE_B64' ? '' : 'a2V5c3RvcmU=',
          pass: missing == 'HS_KEYSTORE_PASS' ? '' : 'EMPTY-PROBE-pw',
          alias: missing == 'HS_KEY_ALIAS' ? '' : 'upload',
          keyPass: missing == 'HS_KEY_PASS' ? '' : 'EMPTY-PROBE-pw',
        );
        expect(r.code, isNot(0), reason: 'empty $missing must fail');
        expect(r.err, contains('$missing is not set'));
        expect(
          r.calls.trim(),
          isEmpty,
          reason: 'the secret check must run before any keytool call',
        );
      });
    }

    test('no password reaches stdout or the job summary', () {
      // The leak this group exists to make impossible: one line reading
      // `($HS_KEYSTORE_PASS)` in the summary table put the upload-keystore
      // password into a rendered, downloadable, retained artifact (#173).
      const secret = 'S3CRET-store-pw-9f2a';
      final r = runStep(pass: secret);
      expect(r.code, 0, reason: 'leak-check: ${r.err}');
      for (final where in {
        'stdout': r.out,
        'stderr': r.err,
        'summary': r.summary,
      }.entries) {
        expect(
          where.value,
          isNot(contains(secret)),
          reason: 'the store password reached ${where.key}',
        );
      }
    });
  });

  group('the keystore_check step of release.yml, as the tag path runs it', () {
    // #158 put the HS_KEY_PASS == HS_KEYSTORE_PASS assertion on the tag path.
    // Deleting it was green, and so was INVERTING it — which fails every
    // correct release while the suite reports all green (#174).
    late String stepScript;

    setUp(() {
      final workflow = Workflow.parse(
        '.github/workflows/release.yml',
        readFile('.github/workflows/release.yml'),
      );
      expect(workflow.problem, isNull);
      final step = workflow.job('ship')!.stepById('keystore_check');
      expect(step, isNotNull, reason: 'the `keystore_check` step has gone');
      stepScript = step!.run!;

      _writeExecutable('${_tmp.path}/bin/keytool', r"""#!/bin/sh
printf '%s\n' "$*" >> "$HS_KEYTOOL_CALLS"
exit 0
""");
    });

    ({int code, String out, String err, String calls}) runStep({
      required String pass,
      required String keyPass,
      String alias = 'upload',
    }) {
      final script = '${_tmp.path}/keystore_check.sh';
      File(script).writeAsStringSync(stepScript);
      final runnerTemp = '${_tmp.path}/runner2';
      Directory(runnerTemp).createSync(recursive: true);
      File('$runnerTemp/upload.keystore').writeAsStringSync('not a keystore');
      final calls = '${_tmp.path}/keytool_calls2.txt';
      File(calls).writeAsStringSync('');

      final r = _exec(
        '/bin/bash',
        [script],
        workingDirectory: repoRoot.path,
        environment: {
          'PATH': '${_tmp.path}/bin:/usr/bin:/bin',
          'RUNNER_TEMP': runnerTemp,
          'HS_KEYSTORE_PASS': pass,
          'HS_KEY_ALIAS': alias,
          'HS_KEY_PASS': keyPass,
          'HS_KEYTOOL_CALLS': calls,
        },
      );
      return (
        code: r.code,
        out: r.out,
        err: r.err,
        calls: File(calls).readAsStringSync(),
      );
    }

    test('matching passwords pass', () {
      final r = runStep(
        pass: 'MATCHING-PASS-same',
        keyPass: 'MATCHING-PASS-same',
      );
      expect(r.code, 0, reason: 'matching: ${r.err}');
      expect(r.out, contains('the keystore opens'));
    });

    test('differing passwords are refused before the build', () {
      final r = runStep(pass: 'STORE-PASS-one', keyPass: 'KEY-PASS-two');
      expect(r.code, isNot(0), reason: 'differing passwords must fail');
      expect(r.err, contains('HS_KEY_PASS differs'));
      expect(
        r.calls.trim(),
        isEmpty,
        reason: 'the comparison must run before keytool, not after',
      );
    });

    test('keytool is scoped to the configured alias', () {
      final r = runStep(
        pass: 'MATCHING-PASS-same',
        keyPass: 'MATCHING-PASS-same',
        alias: 'upload',
      );
      expect(r.calls, contains('-alias upload'));
    });

    test('no password reaches stdout or stderr', () {
      const secret = 'S3CRET-tag-path-7b1c';
      final r = runStep(pass: secret, keyPass: secret);
      expect(r.code, 0, reason: 'leak: ${r.err}');
      expect(r.out, isNot(contains(secret)));
      expect(r.err, isNot(contains(secret)));
    });
  });

  test('nothing in this file starts a process except the chokepoint', () {
    // The reason the chokepoint cannot quietly stop covering things.
    //
    // #200 moved the leak scan into `_run` and said "there is no registration
    // step left to leave out". There was: `_run` was not how the workflow
    // steps were tested, four groups built their own runner, and the whole
    // service-account key reached $GITHUB_STEP_SUMMARY with the suite green
    // (#208). The hole moved from "forgot to plant" to "forgot to use _run".
    //
    // Round eight then walked past this rule six ways out of seven. It
    // matched the literal `Process.runSync(` on one line, so `Process.start`,
    // `Process.run`, a tear-off (`const runner = Process.runSync;`) and a
    // bare marker with no reason all escaped — and so did an ordinary call
    // merely PRECEDED, within thirty lines, by a comment containing the text
    // for the end of `_exec`'s signature, which is how the old "am I inside
    // _exec" test decided.
    //
    // So: every `Process.` in this file is an offence unless it sits inside
    // `_exec`'s own body, and that body's extent is MEASURED rather than
    // guessed from a nearby string.
    // THIS FILE ONLY, and the block below says why.
    //
    // What stood here claimed the opposite — "EVERY guard test file …
    // everywhere else a process start is an offence" — describing a change
    // that was written and then reverted in the same commit, twenty lines
    // above the comment that says it was reverted. It survived its own
    // revert and asserted a guard that does not exist (#229).
    const chokepointFile = 'test/guards/secrets_scripts_test.dart';
    final source = readFile(chokepointFile);
    final lines = source.split('\n');

    final execStart = lines.indexWhere((l) => l.contains(') _exec('));
    expect(
      execStart,
      isNot(-1),
      reason: 'leak-chokepoint: `_exec` is gone; this rule guards nothing',
    );
    final execEnd = lines.indexWhere((l) => l == '}', execStart);
    expect(
      execEnd,
      isNot(-1),
      reason: 'leak-chokepoint: could not find the end of `_exec`',
    );

    final offenders = <String>[];
    final startsProcess = RegExp(r'\bProcess\s*\.');

    // NOT the other guard files, and #222 says why rather than the silence
    // that would otherwise stand here.
    //
    // Scoping this rule across `test/guards/` is correct and it is what #220
    // asked for. Doing it surfaced raw process starts in most of the other
    // guard files — including `signing_guard_test.dart`, which runs real
    // Flutter builds with the HS_* signing variables, so those genuinely
    // need scanning. #222 carries the enumerated list; it is not restated
    // here, and neither is a count, because four different ones have been
    // written down so far and none of them was checked (#239).
    //
    // Routing those calls through a shared chokepoint is a refactor of the
    // test infrastructure, not a line change, and writing an exemption for
    // each instead would be precisely the self-granted exemption tightened
    // below.
    //
    // So the scope stays as it is, the gap is filed with the enumerated list,
    // and this comment exists so the next reader knows the limit is known
    // rather than overlooked.

    final harmless = RegExp("Process\\.runSync\\(\\s*'(chmod|command|which)'");
    for (var i = 0; i < lines.length; i++) {
      if (!startsProcess.hasMatch(lines[i])) continue; // rule-self-reference
      // Prose. A comment cannot start a process, and this file discusses
      // `Process.runSync` at length in the comments explaining why it is
      // funnelled through one place.
      if (lines[i].trimLeft().startsWith('//')) continue;
      // The chokepoint itself.
      if (i >= execStart && i <= execEnd) continue;
      // This rule's own source.
      if (lines[i].contains('rule-self-reference')) continue;
      // Argument-less helpers that carry no secret and produce no output
      // worth scanning.
      // The LINE, not a window. Joining three lines meant any raw process
      // call with a `chmod` within two lines was exempt — which is the shape
      // of an ordinary write-then-chmod helper, so the exemption laundered
      // the bypass it sat next to (#220).
      if (harmless.hasMatch(lines[i])) continue;
      // An exemption must be DECLARED within four lines AND carry a reason.
      // A bare `// chokepoint-exempt:` with nothing after it was accepted,
      // which is an exemption anyone can grant themselves in silence (#208).
      final preceding = lines
          .sublist((i - 4).clamp(0, lines.length), i)
          .join('\n');
      final marker = RegExp(r'chokepoint-exempt:\s*(\S.*)')
          .firstMatch(preceding);
      if (marker != null && marker.group(1)!.trim().length >= 20) continue;
      offenders.add('line ${i + 1}: ${lines[i].trim()}');
    }
    expect(
      offenders,
      isEmpty,
      reason:
          'leak-chokepoint: these start a process without going through '
          '`_exec`, so nothing derives their secrets or scans their output. '
          'An exemption is a `// chokepoint-exempt: <reason>` comment within '
          'four lines, and the reason must say something:\n'
          '${offenders.join('\n')}',
    );
  });

  group('no script puts a secret on a command line', () {
    // `set_ci_secrets.sh:130` states this as fact — "`-storepass:env` keeps
    // the password off the command line and out of the process table" — and
    // nothing tested it. Changing it to `-storepass "$KEYSTORE_PASS"` left
    // the whole suite green (#176, #190).
    //
    // A source rule rather than a stub check, because the pre-flight resolves
    // the REAL keytool by its pinned path, so a stub never sees that argv.
    // The property is about what the script writes, and that is readable.
    // tools/*.sh AND the workflows. #186 demonstrated the defect in
    // play-api-check.yml; the rule was written over tools/ only, so the
    // issue's own reproduction stayed green after it was closed (#200).
    final scripts = [
      ...Directory('${repoRoot.path}/tools')
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.sh')),
      ...Directory('${repoRoot.path}/.github/workflows')
          .listSync()
          .whereType<File>()
          .where((f) => RegExp(r'\.ya?ml$').hasMatch(f.path)),
    ];

    test('the tools directory was found', () {
      expect(
        scripts,
        isNotEmpty,
        reason:
            'sanity: no scripts scanned, so the rule below asserts '
            'nothing',
      );
    });

    test('keytool passwords are passed by env, never as an argument', () {
      final offenders = <String>[];
      for (final f in scripts) {
        final joined = f
            .readAsStringSync()
            .replaceAll(RegExp(r'\\\n\s*'), ' ')
            .split('\n');
        for (var i = 0; i < joined.length; i++) {
          final line = joined[i];
          if (line.trimLeft().startsWith('#')) continue;
          // `-storepass:env NAME` and `-keypass:env NAME` are the safe forms.
          // Anything else after -storepass/-keypass is a value on argv.
          for (final m in RegExp(
            // `\s+` missed `-storepass$IFS"$PASS"`; `[\s$]` covers it.
            r'-(storepass|keypass)(:env)?[\s$]+(\S+)',
          ).allMatches(line)) {
            if (m.group(2) == ':env') continue;
            offenders.add(
              '${f.path.split('/').last}: `${m.group(0)}` puts a password on '
              'the command line, where any process can read it from the '
              'process table. Use -${m.group(1)}:env NAME',
            );
          }
        }
      }
      expect(offenders, isEmpty, reason: offenders.join('\n'));
    });

    test('no secret file is expanded into an argument', () {
      // `gh secret set --body "$(cat "$KEY_PATH")"` puts the whole
      // service-account private key on the command line. The scripts pipe on
      // stdin instead; this is what keeps it that way (#176).
      final offenders = <String>[];
      for (final f in scripts) {
        final text = f.readAsStringSync().replaceAll(RegExp(r'\\\n\s*'), ' ');
        for (final line in text.split('\n')) {
          if (line.trimLeft().startsWith('#')) continue;
          // `=` as well as whitespace, and `$(< file)` as well as `cat`.
          if (RegExp(r'''--body[\s=]+"?\$\(\s*(cat\b|<)''').hasMatch(line)) {
            offenders.add(
              '${f.path.split('/').last}: `--body "\$(cat …)"` expands a '
              'secret file into argv. Pipe it on stdin',
            );
          }
        }
      }
      expect(offenders, isEmpty, reason: offenders.join('\n'));
    });
  });
}
