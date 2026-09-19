@Tags(['guard'])
library;

// Guard for #16: the published privacy policy must keep saying the same thing
// as the build it describes.
//
// The package id appears in three places — the Gradle build, the project
// config, and the policy a player reads. They can drift independently and
// nothing else would notice, and the one that matters is the policy: a wrong
// id there is a public document describing a different app.
//
// What this does NOT cover: whether the policy is legally sufficient, and
// whether the page is actually live. The live check is the post-merge curl
// recorded on #16 and re-checked by /n8-verify.
import 'package:flutter_test/flutter_test.dart';

import 'repo_files.dart';

/// Strips Kotlin `//` line comments so a commented-out `applicationId` cannot
/// be counted. Kept local rather than in repo_files.dart: this is the only
/// guard that reads Kotlin, and #12's identity guard deliberately matches raw
/// text there.
String _stripKotlinLineComments(String source) => source
    .split('\n')
    .map((line) {
      final at = line.indexOf('//');
      return at == -1 ? line : line.substring(0, at);
    })
    .join('\n');

void main() {
  late String applicationId;

  setUpAll(() {
    final gradle = _stripKotlinLineComments(
      readFile('android/app/build.gradle.kts'),
    );
    final found = RegExp(r'applicationId\s*=\s*"([^"]+)"')
        .allMatches(gradle)
        .map((m) => m.group(1)!)
        .toList();
    if (found.length != 1) {
      fail(
        'application-id android/app/build.gradle.kts: expected exactly one '
        'applicationId, found ${found.length} — the policy quotes this value '
        'and cannot be checked against an ambiguous build',
      );
    }
    applicationId = found.single;
  });

  test('the config records the same application id as the build', () {
    final config = stripYamlComments(readFile('.n8/config.yml'));
    final match = RegExp(
      r'^\s+application_id:\s*(\S+)\s*$',
      multiLine: true,
    ).firstMatch(config);
    if (match == null) {
      fail('application-id .n8/config.yml: no application_id under android:');
    }
    expect(
      match.group(1),
      applicationId,
      reason:
          'application-id .n8/config.yml: config and build.gradle.kts '
          'disagree about the package id',
    );
  });

  test('the privacy policy quotes the built application id', () {
    final policy = readFile('docs/privacy.md');
    expect(
      policy,
      contains('`$applicationId`'),
      reason:
          'policy-id docs/privacy.md: the policy must name the package '
          'the build actually produces ($applicationId), in backticks',
    );
  });

  test('the privacy policy gives a contact address', () {
    expect(
      readFile('docs/privacy.md'),
      contains('support@honestarcade.app'),
      reason: 'policy-contact docs/privacy.md: missing the contact address',
    );
  });

  test('the privacy policy carries an effective date', () {
    final policy = readFile('docs/privacy.md');
    expect(
      policy,
      matches(RegExp(r'Effective date:\s*\d{4}-\d{2}-\d{2}')),
      reason:
          'policy-date docs/privacy.md: expected '
          '"Effective date: YYYY-MM-DD"',
    );
  });

  test('the site root links the policy', () {
    expect(
      readFile('docs/index.md'),
      contains('privacy'),
      reason: 'site-index docs/index.md: must link the privacy policy',
    );
  });

  test('the licence is MIT and names Honest Arcade', () {
    final licence = readFile('LICENSE');
    expect(licence, contains('MIT License'));
    expect(licence, contains('Honest Arcade'));
  });

  test('the README names the policy URL and the trademark carve-out', () {
    final readme = readFile('README.md');
    expect(
      readme,
      contains('honestarcade.github.io/HonestSudoku/privacy'),
      reason: 'readme-privacy README.md: must link the published policy',
    );
    expect(
      readme,
      contains('trademark'),
      reason:
          'readme-license README.md: the License section must state that '
          'a copyright licence grants no trademark rights',
    );
  });
}
