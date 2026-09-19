@Tags(['guard'])
library;

// Guard for #13: no secret value can live in this repository, and the signing
// inputs come from the environment.
//
// The failure this prevents is not subtle — a password pasted into
// build.gradle.kts, or a keystore committed "temporarily" — but it is easy, and
// git remembers. The gitignore assertions matter as much as the source ones:
// a pattern silently deleted is how a key gets published.
//
// What this does NOT cover: whether the key in use is the one Play has
// enrolled. M7's enrolment uses the committed public certificate for that. It
// also says nothing about whether a real build succeeds — only what the gate
// reports it is about to do.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'repo_files.dart';

const _gradle = 'android/app/build.gradle.kts';

const _signingVars = [
  'HS_KEYSTORE_PATH',
  'HS_KEYSTORE_PASS',
  'HS_KEY_ALIAS',
  'HS_KEY_PASS',
];

/// Patterns that must each be their own line in .gitignore.
const _requiredIgnores = [
  '*.keystore',
  '*.jks',
  '*.p12',
  'key.properties',
  '*credentials*.txt',
];

/// Runs `tools/gate.sh --signing-mode` with exactly `env` set, plus PATH.
///
/// The parent environment is deliberately excluded: a developer who has the
/// real HS_* variables exported would otherwise flip every one of these cases
/// and the suite would pass for the wrong reason.
String _signingMode(Map<String, String> env) {
  final result = Process.runSync(
    'tools/gate.sh',
    ['--signing-mode'],
    workingDirectory: repoRoot.path,
    includeParentEnvironment: false,
    environment: {
      'PATH': Platform.environment['PATH'] ?? '/usr/bin:/bin',
      ...env,
    },
    stdoutEncoding: utf8,
    stderrEncoding: utf8,
  );
  expect(
    result.exitCode,
    0,
    reason: 'signing-mode: the query flag must not fail.\n${result.stderr}',
  );
  expect(
    result.stdout.toString(),
    isNot(contains('[1/')),
    reason:
        'signing-mode: --signing-mode must report and stop, not run the gate',
  );
  return result.stdout.toString().trim();
}

const _keystorePath = 'HS_KEYSTORE_PATH';
const _allFour = {
  'HS_KEYSTORE_PATH': '/tmp/upload.p12',
  'HS_KEYSTORE_PASS': 'x',
  'HS_KEY_ALIAS': 'upload',
  'HS_KEY_PASS': 'x',
};

void _signingModeTests() {
  // Why these exist: the partial branch did not, and nothing could have said
  // so. The gate's message was only ever read by a human watching a real run,
  // and a real run either has all four variables or none, so the case that was
  // wrong was the case nobody ever saw (#82).

  test('nothing set reports the debug fallback', () {
    expect(_signingMode(const {}), contains('debug fallback'));
  });

  test('all four set reports the upload key', () {
    final mode = _signingMode(_allFour);
    expect(mode, contains('signing with the upload key'));
    expect(mode, isNot(contains('debug fallback')));
  });

  test('all four set with HS_RELEASE=1 still reports the upload key', () {
    final mode = _signingMode({..._allFour, 'HS_RELEASE': '1'});
    expect(mode, contains('signing with the upload key'));
    expect(
      mode,
      isNot(contains('Gradle will refuse')),
      reason:
          'release-complete: with every variable present there is nothing for '
          'Gradle to refuse',
    );
  });

  test('HS_RELEASE=1 with nothing set says the build will be refused', () {
    final mode = _signingMode(const {'HS_RELEASE': '1'});
    expect(mode, contains('Gradle will refuse'));
    expect(
      mode,
      isNot(contains('debug fallback')),
      reason:
          'release-empty: HS_RELEASE=1 is the mode that forbids the debug '
          'fallback, so it must never be described as one',
    );
  });

  // The #82 regression, one case per missing variable. Each is the typo a
  // contributor actually makes, and each must be named rather than described.
  for (final absent in _signingVars) {
    test('$absent missing on its own is reported as partial', () {
      final env = Map<String, String>.from(_allFour)..remove(absent);
      final mode = _signingMode(env);
      expect(
        mode,
        contains('partial'),
        reason:
            'partial-$absent: a partly set environment used to report "no '
            'HS_* variables set", which was false twice over.\nGot: $mode',
      );
      expect(
        mode,
        contains(absent),
        reason:
            'partial-$absent: the message must name the variable that is '
            'empty — that is the whole value of it.\nGot: $mode',
      );
      expect(
        mode,
        isNot(contains('debug fallback')),
        reason:
            'partial-$absent: build.gradle.kts raises a GradleException for '
            'any partial set in every mode, so there is no fallback to '
            'describe.\nGot: $mode',
      );
    });
  }

  test('an empty value counts as missing, not as set', () {
    // `export HS_KEY_PASS=` is a set variable with nothing in it, and Gradle's
    // own check uses isNullOrBlank. The two must agree or the gate's headline
    // contradicts the build three seconds later.
    final env = Map<String, String>.from(_allFour)..[_keystorePath] = '';
    final mode = _signingMode(env);
    expect(mode, contains('partial'));
    expect(mode, contains(_keystorePath));
  });

  test('the build file agrees that a partial set is always an error', () {
    // The gate's new message is a claim about build.gradle.kts. If that file
    // ever starts tolerating a partial set, this message becomes the wrong
    // one again, so the claim is pinned to its source.
    final gradle = readFile(_gradle);
    expect(
      gradle,
      contains('hsPresent.isNotEmpty() && !hsSigningComplete'),
      reason:
          'partial-is-error: gate.sh tells the user Gradle will refuse a '
          'partly set environment. build.gradle.kts no longer has the check '
          'that makes that true.',
    );
  });
}

