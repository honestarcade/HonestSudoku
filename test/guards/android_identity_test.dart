@Tags(['guard'])
library;

// Guard for #12: the Android build identifies as Honest Sudoku, locks to
// portrait, and the repository carries only the Android platform.
//
// These are file-reading assertions, not behavioural ones. What they do NOT
// cover: the package id inside a built bundle (#14's scan asserts the package
// string in the bundle manifest), and whether the app actually launches.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'repo_files.dart';

const _appId = 'com.honestarcade.sudoku';
const _oldId = 'com.honestarcade.sudoku.honest_sudoku';
const _removedPlatforms = ['ios', 'macos', 'linux', 'windows', 'web'];

void main() {
  test('applicationId is the final package id', () {
    final gradle = readFile('android/app/build.gradle.kts');
    expect(
      gradle,
      matches(RegExp(r'applicationId\s*=\s*"' + RegExp.escape(_appId) + r'"')),
      reason: 'applicationId android/app/build.gradle.kts: expected $_appId',
    );
  });

  test('namespace is the final package id', () {
    final gradle = readFile('android/app/build.gradle.kts');
    expect(
      gradle,
      matches(RegExp(r'namespace\s*=\s*"' + RegExp.escape(_appId) + r'"')),
      reason: 'namespace android/app/build.gradle.kts: expected $_appId',
    );
  });

  test('the scaffold package id appears nowhere under android/', () {
    final offenders = <String>[];
    for (final path in trackedFilesUnder('android')) {
      // latin1, not utf8: android/ carries PNGs and a jar, and decoding those
      // as utf8 throws. The id is ASCII, so a latin1 decode of any file finds
      // it if it is there, and binary files simply never match.
      final contents = latin1.decode(
        File('${repoRoot.path}/$path').readAsBytesSync(),
      );
      if (contents.contains(_oldId)) {
        offenders.add('$path: contains $_oldId');
      }
    }
    expect(offenders, isEmpty, reason: describeOffenders('old-id', offenders));
  });

  test('MainActivity lives at the final package path', () {
    expect(
      pathExists(
        'android/app/src/main/kotlin/com/honestarcade/sudoku/MainActivity.kt',
      ),
      isTrue,
      reason:
          'main-activity-path: expected '
          'android/app/src/main/kotlin/com/honestarcade/sudoku/MainActivity.kt',
    );
    expect(
      pathExists(
        'android/app/src/main/kotlin/com/honestarcade/sudoku/honest_sudoku',
      ),
      isFalse,
      reason: 'main-activity-path: the old package directory still exists',
    );
  });

  test('MainActivity declares the final package', () {
    final source = readFile(
      'android/app/src/main/kotlin/com/honestarcade/sudoku/MainActivity.kt',
    );
    expect(
      source,
      matches(
        RegExp(
          r'^\s*package\s+' + RegExp.escape(_appId) + r'\s*$',
          multiLine: true,
        ),
      ),
      reason: 'main-activity-package: expected "package $_appId"',
    );
  });

  test('the manifest points at the relative MainActivity', () {
    final manifest = stripXmlComments(
      readFile('android/app/src/main/AndroidManifest.xml'),
    );
    expect(
      manifest,
      contains('android:name=".MainActivity"'),
      reason: 'manifest-activity: expected android:name=".MainActivity"',
    );
  });

  test('the launcher label is the literal app name', () {
    final manifest = stripXmlComments(
      readFile('android/app/src/main/AndroidManifest.xml'),
    );
    expect(
      manifest,
      matches(RegExp(r'android:label\s*=\s*"Honest Sudoku"')),
      reason: 'label: expected android:label="Honest Sudoku"',
    );
  });

  test('the main activity is locked to portrait', () {
    final manifest = stripXmlComments(
      readFile('android/app/src/main/AndroidManifest.xml'),
    );
    expect(
      manifest,
      matches(RegExp(r'android:screenOrientation\s*=\s*"portrait"')),
      reason: 'orientation: expected android:screenOrientation="portrait"',
    );
  });

  test('minSdk is pinned to 24', () {
    final gradle = readFile('android/app/build.gradle.kts');
    expect(
      gradle,
      matches(RegExp(r'minSdk\s*=\s*24\b')),
      reason: 'min-sdk android/app/build.gradle.kts: expected minSdk = 24',
    );
  });

  test('only the Android platform is present', () {
    final offenders = <String>[];
    for (final platform in _removedPlatforms) {
      if (pathExists(platform)) offenders.add('$platform/ still exists');
    }
    final metadata = readFile('.metadata');
    for (final platform in _removedPlatforms) {
      if (RegExp(
        r'platform:\s*' + platform + r'\s*$',
        multiLine: true,
      ).hasMatch(metadata)) {
        offenders.add('.metadata: still lists platform $platform');
      }
    }
    expect(
      offenders,
      isEmpty,
      reason: describeOffenders('android-only', offenders),
    );
  });

  test('no config file names a removed platform', () {
    final offenders = <String>[];
    for (final path in ['pubspec.yaml', 'analysis_options.yaml']) {
      final lines = stripYamlComments(readFile(path)).split('\n');
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        for (final platform in _removedPlatforms) {
          if (RegExp(r'\b' + platform + r'\b').hasMatch(line)) {
            offenders.add('$path:${i + 1}: ${line.trim()}');
          }
        }
      }
    }
    expect(
      offenders,
      isEmpty,
      reason: describeOffenders('no-platform-refs', offenders),
    );
  });

  test('main.dart locks the orientation before runApp', () {
    final source = readFile('lib/main.dart');
    expect(
      source,
      matches(
        RegExp(
          r'setPreferredOrientations\s*\(\s*\[\s*DeviceOrientation\.portraitUp\s*,?\s*\]\s*\)',
        ),
      ),
      reason:
          'dart-orientation lib/main.dart: expected '
          'SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp])',
    );
  });
}
