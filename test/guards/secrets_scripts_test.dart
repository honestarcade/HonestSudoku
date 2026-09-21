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

void _writeExecutable(String path, String body) {
  File(path)
    ..createSync(recursive: true)
    ..writeAsStringSync(body);
  Process.runSync('chmod', ['+x', path]);
}

/// Values that must never appear anywhere a script can write.
///
/// A test registers what it planted; `_run` then checks **every** channel on
/// **every** invocation. #155's test searched stdout and stderr for three
/// literals on three chosen code paths, and #176 listed nine shapes it
/// missed — appended leaks on unasserted paths, a secret written to a file, a
/// private key copied to a file, argv (two channels), a partial value, and
/// base64/hex/reversed transforms. #176 was closed without closing any of
/// them (#190).
///
/// Registered rather than hard-coded, because the values differ per test and
/// a fixed list is how the three-literals version stayed stuck.
final Set<String> _sentinels = {};

void _plant(Iterable<String> values) {
  for (final v in values) {
    if (v.trim().length >= 6) _sentinels.add(v);
  }
}

/// Every form of [secret] a script could emit instead of the literal.
///
/// A leak does not have to be faithful to be a leak: eight characters of a
/// password narrows a search enormously, and `| base64` defeats a literal
/// scan completely while remaining trivially reversible.
Iterable<String> _leakForms(String secret) sync* {
  yield secret;
  yield base64.encode(utf8.encode(secret));
  yield secret.split('').reversed.join();
  yield utf8
      .encode(secret)
      .map((b) => b.toRadixString(16).padLeft(2, '0'))
      .join();
  if (secret.length >= 8) yield secret.substring(0, 8);
}

/// Everything a script wrote that a human or another process could read.
///
/// Files under the fake `$HOME` are included because a script that writes a
/// secret to disk has leaked it just as surely as one that prints it, and
/// that row of #176's table survived the fix. Recorded argv is included
/// because `set_ci_secrets.sh:130` asserts `-storepass:env` "keeps the
/// password off the command line and out of the process table" — a property
/// nothing tested, while changing it to `-storepass "$PASS"` stayed green.
List<({String where, String text})> _channels(String out, String err) {
  final channels = <({String where, String text})>[
    (where: 'stdout', text: out),
    (where: 'stderr', text: err),
  ];
  for (final log in const ['gh.log', 'keytool.log', 'gcloud.log']) {
    final f = File('${_tmp.path}/$log');
    if (f.existsSync()) {
      channels.add((where: '$log (recorded argv)', text: f.readAsStringSync()));
    }
  }
  final home = Directory(_home);
  if (home.existsSync()) {
    for (final entity in home.listSync(recursive: true)) {
      if (entity is! File) continue;
      // The credentials file is written by make_upload_key.sh on purpose and
      // is the one place a secret is meant to land; every other file under
      // $HOME is a leak.
      if (entity.path == _credentials) continue;
      String text;
      try {
        text = entity.readAsStringSync();
      } on FormatException {
        continue; // a binary file the scripts produced, e.g. a keystore
      }
      channels.add((
        where: 'file ${entity.path.replaceFirst(_home, r'$HOME')}',
        text: text,
      ));
    }
  }
  return channels;
}

/// Fails if any planted value, in any of its forms, reached any channel.
void _assertNoLeak(String out, String err, String why) {
  for (final secret in _sentinels) {
    for (final form in _leakForms(secret)) {
      for (final channel in _channels(out, err)) {
        expect(
          channel.text,
          isNot(contains(form)),
          reason:
              'leak: $why — a planted secret reached ${channel.where}'
              '${form == secret ? '' : ' (as ${_describeForm(secret, form)})'}',
        );
      }
    }
  }
}

String _describeForm(String secret, String form) {
  if (form == base64.encode(utf8.encode(secret))) return 'base64';
  if (form == secret.split('').reversed.join()) return 'reversed';
  if (form.length == 8) return 'its first 8 characters';
  return 'hex';
}