void main() {
  group('gate.sh signing mode', _signingModeTests);

  test('the build file holds no literal secret', () {
    final gradle = readFile(_gradle);
    final offenders = <String>[];
    // A literal assignment is the shape of a pasted secret. The env-var form
    // (storePassword = System.getenv(...)) has no quote after the `=`.
    for (final literal in const [
      'storePassword = "',
      'keyPassword = "',
      'storeFile = file("',
    ]) {
      if (gradle.contains(literal)) {
        offenders.add('$_gradle: contains literal `$literal…`');
      }
    }
    expect(
      offenders,
      isEmpty,
      reason: describeOffenders('no-literal-secrets', offenders),
    );
  });

  test(
    'the build file reads all four signing variables from the environment',
    () {
      final gradle = readFile(_gradle);
      final missing = <String>[];
      for (final name in _signingVars) {
        if (!gradle.contains(name)) missing.add('$_gradle: never reads $name');
      }
      expect(
        missing,
        isEmpty,
        reason: describeOffenders('env-signing-vars', missing),
      );
    },
  );

  test('there is no key.properties file', () {
    // The Android convention this project deliberately does not use: a
    // properties file next to the build is a secret one `git add .` away from
    // being published.
    expect(
      pathExists('android/key.properties'),
      isFalse,
      reason:
          'no-key-properties: android/key.properties exists — this '
          'project reads signing inputs from the environment instead',
    );
  });

  test('.gitignore refuses every kind of key material', () {
    final lines = readFile('.gitignore')
        .split('\n')
        .map((l) => l.trim())
        .toSet();
    final missing = <String>[];
    for (final pattern in _requiredIgnores) {
      if (!lines.contains(pattern)) {
        missing.add('.gitignore: missing the line `$pattern`');
      }
    }
    expect(
      missing,
      isEmpty,
      reason: describeOffenders('gitignore-signing', missing),
    );
  });

  test('no key material is tracked anywhere in the repository', () {
    // The ignore rules above say what git should skip; this says what git
    // actually holds. They can disagree — a file added before the rule existed
    // stays tracked forever.
    final offenders = <String>[];
    for (final path in trackedFilesUnder('.')) {
      final lower = path.toLowerCase();
      if (lower.endsWith('.keystore') ||
          lower.endsWith('.jks') ||
          lower.endsWith('.p12') ||
          lower.endsWith('key.properties') ||
          (lower.contains('credentials') && lower.endsWith('.txt'))) {
        offenders.add('tracked: $path');
      }
    }
    expect(
      offenders,
      isEmpty,
      reason: describeOffenders('no-tracked-key-material', offenders),
    );
  });

  test(
    'the public upload certificate is committed, and only the public part',
    () {
      const cert = 'android/signing/upload_certificate.pem';
      expect(
        pathExists(cert),
        isTrue,
        reason:
            'upload-cert: $cert is missing — M7 needs it for Play App '
            'Signing enrolment',
      );
      final text = readFile(cert);
      expect(text, contains('BEGIN CERTIFICATE'));
      // A private key in a file named "certificate" is the mistake worth
      // catching here.
      expect(
        text.contains('PRIVATE KEY'),
        isFalse,
        reason:
            'upload-cert: $cert contains a PRIVATE KEY — only the public '
            'certificate belongs in the repository',
      );
    },
  );
}
