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
  return (code: r.exitCode, out: r.stdout.toString(), err: r.stderr.toString());
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
      _writeExecutable(
        '${_tmp.path}/bin/keytool',
        '#!/bin/sh\necho "Key and Certificate Management"\nexit 0\n',
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

    void expectNoLeak(({int code, String out, String err}) r, String why) {
      for (final secret in const [password, alias, keyBody]) {
        expect(
          r.out,
          isNot(contains(secret)),
          reason: 'leak: $why printed a secret value on stdout',
        );
        expect(
          r.err,
          isNot(contains(secret)),
          reason: 'leak: $why printed a secret value on stderr',
        );
      }
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

  group('setup_play_ci.sh past the confirmation gate', () {
    // The four refusal tests all stopped at the account gate, so nothing ever
    // exercised a line below it — which is where the #134 trap, the key
    // deletion and the IAM behaviour live. All three survived the mutation
    // battery (#160).
    late String gcloudLog;

    void stubGcloud({bool keysCreateFails = false}) {
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
  "iam service-accounts describe") exit 0 ;;
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
      stubGcloud();
      _run(
        'tools/setup_play_ci.sh',
        env: {'HS_PLAY_ACCOUNT': 'owner@example.com'},
      );
      final calls = File(gcloudLog).readAsStringSync();
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
}
