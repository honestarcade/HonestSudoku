@Tags(['guard'])
library;

// Guard for #16 and #12's AC5: the published privacy policy, the site root,
// the licence and the README must keep saying the same thing as the build they
// describe.
//
// The package id appears in three places — the Gradle build, the project
// config, and the policy a player reads. They can drift independently and
// nothing else would notice, and the one that matters is the policy: a wrong
// id there is a public document describing a different app.
//
// The rules live in docs_rules.dart as pure functions so each can be shown to
// FIRE, not just to pass. This file used to hold presence and equality
// assertions only, which meant verification had to copy the tree and mutate it
// by hand to find out whether the guard worked (#83). The fixtures below are
// those mutations, made permanent.
//
// What this does NOT cover: whether the policy is legally sufficient, and
// whether the page is actually live. The live check is the post-merge curl
// recorded on #16 and re-checked by /n8-verify.
import 'package:flutter_test/flutter_test.dart';

import 'docs_rules.dart';
import 'repo_files.dart';

const _gradle = 'android/app/build.gradle.kts';

void main() {
  late String applicationId;
  late String policy;
  late String readme;

  setUpAll(() {
    final found = applicationIdsIn(readFile(_gradle));
    if (found.length != 1) {
      fail(
        'application-id $_gradle: expected exactly one applicationId, found '
        '${found.length} — the policy quotes this value and cannot be checked '
        'against an ambiguous build',
      );
    }
    applicationId = found.single;
    policy = readFile('docs/privacy.md');
    readme = readFile('README.md');
  });

  group('the repository as it stands', () {
    test('the config records the same application id as the build', () {
      final offenders = configIdOffenders(
        stripYamlComments(readFile('.n8/config.yml')),
        applicationId,
      );
      expect(
        offenders,
        isEmpty,
        reason: describeOffenders('application-id', offenders),
      );
    });

    test('the privacy policy is consistent with the build', () {
      final offenders = policyOffenders(policy, applicationId);
      expect(
        offenders,
        isEmpty,
        reason: describeOffenders('policy', offenders),
      );
    });

    test('the site root links the policy', () {
      final offenders = siteIndexOffenders(readFile('docs/index.md'));
      expect(
        offenders,
        isEmpty,
        reason: describeOffenders('site-index', offenders),
      );
    });

    test('the licence is MIT and names Honest Arcade', () {
      final offenders = licenceOffenders(readFile('LICENSE'));
      expect(
        offenders,
        isEmpty,
        reason: describeOffenders('licence', offenders),
      );
    });

    test('the README makes every claim #12 and #16 require', () {
      final offenders = readmeOffenders(readme);
      expect(
        offenders,
        isEmpty,
        reason: describeOffenders('readme', offenders),
      );
    });
  });

  // The four mutations verification ran by hand, plus the ones #12's AC5 asked
  // for and nothing read. Each proves a rule fires; without them the group
  // above cannot distinguish a working guard from a guard that returns an
  // empty list unconditionally.
  group('each rule fires', () {
    test('a wrong package id in the policy is caught', () {
      final broken = policy.replaceAll(
        '`$applicationId`',
        '`com.honestarcade.sudoku.honest_sudoku`',
      );
      expect(
        policyOffenders(broken, applicationId).join('\n'),
        contains('different app'),
      );
    });

    test('a deleted effective date is caught', () {
      final broken = policy.replaceAll(
        RegExp(r'Effective date:\s*\d{4}-\d{2}-\d{2}'),
        'Effective date: soon',
      );
      expect(
        policyOffenders(broken, applicationId).join('\n'),
        contains('Effective date'),
      );
    });

    test('a deleted contact address is caught', () {
      final broken = policy.replaceAll('support@honestarcade.app', '');
      expect(
        policyOffenders(broken, applicationId).join('\n'),
        contains('contact address'),
      );
    });

    test('a policy that stops claiming no permissions is caught', () {
      // The mutation that matters most. A policy is a public statement, and
      // the moment the build gains a permission this sentence becomes false —
      // so the sentence is guarded, not merely present today.
      // Note the substring: the policy hard-wraps after "no", so the
      // sentence this mutates is not contiguous in the file either.
      final broken = policy.replaceAll(
        'permissions at all',
        'permissions for advertising',
      );
      expect(
        policyOffenders(broken, applicationId).join('\n'),
        contains('invariant 1'),
      );
    });

    test('a mismatched config id is caught', () {
      const broken = 'android:\n  application_id: com.example.other\n';
      expect(
        configIdOffenders(broken, applicationId).join('\n'),
        contains('com.example.other'),
      );
    });

    test('a missing application_id in the config is caught', () {
      expect(
        configIdOffenders('android:\n  minSdk: 24\n', applicationId).join('\n'),
        contains('no application_id'),
      );
    });

    test('a commented-out applicationId does not count', () {
      // The reason the Kotlin comments are stripped at all: two ids, one of
      // them dead, would make the policy uncheckable against either.
      const gradle = '''
android {
    defaultConfig {
        // applicationId = "com.honestarcade.sudoku.honest_sudoku"
        applicationId = "com.honestarcade.sudoku"
    }
}
''';
      expect(applicationIdsIn(gradle), ['com.honestarcade.sudoku']);
    });

    test('a site root that drops the policy link is caught', () {
      expect(siteIndexOffenders('# Honest Sudoku\n'), isNotEmpty);
    });

    test('a non-MIT licence is caught', () {
      expect(
        licenceOffenders('GNU GENERAL PUBLIC LICENSE\nHonest Arcade\n').join(),
        contains('not an MIT licence'),
      );
    });

    test('a licence that drops the studio name is caught', () {
      expect(
        licenceOffenders('MIT License\n\nCopyright (c) 2026 Someone\n').join(),
        contains('does not name Honest Arcade'),
      );
    });

    // #12's AC5. The removal is the part that regresses silently: the scaffold
    // line was deleted once, by hand, and until now nothing objected to it
    // coming back.
    test('the returning -d chrome example is caught', () {
      final broken = readme.replaceAll(
        'flutter run                        #',
        'flutter run -d chrome              #',
      );
      expect(readmeOffenders(broken).join('\n'), contains('-d chrome'));
    });

    test('a reworded intro is caught', () {
      final broken = readme.replaceAll(
        'A fully offline Sudoku game for Android phones, built with Flutter.',
        'A Sudoku game.',
      );
      expect(readmeOffenders(broken).join('\n'), contains('intro sentence'));
    });

    test('a deleted Requirements line is caught', () {
      final broken = readme.replaceAll('Android 7.0 (API 24) or newer', 'any');
      expect(readmeOffenders(broken).join('\n'), contains('Requirements'));
    });

    test('a README that claims other platforms is caught', () {
      final broken = '$readme\n\nIt also runs on iOS and macOS.\n';
      expect(readmeOffenders(broken).join('\n'), contains('runs on iOS'));
    });

    test('a dropped policy link is caught', () {
      final broken = readme.replaceAll(
        'honestarcade.github.io/HonestSudoku/privacy',
        'example.com',
      );
      expect(readmeOffenders(broken).join('\n'), contains('published policy'));
    });

    test('a dropped trademark carve-out is caught', () {
      final broken = readme.replaceAll('trademark', 'copyright');
      expect(readmeOffenders(broken).join('\n'), contains('trademark rights'));
    });
  });
}