({int code, String out, String err}) _run(
  String script, {
  Map<String, String> env = const {},
}) {
  final r = Process.runSync(
    '/bin/bash',
    [script],
    workingDirectory: repoRoot.path,
    includeParentEnvironment: false,
    environment: {
      'PATH':
          '${_tmp.path}/bin:${Platform.environment['PATH'] ?? '/usr/bin:/bin'}',
      'HOME': _home,
      'GH_LOG': _ghLog,
      ...env,
    },
    stdoutEncoding: utf8,
    stderrEncoding: utf8,
  );
  final out = r.stdout.toString();
  final err = r.stderr.toString();
  // Every run, not three chosen ones. A test cannot forget to check, which
  // is how nine of #176's eleven rows survived its own fix (#190).
  _assertNoLeak(out, err, script);
  return (code: r.exitCode, out: out, err: err);
}

/// Sentinels are per-test; a value planted by one group must not make another
/// group's unrelated output look like a leak.
void _clearSentinels() => _sentinels.clear();

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
        'export HS_KEYSTORE_PASS="one"\n'
        'export HS_KEY_ALIAS="upload"\n'
        'export HS_KEY_PASS="two"\n',
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
        'export HS_KEYSTORE_PASS="pw"\n'
        'export HS_KEY_ALIAS="upload"\n'
        'export HS_KEY_PASS="pw"\n',
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
        'export HS_KEYSTORE_PASS="pw"\n'
        'export HS_KEY_ALIAS="upload"\n'
        'export HS_KEY_PASS="pw"\n',
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
        'export HS_KEYSTORE_PASS="pw"\n'
        'export HS_KEY_ALIAS="upload"\n'
        'export HS_KEY_PASS="pw"\n',
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
        'export HS_KEYSTORE_PASS="pw"\n'
        'export HS_KEY_ALIAS="upload"\n'
        'export HS_KEY_PASS="pw"\n',
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
    const password = 'S3CRET-PASSWORD-abcdefghijklmnop';
    const alias = 'S3CRET-ALIAS-qrstuvwx';
    const keyBody = 'S3CRET-PRIVATE-KEY-yz0123456789';

    // Registered, not searched here: `_run` scans every channel on every
    // invocation, so a path this group never thought to list is covered
    // anyway. That is the difference between #155's three chosen cases and
    // what #176 asked for (#190).
    setUp(() => _plant(const [password, alias, keyBody]));
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
      _plant([password]);
      addTearDown(_clearSentinels);

      final made = Process.runSync(
        '/bin/bash',
        ['tools/make_upload_key.sh'],
        workingDirectory: repoRoot.path,
        includeParentEnvironment: false,
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
        stdoutEncoding: utf8,
        stderrEncoding: utf8,
      );
      expect(made.exitCode, 0, reason: 'make: ${made.stderr}');
      // This script is invoked directly rather than through `_run`, so the
      // scan has to be asked for. It was outside the leak group entirely —
      // the last row of #176's table — and it is the only script holding the
      // plaintext password as an environment variable (#190).
      _assertNoLeak(
        made.stdout.toString(),
        made.stderr.toString(),
        'make_upload_key.sh',
      );

      // 1. Nothing ran while the file was being written.
      expect(
        File(marker).existsSync() || File('${marker}2').existsSync(),
        isFalse,
        reason: 'write: the password executed while the file was written',
      );

      // 2. Nothing runs if someone sources it anyway, and the value comes back
      //    whole.
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
      final opens = Process.runSync(
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
        stdoutEncoding: utf8,
      );
      expect(
        opens.exitCode,
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
        final r = Process.runSync(
          '/bin/bash',
          ['tools/make_upload_key.sh'],
          workingDirectory: repoRoot.path,
          includeParentEnvironment: false,
          environment: {
            'PATH': Platform.environment['PATH'] ?? '/usr/bin:/bin',
            'HOME': _home,
            'HS_KEYSTORE_PASS': 'irrelevant',
            'HS_KEYTOOL': keytool,
            'HS_UPLOAD_CERT_OUT': '$_home/cert.pem',
          },
          stdoutEncoding: utf8,
          stderrEncoding: utf8,
        );
        expect(r.exitCode, 2, reason: 'overwrite: ${r.stderr}');
        expect(r.stderr, contains('refusing to overwrite'));
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
      _writeExecutable('${_tmp.path}/bin/gcloud', '''#!/bin/sh
case "\$1 \$2" in
  "auth activate-service-account") exit 0 ;;
  "auth print-access-token") echo "ya29.FAKE-TOKEN"; exit 0 ;;
esac
exit 0
''');
      // curl: answers from files the test plants, so each HTTP status and body
      // is the scenario's choice.
      _writeExecutable('${_tmp.path}/bin/curl', r'''#!/bin/sh
out=""; kind="edits"
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
''');
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

      final r = Process.runSync(
        '/bin/bash',
        [script],
        workingDirectory: repoRoot.path,
        includeParentEnvironment: false,
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
        stdoutEncoding: utf8,
        stderrEncoding: utf8,
      );
      return (
        code: r.exitCode,
        out: r.stdout.toString(),
        err: r.stderr.toString(),
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

      final r = Process.runSync(
        '/bin/bash',
        [script],
        workingDirectory: repoRoot.path,
        includeParentEnvironment: false,
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
        stdoutEncoding: utf8,
        stderrEncoding: utf8,
      );
      return (
        code: r.exitCode,
        out: r.stdout.toString(),
        err: r.stderr.toString(),
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
      final r = runStep(pass: 'one', keyPass: 'two');
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
          pass: missing == 'HS_KEYSTORE_PASS' ? '' : 'pw',
          alias: missing == 'HS_KEY_ALIAS' ? '' : 'upload',
          keyPass: missing == 'HS_KEY_PASS' ? '' : 'pw',
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
      const secret = 'S3CRET-store-password';
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

      final r = Process.runSync(
        '/bin/bash',
        [script],
        workingDirectory: repoRoot.path,
        includeParentEnvironment: false,
        environment: {
          'PATH': '${_tmp.path}/bin:/usr/bin:/bin',
          'RUNNER_TEMP': runnerTemp,
          'HS_KEYSTORE_PASS': pass,
          'HS_KEY_ALIAS': alias,
          'HS_KEY_PASS': keyPass,
          'HS_KEYTOOL_CALLS': calls,
        },
        stdoutEncoding: utf8,
        stderrEncoding: utf8,
      );
      return (
        code: r.exitCode,
        out: r.stdout.toString(),
        err: r.stderr.toString(),
        calls: File(calls).readAsStringSync(),
      );
    }

    test('matching passwords pass', () {
      final r = runStep(pass: 'same', keyPass: 'same');
      expect(r.code, 0, reason: 'matching: ${r.err}');
      expect(r.out, contains('the keystore opens'));
    });

    test('differing passwords are refused before the build', () {
      final r = runStep(pass: 'one', keyPass: 'two');
      expect(r.code, isNot(0), reason: 'differing passwords must fail');
      expect(r.err, contains('HS_KEY_PASS differs'));
      expect(
        r.calls.trim(),
        isEmpty,
        reason: 'the comparison must run before keytool, not after',
      );
    });

    test('keytool is scoped to the configured alias', () {
      final r = runStep(pass: 'same', keyPass: 'same', alias: 'upload');
      expect(r.calls, contains('-alias upload'));
    });

    test('no password reaches stdout or stderr', () {
      const secret = 'S3CRET-tag-path';
      final r = runStep(pass: secret, keyPass: secret);
      expect(r.code, 0, reason: 'leak: ${r.err}');
      expect(r.out, isNot(contains(secret)));
      expect(r.err, isNot(contains(secret)));
    });
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
    final scripts = Directory('${repoRoot.path}/tools')
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.sh'))
        .toList();

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
            r'-(storepass|keypass)(:env)?\s+(\S+)',
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
          if (RegExp(r'--body\s+"?\$\(\s*cat\b').hasMatch(line)) {
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
