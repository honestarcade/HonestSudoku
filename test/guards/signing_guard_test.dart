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
// enrolled. M7's enrolment uses the committed public certificate for that.
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

void main() {
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
