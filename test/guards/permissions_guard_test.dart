@Tags(['guard'])
library;

// Guard for #14 and project invariant 1: the release build declares no Android
// permissions at all, INTERNET included, and no manifest strips one at build
// time.
//
// Why removal rules are banned rather than tolerated: a plugin that needs a
// permission is rejected during planning, after its own manifest is read and
// the owner approves (CLAUDE.md, invariant 1). A `tools:node="remove"` would
// let one in and then hide it, which is the failure this guard exists to make
// impossible.
//
// What this does NOT cover: Gradle's merged manifest under build/, which only
// exists after a build. tools/check_aab.sh scans the built bundle for that.
import 'package:flutter_test/flutter_test.dart';

import 'repo_files.dart';

const _mainManifest = 'android/app/src/main/AndroidManifest.xml';
const _releaseManifest = 'android/app/src/release/AndroidManifest.xml';
const _debugManifest = 'android/app/src/debug/AndroidManifest.xml';
const _profileManifest = 'android/app/src/profile/AndroidManifest.xml';

/// `<uses-permission`, `<uses-permission-sdk-23`, `<permission`,
/// `<permission-group`, `<permission-tree` — matched only when the element name
/// is followed by whitespace, `>` or `/`, so `<permission-foo` would not count
/// and `<uses-permissions-note>` cannot false-positive.
final _permissionElement = RegExp(
  r'<\s*(uses-permission-sdk-23|uses-permission|permission-group|permission-tree|permission)(?=[\s>/])',
);

/// The mandated comment, matched whitespace-normalised so it may be wrapped
/// across lines however the file needs.
const _requiredComment =
    'INTERNET is required only for Flutter hot reload and DevTools in '
    'debug/profile builds. It must never appear in src/main or src/release: '
    'invariant 1 (CLAUDE.md). Enforced by '
    'test/guards/permissions_guard_test.dart and tools/check_aab.sh.';

String _normalise(String s) => s.replaceAll(RegExp(r'\s+'), ' ').trim();

List<String> _permissionElementsIn(String path) {
  final body = stripXmlComments(readFile(path));
  return _permissionElement
      .allMatches(body)
      .map((m) => '$path: <${m.group(1)}')
      .toList();
}

void main() {
  test('the main manifest declares no permission of any kind', () {
    final offenders = _permissionElementsIn(_mainManifest);
    expect(
      offenders,
      isEmpty,
      reason: describeOffenders('main-no-permissions', offenders),
    );
  });

  test('the release manifest, if present, declares no permission', () {
    if (!pathExists(_releaseManifest)) {
      // Printed rather than skipped: a skipped test reads as a passing one, and
      // the point is that this file's absence is itself the current state.
      // ignore: avoid_print
      print(
        'release-no-permissions: $_releaseManifest is absent — nothing to '
        'check, which is the intended state (#14).',
      );
      return;
    }
    final offenders = _permissionElementsIn(_releaseManifest);
    expect(
      offenders,
      isEmpty,
      reason: describeOffenders('release-no-permissions', offenders),
    );
  });

  test('no manifest strips a permission at build time', () {
    final offenders = <String>[];
    for (final path in trackedFilesUnder('android/app/src')) {
      if (!path.endsWith('AndroidManifest.xml')) continue;
      final body = stripXmlComments(readFile(path));
      if (RegExp(r'''tools:node\s*=\s*["']remove["']''').hasMatch(body)) {
        offenders.add(
          '$path: tools:node="remove" is forbidden — a plugin '
          'needing a permission is rejected in planning, not stripped here',
        );
      }
    }
    expect(
      offenders,
      isEmpty,
      reason: describeOffenders('no-removal-rules', offenders),
    );
  });

  for (final entry in {
    'debug': _debugManifest,
    'profile': _profileManifest,
  }.entries) {
    test('the ${entry.key} manifest declares exactly INTERNET', () {
      final body = stripXmlComments(readFile(entry.value));
      final elements = _permissionElement.allMatches(body).toList();
      expect(
        elements,
        hasLength(1),
        reason:
            '${entry.key}-exactly-internet ${entry.value}: expected one '
            'permission element, found ${elements.length}',
      );
      expect(
        body,
        matches(
          RegExp(
            r'<\s*uses-permission[^>]*android:name\s*=\s*"android\.permission\.INTERNET"',
          ),
        ),
        reason:
            '${entry.key}-exactly-internet ${entry.value}: the one '
            'permission must be INTERNET',
      );
    });

    test('the ${entry.key} manifest carries the invariant-1 comment', () {
      expect(
        _normalise(readFile(entry.value)),
        contains(_normalise(_requiredComment)),
        reason:
            '${entry.key}-comment ${entry.value}: the mandated comment is '
            'missing or altered',
      );
    });
  }

  test('uses-feature is allowed everywhere', () {
    // A negative control for the element regex: uses-feature must never be
    // mistaken for a permission, or a future hardware declaration would fail
    // this guard for the wrong reason.
    const sample =
        '<uses-feature android:name="android.hardware.touchscreen" '
        'android:required="false"/>';
    expect(
      _permissionElement.hasMatch(sample),
      isFalse,
      reason:
          'uses-feature-allowed: the permission regex matched a '
          '<uses-feature> element',
    );
  });
}
