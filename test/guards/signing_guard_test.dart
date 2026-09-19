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

/// A file that exists, standing in for a keystore.
///
/// It has to exist: since #91 the gate refuses to promise the upload key for a
/// keystore it cannot read, so a fixture pointing at a path that is not there
/// would exercise that branch instead of the one it means to.
final File _fakeKeystore = File(
  '${Directory.systemTemp.createTempSync('hs-signing').path}/upload.p12',
)..writeAsStringSync('not a real keystore');

Map<String, String> get _allFour => {
  'HS_KEYSTORE_PATH': _fakeKeystore.path,
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

  // #91. The two ways the headline could still be false. The first is the one
  // that mattered: it was the only case found where a PASSING gate mislabelled
  // the artefact it named.

  test('a whitespace value counts as missing, matching isNullOrBlank', () {
    // build.gradle.kts decides with Kotlin's isNullOrBlank(), which treats
    // whitespace as unset. The gate used to decide with [ -n "$var" ], which
    // does not. With all four set to a single space the gate announced the
    // upload key, Gradle took the debug fallback, the build SUCCEEDED, and
    // GATE PASSED was printed over a bundle signed `CN=Android Debug`.
    final allBlank = {for (final v in _signingVars) v: ' '};
    expect(
      _signingMode(allBlank),
      contains('debug fallback'),
      reason:
          'blank-all: whitespace must read exactly as Gradle reads it — as '
          'unset, so the headline matches the debug fallback the build takes',
    );
    expect(_signingMode(allBlank), isNot(contains('upload key')));

    for (final blank in _signingVars) {
      final env = Map<String, String>.from(_allFour)..[blank] = '   ';
      final mode = _signingMode(env);
      expect(
        mode,
        contains('partial'),
        reason:
            'blank-$blank: one whitespace variable is a partial set, which '
            'Gradle refuses.\nGot: $mode',
      );
      expect(mode, contains(blank));
    }
  });

  test('an unreadable keystore is not announced as the upload key', () {
    // The lesser half of the same defect: a promise made without checking.
    // This one fails safe — Gradle dies at validateSigningRelease — but the
    // headline was still false.
    final env = Map<String, String>.from(_allFour)
      ..[_keystorePath] = '/tmp/hs-definitely-not-here.p12';
    final mode = _signingMode(env);
    expect(
      mode,
      contains('not readable'),
      reason:
          'unreadable-keystore: the gate must not promise a key it cannot '
          'find.\nGot: $mode',
    );
    expect(mode, isNot(contains('signing with the upload key')));
  });

  test('the key script refuses when either output already exists', () {
    // #93. Driven with a fake HOME, so the real secrets directory is never
    // read, written or even resolved. The credentials file is the only copy
    // of the password until the owner moves it to a password manager, and the
    // key it unlocks cannot be regenerated once Play has enrolled it — so
    // overwriting it is the one irreversible thing this script can do. It used
    // to refuse on the keystore alone.
    final home = Directory.systemTemp.createTempSync('hs-keyscript');
    final secrets = Directory('${home.path}/HonestArcadeApps/secrets')
      ..createSync(recursive: true);
    final keystore = File('${secrets.path}/sudoku-upload.keystore');
    final credentials = File('${secrets.path}/sudoku-signing-credentials.txt');

    ProcessResult run() => Process.runSync(
      'tools/make_upload_key.sh',
      const [],
      workingDirectory: repoRoot.path,
      includeParentEnvironment: false,
      environment: {
        'PATH': Platform.environment['PATH'] ?? '/usr/bin:/bin',
        'HOME': home.path,
        // Set, so the refusal is what stops the run rather than a missing
        // password. Never a real one: this script must not reach keytool.
        'HS_KEYSTORE_PASS': 'not-used-because-it-refuses',
      },
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
    );

    try {
      keystore.writeAsStringSync('pretend keystore');
      var result = run();
      expect(
        result.exitCode,
        2,
        reason:
            'key-refusal: an existing keystore must stop the run.\n'
            '${result.stderr}',
      );
      expect(result.stderr, contains('refusing to overwrite'));

      keystore.deleteSync();
      credentials.writeAsStringSync('THE PASSWORD OF A LIVE KEY\n');
      result = run();
      expect(
        result.exitCode,
        2,
        reason:
            'key-refusal: an existing credentials file must stop the run too. '
            'With the keystore moved aside this used to overwrite the only '
            'record of a live key\'s password and exit 0.\n${result.stderr}',
      );
      expect(result.stderr, contains('sudoku-signing-credentials.txt'));
      expect(
        credentials.readAsStringSync(),
        'THE PASSWORD OF A LIVE KEY\n',
        reason:
            'key-refusal: the credentials file was modified by a run that '
            'was supposed to refuse',
      );
    } finally {
      home.deleteSync(recursive: true);
    }
  });

  // #106. #91 fixed ASCII whitespace by stripping POSIX [:space:]. Kotlin's
  // Character.isWhitespace also counts 0x1C-0x1F — single ASCII bytes a
  // mangled paste really produces — and several multi-byte characters. With
  // four 0x1C values the gate announced one thing, the build did another, and
  // the gate PASSED over a debug-signed bundle.
  //
  // Parameterised over the difference set, not over one more example: a
  // fixture that checks one space and one empty string is what let this
  // survive twice.
  test('every ASCII character Java calls whitespace counts as missing', () {
    const javaAsciiWhitespace = {
      '\u0009': 'tab',
      '\u000A': 'line feed',
      '\u000B': 'vertical tab',
      '\u000C': 'form feed',
      '\u000D': 'carriage return',
      '\u001C': 'file separator',
      '\u001D': 'group separator',
      '\u001E': 'record separator',
      '\u001F': 'unit separator',
      '\u0020': 'space',
    };
    javaAsciiWhitespace.forEach((char, name) {
      final all = {for (final v in _signingVars) v: char};
      expect(
        _signingMode(all),
        contains('debug fallback'),
        reason:
            'blank-$name: Gradle treats this as unset, so the gate must too, '
            'or the headline contradicts the build (#106)',
      );

      final one = Map<String, String>.from(_allFour)..[_keystorePath] = char;
      expect(
        _signingMode(one),
        contains('partial'),
        reason: 'blank-$name: one blank variable is a partial set',
      );
    });
  });

  test('a non-breaking space counts as SET, because Java says so', () {
    // The control, and the reason the fix is an explicit list rather than
    // "strip anything unprintable". Character.isWhitespace is FALSE for
    // U+00A0, U+2007 and U+202F, so classifying them as blank would be a new
    // disagreement in the other direction.
    final env = {for (final v in _signingVars) v: '\u00A0'};
    expect(
      _signingMode(env),
      isNot(contains('debug fallback')),
      reason:
          'nbsp: Java does not call U+00A0 whitespace, so neither may the gate',
    );
  });

  test('the gate cross-checks its prediction against what Gradle did', () {
    // The part that cannot drift. `signing_mode` is a prediction; the build is
    // the fact. They have disagreed twice (#91, #106), each time with the gate
    // announcing the upload key over a debug-signed bundle. A disagreement is
    // now a gate failure, which is what makes the residual multi-byte gap in
    // `hs_is_blank` harmless rather than merely unlikely.
    final gate = readFile('tools/gate.sh');
    expect(
      gate,
      contains('signed with the UPLOAD key'),
      reason:
          'cross-check: the gate no longer reads back which key Gradle used',
    );
    expect(gate, contains('signed with the DEBUG key'));
    expect(
      gate,
      contains(r'GATE FAILED at $label: the header said'),
      reason:
          'cross-check: a disagreement between the header and the build must '
          'fail the gate, not be printed and ignored',
    );

    // And the build file must say which key it used in BOTH branches, or the
    // cross-check has nothing to read.
    final gradle = readFile(_gradle);
    expect(
      gradle,
      contains('signed with the UPLOAD key'),
      reason:
          'cross-check: build.gradle.kts announces the debug fallback but not '
          'the upload key, so the gate cannot tell the two apart',
    );
    expect(gradle, contains('signed with the DEBUG key'));
  });

  test('the gate dispatches through a function, not eval', () {
    // #17's acceptance criterion says the parallel arrays are "run by one
    // function", and its discretion says "(no `eval`)". The file had a
    // top-level loop calling eval. No exploit today, since COMMANDS holds
    // literals — it matters because M1's CI is meant to consume this and
    // there was no function for it to call (#108).
    final gate = readFile('tools/gate.sh');
    expect(gate, contains('run_step() {'));
    expect(
      gate,
      isNot(contains(r'eval "$command"')),
      reason: 'no-eval: the dispatcher is still eval',
    );
  });

  test('the upload certificate can be checked against a bundle', () {
    // #13's discretion specified this "so M1 can reuse it" and it was never
    // written (#108). It is the only check that catches a release signed with
    // the wrong key before Play rejects it.
    const script = 'tools/verify_upload_cert.sh';
    expect(pathExists(script), isTrue, reason: 'verify-cert: $script missing');

    ProcessResult run(List<String> args, [Map<String, String>? extra]) =>
        Process.runSync(
          script,
          args,
          workingDirectory: repoRoot.path,
          includeParentEnvironment: false,
          environment: {
            'PATH': Platform.environment['PATH'] ?? '/usr/bin:/bin',
            'HOME': Platform.environment['HOME'] ?? '',
            ...?extra,
          },
          stdoutEncoding: utf8,
          stderrEncoding: utf8,
        );

    final missing = run(['/tmp/hs-definitely-not-a-bundle.aab']);
    expect(
      missing.exitCode,
      2,
      reason:
          'verify-cert: a missing input must be its own exit code, not a '
          'mismatch.\n${missing.stderr}',
    );

    // The macOS /usr/bin/keytool is a stub: it exists, it is executable, and
    // it cannot run. Mistaking it for a working keytool is the trap the
    // toolchain memory documents for `java`.
    final stub = run(const [], {'HS_KEYTOOL': '/usr/bin/keytool'});
    if (stub.stderr.toString().contains('macOS stub')) {
      expect(
        stub.exitCode,
        3,
        reason: 'verify-cert: the stub must be reported, not used',
      );
    } else {
      // ignore: avoid_print
      print(
        'verify-cert: /usr/bin/keytool is not the stub on this machine, so '
        'that branch was not exercised.',
      );
    }
  });

  test('the credentials file quotes its values', () {
    // It documents itself as sourceable. An unquoted value containing a space
    // breaks `. this-file`, and one containing a shell metacharacter executes
    // on it (#108).
    final script = readFile('tools/make_upload_key.sh');
    for (final name in _signingVars) {
      expect(
        script,
        contains('export $name="'),
        reason: 'credentials-quoting: $name is written unquoted',
      );
    }
  });

  test('the gate pins its locale', () {
    // Without this the multi-byte whitespace rules behave differently in a
    // UTF-8 shell and in the C locale a bare CI runner has, so a CI failure
    // could not be reproduced by hand (#106).
    expect(readFile('tools/gate.sh'), contains('export LC_ALL=C'));
  });

  test('the stale bundle is cleared before the first step, not the fifth', () {
    // #108. The removal sat at step 5, by which time step 4 had already read
    // whatever was at that path.
    final gate = readFile('tools/gate.sh');
    final removal = gate.indexOf(r'rm -f "$BUNDLE"');
    final loop = gate.indexOf(r'while [ "$i" -lt "$total" ]');
    expect(removal, greaterThan(-1));
    expect(
      removal,
      lessThan(loop),
      reason:
          'stale-bundle: the removal must precede the loop, so the path holds '
          "this run's artefact for every step and not just the last two",
    );
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

const _bundle = 'build/app/outputs/bundle/release/app-release.aab';

/// Output that means the Android toolchain is not usable here, rather than
/// that the build was refused for the reason under test.
const _toolchainAbsent = [
  'No Android SDK found',
  'Unable to locate a Java Runtime',
  'Android sdkmanager not found',
  'No valid Android SDK platforms found',
];

/// Runs a release build under exactly `env` and returns what came out, after
/// recording whether the bundle on disk survived untouched.
///
/// Returns null when the Android toolchain is not usable here, having said so
/// out loud. Printed rather than skipped: a skipped test reads as a passing
/// one, and the whole point of this check is that it cannot be satisfied by
/// absence.
_BuildOutcome? _releaseBuild(Map<String, String> env) {
  final file = File('${repoRoot.path}/$_bundle');
  final existedBefore = file.existsSync();
  final sizeBefore = existedBefore ? file.lengthSync() : -1;
  final modifiedBefore = existedBefore ? file.lastModifiedSync() : null;

  late ProcessResult result;
  try {
    result = Process.runSync(
      'flutter',
      ['build', 'appbundle', '--release', '--no-pub'],
      workingDirectory: repoRoot.path,
      includeParentEnvironment: false,
      environment: {
        'PATH': Platform.environment['PATH'] ?? '/usr/bin:/bin',
        'HOME': Platform.environment['HOME'] ?? '',
        ...env,
      },
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
    );
  } on ProcessException catch (e) {
    // ignore: avoid_print
    print(
      'hard-fail: `flutter` is not on PATH ($e) — this check needs the '
      'Android toolchain. tools/gate.sh runs where it is present.',
    );
    return null;
  }

  final output = '${result.stdout}${result.stderr}';
  for (final marker in _toolchainAbsent) {
    if (output.contains(marker)) {
      // ignore: avoid_print
      print(
        'hard-fail: the Android toolchain is unusable here ("$marker"), so '
        'the refusal under test could not be reached.',
      );
      return null;
    }
  }

  final after = File('${repoRoot.path}/$_bundle');
  final bundleUntouched = existedBefore
      ? after.existsSync() &&
            after.lengthSync() == sizeBefore &&
            after.lastModifiedSync() == modifiedBefore
      : !after.existsSync();

  return _BuildOutcome(result.exitCode, output, bundleUntouched);
}

class _BuildOutcome {
  const _BuildOutcome(this.exitCode, this.output, this.bundleUntouched);
  final int exitCode;
  final String output;

  /// The bundle is the file it was before — or is still absent, if it was.
  final bool bundleUntouched;
}

void _hardFailTests() {
  // The complement #13 only ever proved by hand. The acceptance criterion is
  // not "the build fails" — it is that nothing shippable comes out of it. A
  // change making the GradleException non-fatal would ship a debug-signed
  // release, and every other assertion in this file would stay green (#83).
  //
  // Two cases, because build.gradle.kts has two separate refusals and the
  // first draft of this test could not tell them apart: it unset one of four
  // variables, which trips the PARTIAL check, so the HS_RELEASE check was
  // never reached and the test passed against a build file with that check
  // deleted. Each case below leaves exactly one refusal able to fire.
  //
  // Both cost about two seconds: the exceptions are raised at Gradle
  // CONFIGURATION time, so nothing compiles.

  test('HS_RELEASE=1 with no secrets at all produces no bundle', () {
    // Only `hsReleaseRequested && !hsSigningComplete` can refuse this one.
    final outcome = _releaseBuild(const {'HS_RELEASE': '1'});
    if (outcome == null) return;
    expect(
      outcome.exitCode,
      isNot(0),
      reason:
          'hard-fail-release: HS_RELEASE=1 with nothing set must fail the '
          'build rather than fall back to the debug key.\n${outcome.output}',
    );
    expect(
      outcome.output,
      contains('HS_KEYSTORE_PATH is not set'),
      reason:
          'hard-fail-release: it must fail for THIS reason, naming the first '
          'missing variable.\n${outcome.output}',
    );
    expect(
      outcome.bundleUntouched,
      isTrue,
      reason:
          'hard-fail-release: a refused build produced or replaced the '
          'bundle. That bundle would be signed with the debug key.',
    );
  }, timeout: const Timeout(Duration(minutes: 10)));

  test('a partly set environment produces no bundle either', () {
    // Only `hsPresent.isNotEmpty() && !hsSigningComplete` can refuse this one:
    // HS_RELEASE is absent, so without that check the build would fall back to
    // the debug key and succeed.
    final env = Map<String, String>.from(_allFour)..remove('HS_KEY_PASS');
    final outcome = _releaseBuild(env);
    if (outcome == null) return;
    expect(
      outcome.exitCode,
      isNot(0),
      reason:
          'hard-fail-partial: a partly set environment must fail the build in '
          'every mode, not fall back.\n${outcome.output}',
    );
    expect(
      outcome.output,
      contains('HS_KEY_PASS is not set'),
      reason:
          'hard-fail-partial: it must name the variable that is missing.\n'
          '${outcome.output}',
    );
    expect(
      outcome.bundleUntouched,
      isTrue,
      reason:
          'hard-fail-partial: a refused build produced or replaced the bundle.',
    );
  }, timeout: const Timeout(Duration(minutes: 10)));

  test('the release build type has no unconditional debug signing', () {
    // The static half of the same claim, and the one that survives a machine
    // with no toolchain: the debug key is reachable only through the fallback
    // branch, never as the release default.
    final gradle = readFile(_gradle);
    expect(
      gradle,
      contains('hsReleaseRequested && !hsSigningComplete'),
      reason:
          'hard-fail-static: the check that turns HS_RELEASE=1 with a missing '
          'secret into a GradleException is gone from $_gradle',
    );
    expect(
      gradle,
      contains('throw GradleException'),
      reason:
          'hard-fail-static: nothing in $_gradle throws any more, so a '
          'missing secret can no longer be a hard failure',
    );
  });
}

void main() {
  group('gate.sh signing mode', _signingModeTests);
  group('hard failure produces nothing', _hardFailTests);

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
