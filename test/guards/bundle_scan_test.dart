@Tags(['guard'])
library;

// Permanent fixtures for tools/check_aab.sh, the bundle scanner that enforces
// project invariant 1 (CLAUDE.md) on the artefact that actually ships.
//
// Why these exist (#80): the scanner had only ever been run against real
// bundles, and a real bundle is clean, so every run agreed with every other run
// and nobody learned anything. A scanner is only worth its exit code if a dirty
// bundle makes it fail, and no dirty bundle existed to try. Two separate bugs
// lived in that blind spot — first a check that matched `uses-permission` as a
// whole run and so never fired at all, then a replacement that matched every
// dotted name in the file and failed the real build. Both would have died here
// in a second.
//
// How the fixtures are built: the bundle manifest is protobuf, and the scanner
// reads it as printable byte runs, so these fixtures reproduce the run layout
// the scanner depends on — element name with the next field's tag packed onto
// it, the android namespace, the attribute name, then a length byte followed by
// the value. That is a model of the encoding, not a real aapt2 output, so the
// last test in this file pins the model to the genuine article: when a release
// bundle exists on disk, its own manifest must have that same shape and must
// scan clean.
//
// What this does NOT cover: anything about the bundle other than its base
// manifest — no dex scan, no resource scan. It also cannot prove a real aapt2
// would encode an unusual manifest the way these fixtures do; the pinning test
// is the only thing tying the two together.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'repo_files.dart';

const _package = 'com.honestarcade.sudoku';
const _selfPermission = '$_package.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION';
const _namespace = '*http://schemas.android.com/apk/res/android';

/// Builds the printable-run layout of a bundle manifest.
///
/// Runs are separated by a non-printable byte, exactly as the real encoding's
/// field tags separate them; `tr -c '[:print:]' '\n'` turns each into a line.
class _Manifest {
  final _bytes = <int>[];

  void _gap() => _bytes.add(0x12);

  void _raw(String s) => _bytes.addAll(latin1.encode(s));

  /// An element name with the following field's tag packed straight onto it —
  /// the encoding fact that made the first version of this check inert.
  void element(String name, {String packed = '"y'}) {
    _gap();
    _raw('$name$packed');
  }

  /// One `android:<name>="<value>"` attribute, length-prefixed like the real
  /// thing. A value under 32 characters gets a non-printable length byte and so
  /// starts its own run; a longer one shares the run with its length byte. Both
  /// shapes occur in a real manifest and both are exercised here.
  void attribute(String name, String value) {
    _gap();
    _raw(_namespace);
    _gap();
    _raw(name);
    _gap();
    _bytes.add(value.length);
    _raw('$value(');
  }

  void packageId(String id) {
    element('manifest', packed: '""');
    _gap();
    _raw('package');
    _gap();
    _raw('$id"K');
  }

  List<int> get bytes => List<int>.unmodifiable(_bytes);
}

/// A manifest shaped like a real Flutter release build's: the launcher intent,
/// framework class names, the profileinstaller receiver's DUMP *restriction*
/// and the androidx.core self-permission. Every one of these is a dotted name
/// that is not a requested permission, which is what the second attempt at the
/// scan could not tell apart.
_Manifest _realisticBase() {
  final m = _Manifest()..packageId(_package);
  m
    ..element('uses-sdk')
    ..attribute('minSdkVersion', '24')
    ..element('action')
    ..attribute('name', 'android.intent.action.PROCESS_TEXT')
    ..element('permission')
    ..attribute('name', _selfPermission)
    ..attribute('protectionLevel', 'signature')
    ..element('uses-permission')
    ..attribute('name', _selfPermission)
    ..element('application')
    ..attribute('appComponentFactory', 'androidx.core.app.CoreComponentFactory')
    ..element('activity')
    ..attribute('name', '$_package.MainActivity')
    ..element('action')
    ..attribute('name', 'android.intent.action.MAIN')
    ..element('category')
    ..attribute('name', 'android.intent.category.LAUNCHER')
    ..element('receiver')
    ..attribute('name', 'androidx.profileinstaller.ProfileInstallReceiver')
    // The restriction, not a request: this receiver refuses callers who lack
    // DUMP. It is a lock, not a key, and it is in every Flutter release build.
    ..attribute('permission', 'android.permission.DUMP')
    ..element('action')
    ..attribute('name', 'androidx.profileinstaller.action.INSTALL_PROFILE');
  return m;
}

