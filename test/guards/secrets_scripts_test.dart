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

({int code, String out, String err}) _run(
  String script, {
  Map<String, String> env = const {},
}) {
  final r = Process.runSync(
    'bash',
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
  return (code: r.exitCode, out: r.stdout.toString(), err: r.stderr.toString());
}

void _writeCredentials(String text) {
  File(_credentials)
    ..createSync(recursive: true)
    ..writeAsStringSync(text);
}

List<int> _uploadedLengths() {
  final f = File(_ghLog);
  if (!f.existsSync()) return const [];
  return f
      .readAsLinesSync()
      .where((l) => l.startsWith('SET '))
      .map((l) => int.parse(l.split('bytes=')[1]))
      .toList();
}

void main() {
  setUp(() {
    _tmp = Directory.systemTemp.createTempSync('hs-secrets-guard');
    Directory('$_home/HonestArcadeApps/secrets').createSync(recursive: true);
    // Records the name and byte length of what it is given. Never the value.
    _writeExecutable('${_tmp.path}/bin/gh', '''#!/bin/sh
if [ "\$1 \$2" = "secret list" ]; then exit 0; fi
n=\$(wc -c | tr -d ' ')
echo "SET bytes=\$n" >> "\$GH_LOG"
''');
    File(_ghLog).writeAsStringSync('');
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
      // No keytool: the pre-flight skips loudly, which is the documented
      // behaviour and lets the parse be tested on its own.
      final r = _run(
        'tools/set_ci_secrets.sh',
        env: {'HS_KEYTOOL': '/nonexistent/keytool'},
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

  group('setup_play_ci.sh', () {
    void stubGcloud(String account) {
      _writeExecutable('${_tmp.path}/bin/gcloud', '''#!/bin/sh
case "\$1 \$2" in "auth list") echo "$account"; exit 0 ;; esac
exit 0
''');
    }

    test('no gcloud on PATH is refused', () {
      // A minimal PATH on purpose: this machine may well have a real gcloud,
      // and finding it would test the login check instead of this one.
      final r = _run(
        'tools/setup_play_ci.sh',
        env: {'PATH': '${_tmp.path}/bin:/usr/bin:/bin'},
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

  group('play-api-check.yml', () {
    // The tracks listing is the step that could not pass the case it exists
    // for: `grep` exits 1 on an empty list, and under `set -o pipefail` that
    // killed the step before the summary (#127). Extracted and run here so
    // the behaviour is asserted rather than read.
    ({int code, String out}) runTracksPipeline(String json) {
      final file = '${_tmp.path}/tracks.json';
      File(file).writeAsStringSync(json);
      final r = Process.runSync('bash', [
        '-c',
        'set -euo pipefail; '
            'names="\$(tr -d \' \\n\' < $file | '
            "{ grep -oE '\"track\":\"[a-z]+\"' || true; } | "
            'cut -d\'"\' -f4 | sort -u | tr \'\\n\' \' \')"; '
            'echo "TRACKS[\$names]"',
      ]);
      return (code: r.exitCode, out: r.stdout.toString().trim());
    }

    test('an empty tracks list passes, which is a brand-new app', () {
      final r = runTracksPipeline(
        '{"kind":"androidpublisher#tracksListResponse"}',
      );
      expect(r.code, 0, reason: 'empty-tracks: the step must not fail here');
      expect(r.out, 'TRACKS[]');
    });

    test('a populated tracks list is read', () {
      final r = runTracksPipeline(
        '{"tracks":[{"track":"internal"},{"track":"alpha"}]}',
      );
      expect(r.code, 0);
      expect(r.out, 'TRACKS[alpha internal ]');
    });

    test('the workflow checks the HTTP status of the tracks call', () {
      // The complement of the two above: an empty list and a 403 used to be
      // indistinguishable, because neither contained a "track".
      final text = readFile('.github/workflows/play-api-check.yml');
      expect(
        text,
        contains('tracks_status'),
        reason: 'tracks-status: the tracks call must check its HTTP status',
      );
      expect(
        text,
        contains('This is not the same as an app with no tracks yet'),
      );
    });

    test('the alias is compared, not merely printed', () {
      final text = readFile('.github/workflows/play-api-check.yml');
      expect(text, contains(r'if [ "$alias_got" != "$alias_want" ]'));
    });

    test('it does not claim a PKCS12 -keypass check proves anything', () {
      // keytool ignores -keypass for PKCS12 and exits 0, so the old check
      // could not fail (#143).
      final text = readFile('.github/workflows/play-api-check.yml');
      expect(
        text,
        isNot(contains('Proves the KEY password too')),
        reason: 'keypass-claim: that claim was false for PKCS12',
      );
      expect(text, contains(r'if [ "$HS_KEY_PASS" != "$HS_KEYSTORE_PASS" ]'));
    });
  });
}
