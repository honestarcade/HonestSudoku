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

/// Derive broken text from a real file, and refuse to produce a no-op.
///
/// A fixture that says `real.replaceAll(x, y)` where `x` is no longer in the
/// file produces the file unchanged. The test then asserts that the UNCHANGED
/// real file is refused, fails, and reports something that looks like the
/// rule misbehaving — the misleading shape #102 added the integrity check to
/// prevent.
///
/// It was added at 5 of 19 derivation sites, so the other fourteen still had
/// it. Demonstrated by reflowing the README's code-block alignment, a
/// cosmetic edit, which turned the `-d chrome` fixture into
/// `Expected: contains '-d chrome' / Actual: ''` (#102, #117).
///
/// Routing every derivation through this makes the omission impossible
/// rather than remembered.
String mutate(String source, Object from, String to, {String? why}) {
  final out = from is Pattern
      ? source.replaceAll(from, to)
      : source.replaceAll('$from', to);
  expect(
    out,
    isNot(source),
    reason:
        'fixture-integrity: ${why ?? 'replacing "$from"'} changed nothing, so '
        'this test would assert against the unmodified real file. The text '
        'it looks for has moved or been reworded — fix the fixture, not the '
        'rule.',
  );
  return out;
}

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

    test('the site config names the app', () {
      final offenders = siteConfigOffenders(readFile('docs/_config.yml'));
      expect(
        offenders,
        isEmpty,
        reason: describeOffenders('site-config', offenders),
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

    test('the README carries a Release section', () {
      final offenders = readmeReleaseOffenders(readFile('README.md'));
      expect(
        offenders,
        isEmpty,
        reason: describeOffenders('readme-release', offenders),
      );
    });

    test('a valid Release section that is the last section passes', () {
      // The shape the `\Z` bug broke, and the one the real README cannot
      // exercise because `## Privacy` follows it. Without this fixture a
      // reintroduced lookahead-style slice would be masked exactly as before
      // (#151).
      const lastSection =
          '# Honest Sudoku\n\n'
          '## Quality gate\n\nRun it.\n\n'
          '## Release\n\n'
          'Tag `v0.1.0` and push. `release.yml` ships it; `ci_version.sh` '
          'computes the code. Never re-tag a version.\n\n'
          '| Secret |\n|---|\n'
          '| `HS_KEYSTORE_B64` |\n| `HS_KEYSTORE_PASS` |\n'
          '| `HS_KEY_ALIAS` |\n| `HS_KEY_PASS` |\n'
          '| `PLAY_SERVICE_ACCOUNT_JSON` |\n';
      expect(
        readmeReleaseOffenders(lastSection),
        isEmpty,
        reason: 'readme-release: refused a valid section that ends the file',
      );
    });

    test('the Release rule refuses a README without one', () {
      // The complement. #132 was a criterion reported met with nothing
      // asserting it, so this rule is worth nothing unless it can fail.
      expect(
        readmeReleaseOffenders('# Honest Sudoku\n\n## Privacy\n\nNothing.\n'),
        contains('README.md: no `## Release` section'),
      );
      const missingSecret =
          '## Release\n\n'
          'Tag v0.1.0. release.yml ships it. ci_version.sh computes the code.\n'
          'Never re-tag a version.\n\n'
          'HS_KEYSTORE_B64 HS_KEYSTORE_PASS HS_KEY_ALIAS HS_KEY_PASS\n';
      expect(
        readmeReleaseOffenders(missingSecret),
        contains(
          'README.md: the Release section does not name '
          'PLAY_SERVICE_ACCOUNT_JSON',
        ),
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
    // #89. Everything below was mutated to its opposite during verification
    // with the suite staying green. The published policy is a public
    // statement; these are the sentences that could become false silently.

    test('a deleted permalink is caught', () {
      // The single line the published URL rests on. Remove it and `/privacy`
      // 404s, taking the README link and M7's Play Console URL with it.
      final broken = mutate(
        policy,
        RegExp(r'^permalink: /privacy\n', multiLine: true),
        '',
      );
      expect(
        policyOffenders(broken, applicationId).join('\n'),
        contains('permalink'),
      );
    });

    for (final claim in const {
      'only on your device': 'uploaded to our servers for backup',
      'no ads and contains no purchases':
          'shows banner ads and contains in-app purchases',
      // Without the leading "no": the policy hard-wraps after it, so the
      // rule's own claim key is not contiguous in the file. The rule reads
      // normalised prose and is right to; the fixture has to mutate text that
      // actually exists. The integrity check below is what caught this.
      'advertising, analytics, attribution or crash-reporting SDKs':
          'the usual advertising and analytics SDKs',
      'published by Honest Arcade': 'published by someone else',
    }.entries) {
      test('a policy that stops claiming "${claim.key}" is caught', () {
        final broken = mutate(policy, claim.key, claim.value);
        expect(
          broken,
          isNot(policy),
          reason:
              'fixture-integrity: the mutation changed nothing, so this test '
              'would prove nothing — the policy no longer contains '
              '"${claim.key}"',
        );
        expect(
          policyOffenders(broken, applicationId).join('\n'),
          contains('pinned sentence'),
        );
      });
    }

    test('the collection sentence cannot be inverted', () {
      // #104 closed one half of this and its closing comment said "all three
      // of the substantive gaps". This was the second half of gap 2:
      // changing "are collected, stored, shared, or sold" to "ARE collected
      // ... and sold to third parties" left the suite green, because every
      // other pin matched a different sentence (#117).
      final inverted = mutate(
        policy,
        'No personal information, identifiers, usage analytics, crash '
            'reports,\n  advertising IDs, or diagnostics are collected, '
            'stored, shared, or sold',
        'Personal information, identifiers, usage analytics, crash '
            'reports,\n  advertising IDs, and diagnostics are collected, '
            'stored, shared, and sold to third parties',
      );
      expect(
        inverted,
        isNot(policy),
        reason: 'sanity: the inversion matched nothing',
      );
      expect(
        policyOffenders(inverted, 'com.honestarcade.sudoku'),
        isNotEmpty,
        reason: 'policy-inverted: the collection sentence is unpinned',
      );
    });

    test('a claim hidden in an HTML comment does not satisfy a pin', () {
      // The rules read raw text with no notion of what renders, so the whole
      // visible policy could be replaced with an inverted one and all nine
      // pinned sentences smuggled into one comment block (#117).
      final hidden =
          '---\npermalink: /privacy\n---\n\n'
          '# Privacy\n\nEffective date: 2026-09-20\n\n'
          'This app `com.honestarcade.sudoku` collects everything.\n'
          'Contact support@honestarcade.app\n\n'
          '<!--\n${policy.replaceAll("<!--", "").replaceAll("-->", "")}\n-->\n';
      expect(
        policyOffenders(hidden, 'com.honestarcade.sudoku'),
        isNotEmpty,
        reason: 'policy-comment: a pin was satisfied by unpublished text',
      );
    });

    test('a struck-through claim does not satisfy a pin', () {
      // proseOf stripped `*` and not `~`, so `~~collects no data. none.~~`
      // matched while rendering as struck-through text (#102, #117).
      final struck = mutate(
        policy,
        'collects **no data**. None.',
        '~~collects **no data**. None.~~',
      );
      expect(struck, isNot(policy), reason: 'sanity: nothing was struck');
      expect(
        policyOffenders(struck, 'com.honestarcade.sudoku'),
        isNotEmpty,
        reason: 'policy-struck: strikethrough satisfied a pin',
      );
    });

    test('a contradiction appended after the pins is caught', () {
      // Every pin can be present while the page says the opposite further
      // down. A substring pin cannot see that, so the inversions are refused
      // by name (#117).
      for (final appended in const [
        '\n\n**Update:** the app now collects diagnostics and shares them '
            'with our ad partners.\n',
        '\n\nWe collect your email address for marketing.\n',
        '\n\nThe full version shows banner ads.\n',
      ]) {
        expect(
          policyOffenders(policy + appended, 'com.honestarcade.sudoku'),
          isNotEmpty,
          reason: 'policy-contradiction: "$appended" was not caught',
        );
      }
    });

    test('a site root that keeps the word but drops the link is caught', () {
      // The rule used to match the word "privacy" anywhere, so a sentence
      // announcing the page had been taken down satisfied it. It failed open
      // on the exact regression it exists to prevent.
      const broken =
          '# Honest Sudoku\n\nThe privacy page has been taken '
          'down.\n';
      expect(siteIndexOffenders(broken), isNotEmpty);
      // The spellings that actually resolve. EVERY ONE was curled against
      // the live site on 2026-09-20 before being added here — the step both
      // this fixture and the one before it skipped, and two seconds each.
      //
      //   /privacy         200      /privacy.md      404
      //   /privacy.html    200      /privacy/        404
      //   /privacy#section 200      bare /privacy    404
      //   /privacy?utm=x   200
      //
      // The previous list contained `](/privacy)` (#101) and then, three
      // lines below the comment explaining why that was wrong, `](privacy.md)`
      // (#110). A negative fixture that blesses a broken URL is worse than no
      // fixture: the next person to write the correct form is told they are
      // wrong.
      for (final good in const [
        '- [Privacy policy](privacy)',
        '- [Privacy policy](privacy.html)',
        '- [Privacy policy](privacy "Policy")',
        // Six forms the rule used to refuse although they return 200.
        '- [Privacy policy](./privacy)',
        '- [Privacy policy](privacy#section)',
        '- [Privacy policy](privacy?utm=x)',
        '- [Privacy policy](<privacy>)',
        "- [Privacy policy]({{ '/privacy' | absolute_url }})",
        '- [Privacy policy]({{ site.url }}{{ site.baseurl }}/privacy)',
        // And the ones it already accepted.
        '- [Privacy policy]({{ site.baseurl }}/privacy)',
        "- [Privacy policy]({{ '/privacy' | relative_url }})",
        '- [Privacy policy](https://honestarcade.github.io/HonestSudoku/privacy)',
        '- [Privacy policy][pp]\n\n[pp]: privacy',
        '<a href="privacy">Privacy policy</a>',
      ]) {
        expect(
          siteIndexOffenders(good),
          isEmpty,
          reason: 'site-index-negative: refused a link that resolves: $good',
        );
      }

      // Spellings that 404, refused by name. `privacy.md` is the source
      // extension — Jekyll serves privacy.html — and a trailing slash is a
      // directory that does not exist.
      for (final bad in const [
        '- [Privacy policy](privacy.md)',
        '- [Privacy policy](privacy/)',
        '- [Privacy policy](/privacy/)',
      ]) {
        expect(
          siteIndexOffenders(bad),
          isNotEmpty,
          reason: 'site-index: blessed a URL that 404s: $bad',
        );
      }

      // A link to a FOREIGN host passed, because the rule reduced an
      // absolute URL to its path and compared only that (#110).
      expect(
        siteIndexOffenders(
          '- [Privacy policy](https://evil.example.com/HonestSudoku/privacy)',
        ),
        isNotEmpty,
        reason: 'site-index: any host serving /HonestSudoku/privacy passed',
      );

      // A link that renders nothing. Reproduced on the real docs/index.md by
      // moving its only link into a fenced block, with the suite green.
      for (final hidden in const [
        '# Honest Sudoku\n\n```\n- [Privacy policy](privacy)\n```\n',
        '# Honest Sudoku\n\n<!-- - [Privacy policy](privacy) -->\n',
        '# Honest Sudoku\n\nWrite `[Privacy policy](privacy)` to link it.\n',
      ]) {
        expect(
          siteIndexOffenders(hidden),
          isNotEmpty,
          reason:
              'site-index: a link that is never published satisfied the '
              'rule: $hidden',
        );
      }

      // A page carrying BOTH a correct link and a broken one passes: the
      // correct one resolves, and that is what a reader clicks.
      expect(
        siteIndexOffenders(
          '- [Privacy policy](privacy)\n- [Old link](/privacy)\n',
        ),
        isEmpty,
        reason: 'site-index: one resolving link is enough',
      );

      // And the root-absolute form is refused BY NAME, with the reason.
      final rootAbsolute = siteIndexOffenders('- [Privacy policy](/privacy)');
      expect(
        rootAbsolute,
        isNotEmpty,
        reason:
            'site-index-root-absolute: this 404s on a project page and the '
            'guard used to bless it',
      );
      expect(rootAbsolute.single, contains('PROJECT page'));
    });

    test('an MIT header over a non-MIT body is caught', () {
      const broken =
          'MIT License\n\n'
          'Copyright (c) 2026 Honest Arcade\n\n'
          'Commercial use is prohibited. All rights reserved.\n';
      final offenders = licenceOffenders(broken).join('\n');
      expect(
        offenders,
        contains('not the MIT text'),
        reason:
            'licence-body: two substrings made a GPL body pass as MIT, which '
            'is what the licence says about itself rather than what it grants',
      );
    });

    test('a missing copyright line is caught', () {
      final broken = mutate(
        readFile('LICENSE'),
        RegExp(r'Copyright \(c\) \d{4} Honest Arcade'),
        'Honest Arcade',
      );
      expect(licenceOffenders(broken).join('\n'), contains('Copyright'));
    });

    test('a site config naming another app is caught', () {
      expect(
        siteConfigOffenders('title: Frog Across\n').join('\n'),
        contains('_config.yml'),
      );
      expect(siteConfigOffenders('theme: minima\n'), isNotEmpty);
    });

    for (final spelling in const [
      'flutter run -dchrome',
      'flutter run --device-id chrome',
      'flutter run -d  chrome',
    ]) {
      test('`$spelling` is caught', () {
        // Tested against the rule directly, not through a README mutation.
        // Several fixtures in this group derive their broken text from the
        // real file, so a no-op replaceAll makes them fail with `Actual: ''` —
        // fail-safe, but a red run there is not proof the rule fired.
        expect(
          readmeOffenders('# X\n\n```sh\n$spelling\n```\n').join('\n'),
          contains('chrome'),
        );
      });
    }

    test('the chrome rule leaves innocent text alone', () {
      expect(
        readmeOffenders(readme),
        isEmpty,
        reason:
            'chrome-negative: the widened pattern started matching the real '
            'README, which has no web example',
      );
      expect(
        readmeOffenders('$readme\n\nTested on chrome-plated hardware.\n'),
        isEmpty,
      );
    });

    test('a wrong package id in the policy is caught', () {
      final broken = mutate(
        policy,
        '`$applicationId`',
        '`com.honestarcade.sudoku.honest_sudoku`',
      );
      expect(
        policyOffenders(broken, applicationId).join('\n'),
        contains('different app'),
      );
    });

    test('a deleted effective date is caught', () {
      final broken = mutate(
        policy,
        RegExp(r'Effective date:\s*\d{4}-\d{2}-\d{2}'),
        'Effective date: soon',
      );
      expect(
        policyOffenders(broken, applicationId).join('\n'),
        contains('Effective date'),
      );
    });

    test('a deleted contact address is caught', () {
      final broken = mutate(policy, 'support@honestarcade.app', '');
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
      final broken = mutate(
        policy,
        'permissions at all',
        'permissions for advertising',
      );
      expect(
        policyOffenders(broken, applicationId).join('\n'),
        contains('invariant 1'),
      );
    });

    // #104. Three things the guard was satisfied while missing.

    test('a LICENSE that loses the MIT grant condition is caught', () {
      // The licence's ONE condition. Without it this is a bare grant with no
      // attribution requirement and is not MIT — and the whole suite stayed
      // green when it was deleted.
      final broken = mutate(
        readFile('LICENSE'),
        RegExp(
          r'The above copyright notice and this permission notice shall be '
          r'included in all\ncopies or substantial portions of the Software\.\n\n',
        ),
        '',
      );
      expect(
        broken,
        isNot(readFile('LICENSE')),
        reason: 'fixture-integrity: the mutation changed nothing',
      );
      expect(
        licenceOffenders(broken).join('\n'),
        contains('The above copyright notice'),
      );
    });

    test('a policy that inverts its headline claim is caught', () {
      final broken = mutate(
        policy,
        'collects **no data**. None.',
        'collects diagnostics and usage analytics.',
      );
      expect(broken, isNot(policy), reason: 'fixture-integrity');
      expect(
        policyOffenders(broken, applicationId).join('\n'),
        contains('collects nothing'),
      );
    });

    for (final claim in const {
      // Contiguous substrings: the policy is hard-wrapped, so mutating the
      // rule's own claim key would be a no-op. The fixture-integrity
      // assertion below is what caught that, again.
      'collected from children': "children's privacy",
      'ask us to delete': 'nothing to request',
      'Uninstalling the app deletes them': 'uninstalling',
    }.entries) {
      test('deleting the "${claim.value}" paragraph is caught', () {
        final broken = mutate(policy, claim.key, 'something else entirely');
        expect(broken, isNot(policy), reason: 'fixture-integrity');
        expect(
          policyOffenders(broken, applicationId).join('\n'),
          contains('pinned sentence'),
        );
      });
    }

    // #102 and #98. The other direction: ordinary edits that change no meaning
    // must not turn the suite red with a message implying a fact was removed.
    test('legal spellings of the same fact are accepted', () {
      for (final spelling in const [
        'permalink: "/privacy"',
        "permalink: '/privacy'",
      ]) {
        final edited = mutate(policy, 'permalink: /privacy', spelling);
        expect(
          policyOffenders(
            edited,
            applicationId,
          ).where((o) => o.contains('permalink')),
          isEmpty,
          reason: 'overshoot: `$spelling` is legal YAML for the same value',
        );
      }

      for (final title in const [
        'title: "Honest Sudoku"',
        "title: 'Honest Sudoku'",
        'title: Honest Sudoku # the published <title>',
      ]) {
        expect(
          siteConfigOffenders('$title\ntheme: jekyll-theme-primer\n'),
          isEmpty,
          reason: 'overshoot: `$title` is legal YAML for the same value',
        );
      }

      for (final notice in const [
        'Copyright (c) 2026-2027 Honest Arcade',
        'Copyright (C) 2026 Honest Arcade',
        'Copyright © 2026 Honest Arcade',
      ]) {
        final edited = readFile('LICENSE')
            .replaceAll('Copyright (c) 2026 Honest Arcade', notice);
        expect(
          licenceOffenders(edited).where((o) => o.contains('Copyright')),
          isEmpty,
          reason: 'overshoot: `$notice` is an ordinary way to write it',
        );
      }

      expect(
        readmeOffenders(readme.replaceAll('trademark', 'trade mark'))
            .where((o) => o.contains('trademark rights')),
        isEmpty,
        reason: 'overshoot: "trade mark" is the British spelling',
      );

      // An Oxford comma in the SDK sentence must not break the build.
      final oxford = mutate(
        policy,
        'attribution or crash-reporting',
        'attribution, or crash-reporting',
      );
      expect(oxford, isNot(policy), reason: 'fixture-integrity');
      expect(
        policyOffenders(oxford, applicationId),
        isEmpty,
        reason:
            'overshoot: one comma turned the suite red with a message '
            'saying the policy no longer stated something it plainly did',
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
        contains('not the MIT text'),
      );
    });

    test('a licence that negates the MIT grant in prose is caught', () {
      // The rule was four substrings, so a licence could contain all four
      // while saying the opposite around them. This text passed every check
      // (#89, #104, #111).
      const negated =
          'MIT License\n\n'
          'Copyright (c) 2026 Honest Arcade\n\n'
          'THIS IS NOT AN MIT LICENCE. Commercial use, sublicensing and sale\n'
          'are PROHIBITED. All other rights are reserved by Honest Arcade.\n\n'
          'For the avoidance of doubt, nothing here should be read as saying\n'
          '"Permission is hereby granted, free of charge" to deal in the\n'
          'Software "without restriction".\n\n'
          'The above copyright notice and this permission notice shall be\n'
          'included in all copies or substantial portions of the Software.\n\n'
          'THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND.\n';
      expect(
        licenceOffenders(negated).join('\n'),
        contains('not the MIT text'),
        reason:
            'licence-negated: a licence that says it is not MIT, and quotes '
            'the required phrases only to disclaim them, passed',
      );
    });

    test('the real licence re-wrapped is still accepted', () {
      // The complement: comparison is whitespace-normalised, so re-flowing
      // the file is fine. A check that also refuses the real licence in a
      // different wrapping is a check people delete.
      final real = readFile('LICENSE');
      expect(
        licenceOffenders(real.replaceAll('\n', ' ')),
        isEmpty,
        reason: 'licence-rewrap: re-wrapping must not be an offence',
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
      final broken = mutate(
        readme,
        'flutter run                        #',
        'flutter run -d chrome              #',
      );
      expect(readmeOffenders(broken).join('\n'), contains('-d chrome'));
    });

    test('a reworded intro is caught', () {
      final broken = mutate(
        readme,
        'A fully offline Sudoku game for Android phones, built with Flutter.',
        'A Sudoku game.',
      );
      expect(readmeOffenders(broken).join('\n'), contains('intro sentence'));
    });

    test('a deleted Requirements line is caught', () {
      final broken = mutate(readme, 'Android 7.0 (API 24) or newer', 'any');
      expect(readmeOffenders(broken).join('\n'), contains('Requirements'));
    });

    test('a README that claims other platforms is caught', () {
      final broken = '$readme\n\nIt also runs on iOS and macOS.\n';
      expect(readmeOffenders(broken).join('\n'), contains('runs on iOS'));
    });

    test('a dropped policy link is caught', () {
      final broken = mutate(
        readme,
        'honestarcade.github.io/HonestSudoku/privacy',
        'example.com',
      );
      expect(readmeOffenders(broken).join('\n'), contains('published policy'));
    });

    test('a dropped trademark carve-out is caught', () {
      final broken = mutate(readme, 'trademark', 'copyright');
      expect(readmeOffenders(broken).join('\n'), contains('trademark rights'));
    });
  });
}