/// Writes `bytes` as `base/manifest/AndroidManifest.xml` inside a new .aab.
String _bundle(Directory dir, String name, List<int> bytes) {
  final staging = Directory('${dir.path}/$name-src/base/manifest')
    ..createSync(recursive: true);
  File('${staging.path}/AndroidManifest.xml').writeAsBytesSync(bytes);
  final aab = '${dir.path}/$name.aab';
  final result = Process.runSync('zip', [
    '-qr',
    aab,
    'base',
  ], workingDirectory: '${dir.path}/$name-src');
  if (result.exitCode != 0) {
    throw StateError('zip failed (${result.exitCode}): ${result.stderr}');
  }
  return aab;
}

class _Scan {
  const _Scan(this.exitCode, this.stdout, this.stderr);
  final int exitCode;
  final String stdout;
  final String stderr;
  String get output => '$stdout$stderr';
}

_Scan _scan(String path) {
  final result = Process.runSync('tools/check_aab.sh', [
    path,
  ], workingDirectory: repoRoot.path);
  return _Scan(
    result.exitCode,
    result.stdout.toString(),
    result.stderr.toString(),
  );
}

void main() {
  late Directory tmp;

  setUpAll(() {
    tmp = Directory.systemTemp.createTempSync('hs-bundle-scan');
    // No graceful degradation: a fixture suite that quietly stops building
    // fixtures is the blind spot this file was written to close.
    final zip = Process.runSync('zip', ['-v']);
    if (zip.exitCode != 0) {
      throw StateError('the `zip` command is required to build these fixtures');
    }
  });

  tearDownAll(() => tmp.deleteSync(recursive: true));

  test('a realistic clean bundle scans clean', () {
    final scan = _scan(_bundle(tmp, 'clean', _realisticBase().bytes));
    expect(
      scan.exitCode,
      0,
      reason:
          'clean-bundle: a bundle carrying only the launcher intent, the DUMP '
          'restriction and the androidx.core self-permission must pass.\n'
          '${scan.output}',
    );
    expect(scan.stdout, contains('no permissions declared'));
  });

  test('both allowlisted entries are announced, never silently swallowed', () {
    final scan = _scan(_bundle(tmp, 'announce', _realisticBase().bytes));
    expect(
      scan.stderr,
      contains('android.permission.DUMP'),
      reason:
          'announce-allowlist: the DUMP restriction is allowlisted, so every '
          'clean run must say so out loud.\n${scan.output}',
    );
    expect(
      scan.stderr,
      contains(_selfPermission),
      reason:
          'announce-allowlist: the self-permission is allowlisted, so every '
          'clean run must say so out loud.\n${scan.output}',
    );
  });

  // The #80 regression. Watched fail against the pre-fix script, which exited
  // 0 on exactly this bundle.
  test('a custom permission request is caught', () {
    final m = _realisticBase()
      ..element('uses-permission')
      ..attribute('name', 'com.evilads.sdk.TRACK_USER');
    final scan = _scan(_bundle(tmp, 'custom-perm', m.bytes));
    expect(
      scan.exitCode,
      1,
      reason:
          'custom-permission: a bundle requesting com.evilads.sdk.TRACK_USER '
          'must fail. This exited 0 before #80 was fixed.\n${scan.output}',
    );
    expect(scan.stderr, contains('com.evilads.sdk.TRACK_USER'));
  });

  test('an android.permission request is caught', () {
    final m = _realisticBase()
      ..element('uses-permission')
      ..attribute('name', 'android.permission.INTERNET');
    final scan = _scan(_bundle(tmp, 'internet', m.bytes));
    expect(
      scan.exitCode,
      1,
      reason:
          'internet-permission: INTERNET is the permission invariant 1 exists '
          'to keep out.\n${scan.output}',
    );
    expect(scan.stderr, contains('android.permission.INTERNET'));
  });

  test('uses-permission-sdk-23 is caught too', () {
    final m = _realisticBase()
      ..element('uses-permission-sdk-23')
      ..attribute('name', 'com.evilads.sdk.TRACK_USER');
    final scan = _scan(_bundle(tmp, 'sdk23', m.bytes));
    expect(
      scan.exitCode,
      1,
      reason:
          'sdk23-permission: the -sdk-23 spelling requests a permission just '
          'the same.\n${scan.output}',
    );
  });

  test('a restriction is not mistaken for a request', () {
    // The complement of the INTERNET test: the same permission name, in the
    // position that grants the app nothing. A scanner that fails this has
    // stopped reading structure and gone back to grepping for names — which is
    // the bug that failed the real build.
    final m = _realisticBase()
      ..element('receiver')
      ..attribute('name', '$_package.SomeReceiver')
      ..attribute('permission', 'android.permission.DUMP');
    final scan = _scan(_bundle(tmp, 'restriction', m.bytes));
    expect(
      scan.exitCode,
      0,
      reason:
          'restriction-not-request: android:permission on a component is a '
          'lock, not a key.\n${scan.output}',
    );
  });

  test('a permission whose name cannot be read still fails', () {
    // Fail closed. A request nobody can name is still a request, and an
    // encoding this decoder has not seen must never read as "clean".
    final m = _Manifest()..packageId(_package);
    m._gap();
    m._raw('uses-permission"y');
    final scan = _scan(_bundle(tmp, 'undecodable', m.bytes));
    expect(
      scan.exitCode,
      1,
      reason:
          'fail-closed: a uses-permission element with no readable name must '
          'not pass.\n${scan.output}',
    );
    expect(scan.stderr, contains('unreadable name'));
  });

  // #87. The scan decoded requests correctly and ignored declarations
  // entirely, so a library `<permission>` — which is exactly how the
  // androidx.core one arrives — scanned clean. The repository's own manifest
  // guard bans all five permission elements; the bundle scan is the only place
  // a merged manifest can be seen, so it has to ban them too.
  for (final element in const [
    'permission',
    'permission-group',
    'permission-tree',
  ]) {
    test('a <$element> declaration is caught', () {
      final m = _realisticBase()
        ..element(element)
        ..attribute('name', 'com.evil.NEW_CUSTOM_PERMISSION')
        ..attribute('protectionLevel', 'dangerous');
      final scan = _scan(_bundle(tmp, 'declare-$element', m.bytes));
      expect(
        scan.exitCode,
        1,
        reason:
            'declare-$element: declaring a permission is not requesting one, '
            'but invariant 1 says the release build declares none.\n'
            '${scan.output}',
      );
      expect(scan.stderr, contains('com.evil.NEW_CUSTOM_PERMISSION'));
      expect(scan.stderr, contains('declared'));
    });
  }

  test('the allowlisted declaration is refused at the wrong level', () {
    // The allowlist is for a signature-level permission only its own signer
    // can hold. At any other protection level it is a permission other apps
    // can actually be granted — a different thing wearing the same name.
    final m = _Manifest()..packageId(_package);
    m
      ..element('permission')
      ..attribute('name', _selfPermission)
      ..attribute('protectionLevel', 'dangerous');
    final scan = _scan(_bundle(tmp, 'wrong-level', m.bytes));
    expect(
      scan.exitCode,
      1,
      reason:
          'allowlist-level: the name alone must not buy a pass.\n${scan.output}',
    );
    expect(scan.stderr, contains('not signature'));
  });

  test('a declaration with no readable name still fails', () {
    final m = _Manifest()..packageId(_package);
    m
      ..element('permission')
      ..attribute('protectionLevel', 'dangerous');
    final scan = _scan(_bundle(tmp, 'declare-undecodable', m.bytes));
    expect(
      scan.exitCode,
      1,
      reason:
          'declare-fail-closed: a permission nobody can name is still a '
          'permission.\n${scan.output}',
    );
  });

  test('a wrong package id fails with its own exit code', () {
    final m = _Manifest()..packageId('com.honestarcade.sudoku.honest_sudoku');
    final scan = _scan(_bundle(tmp, 'wrong-package', m.bytes));
    expect(
      scan.exitCode,
      2,
      reason:
          'wrong-package: the scaffold id is a longer token and must not '
          'satisfy the package check.\n${scan.output}',
    );
    expect(scan.stderr, contains('PACKAGE MISSING'));
  });

  test('a bundle with no manifest entry fails rather than reading clean', () {
    final dir = Directory('${tmp.path}/empty-src/base/other')
      ..createSync(recursive: true);
    File('${dir.path}/placeholder').writeAsStringSync('nothing here\n');
    final aab = '${tmp.path}/empty.aab';
    Process.runSync('zip', [
      '-qr',
      aab,
      'base',
    ], workingDirectory: '${tmp.path}/empty-src');
    final scan = _scan(aab);
    expect(
      scan.exitCode,
      3,
      reason:
          'no-manifest: `unzip -p` prints nothing and exits 0 for a missing '
          'entry, which would otherwise read as "no permissions".\n'
          '${scan.output}',
    );
  });

  test('a file that is not a bundle is refused', () {
    final notAab = File('${tmp.path}/app.apk')..writeAsStringSync('nope\n');
    expect(_scan(notAab.path).exitCode, 3);
    expect(_scan('${tmp.path}/does-not-exist.aab').exitCode, 3);
  });

  test('repeated scans of one bundle agree', () {
    // The other half of #80's sibling bug: `grep -q` closed the pipe under
    // `unzip`, which died of SIGPIPE, which `set -o pipefail` turned into the
    // pipeline's status — so identical runs disagreed at random.
    final aab = _bundle(tmp, 'determinism', _realisticBase().bytes);
    final codes = List.generate(8, (_) => _scan(aab).exitCode);
    expect(codes.toSet(), {
      0,
    }, reason: 'determinism: eight scans of one bundle returned $codes');
  });

  test('the real release bundle matches the modelled shape', () {
    // This is the only thing tying the twelve fixtures above to reality. They
    // model the protobuf encoding rather than being real aapt2 output, so if
    // aapt2 ever changes how it encodes a manifest they all keep passing while
    // testing a fiction.
    //
    // It used to run only when a bundle happened to be on disk, and print a
    // notice otherwise. tools/gate.sh runs the tests at step 4 and builds the
    // bundle at step 5, so on every clean checkout — every CI run, every fresh
    // clone — it printed and asserted nothing while counting as a passing test
    // (#92). The comment that said "tools/gate.sh builds the bundle before
    // scanning it" was true of the scan and false of this test, and that is
    // how the gap survived review.
    //
    // So it builds what it needs. Only when the bundle is absent, so a local
    // re-run stays fast.
    const built = 'build/app/outputs/bundle/release/app-release.aab';
    if (!pathExists(built)) {
      // ignore: avoid_print
      print('real-bundle-shape: no bundle on disk — building one.');
      late ProcessResult build;
      try {
        build = Process.runSync(
          'flutter',
          ['build', 'appbundle', '--release', '--no-pub'],
          workingDirectory: repoRoot.path,
          stdoutEncoding: utf8,
          stderrEncoding: utf8,
        );
      } on ProcessException catch (e) {
        // The one honest reason to skip: no toolchain to build with. Printed
        // rather than skipped, because a skipped test reads as a passing one —
        // and the message now says the build failed, not that a file was
        // missing, which is the difference that makes the gap visible.
        // ignore: avoid_print
        print(
          'real-bundle-shape: cannot build — `flutter` is not on PATH ($e). '
          'This check needs the Android toolchain.',
        );
        return;
      }
      if (!pathExists(built)) {
        // ignore: avoid_print
        print(
          'real-bundle-shape: the release build did not produce a bundle, so '
          'the fixtures could not be checked against a real one.\n'
          '${build.stdout}${build.stderr}',
        );
        return;
      }
    }

    final scan = _scan(built);
    expect(
      scan.exitCode,
      0,
      reason:
          'real-bundle-shape: the real release bundle must scan clean.\n'
          '${scan.output}',
    );

    // And the shape the fixtures model is the shape it really has: every
    // uses-permission run is followed, within a dozen runs, by a run that is
    // exactly `name`. If aapt2 ever stops encoding it this way, these fixtures
    // stop standing in for reality and this test says so.
    final dump = Process.runSync('sh', [
      '-c',
      "unzip -p '$built' base/manifest/AndroidManifest.xml "
          "| LC_ALL=C tr -c '[:print:]' '\\n'",
    ], workingDirectory: repoRoot.path);
    final runs = const LineSplitter().convert(dump.stdout.toString());
    final starts = <int>[];
    for (var i = 0; i < runs.length; i++) {
      if (RegExp(r'^uses-permission(-sdk-23)?([^A-Za-z0-9_-]|$)')
          .hasMatch(runs[i])) {
        starts.add(i);
      }
    }
    expect(
      starts,
      isNotEmpty,
      reason:
          'real-bundle-shape: no uses-permission run found at all. Either the '
          'encoding changed or the run-start match is inert again (#80).\n'
          'Every Flutter build carries the androidx.core self-permission.',
    );
    for (final start in starts) {
      final window = runs
          .skip(start + 1)
          .where((r) => r.isNotEmpty)
          .take(12)
          .toList();
      expect(
        window,
        contains('name'),
        reason:
            'real-bundle-shape: the uses-permission run at index $start is not '
            'followed by a `name` attribute run within 12 runs, so the '
            'fixtures in this file no longer model the real encoding.\n'
            'Runs seen: $window',
      );
    }
  });
}
