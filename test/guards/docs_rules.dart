// The docs-consistency rules, as pure functions over strings.
//
// They are pure for the reason #15's rules are (#83): a rule proven only
// against the real, correct file has been shown to pass, never to fire.
// `docs_consistency_test.dart` held presence and equality assertions and
// nothing else, so verification had to copy the tree and mutate it four ways
// by hand to learn whether the guard worked. It did. Nothing would have
// noticed if it stopped.
//
// Every rule returns a list of offender strings — empty means the text is
// consistent — so each one can be fed both the repository's real files and a
// deliberately broken fixture.
library;

/// Strips Kotlin `//` line comments so a commented-out `applicationId` cannot
/// be counted.
String stripKotlinLineComments(String source) => source
    .split('\n')
    .map((line) {
      final at = line.indexOf('//');
      return at == -1 ? line : line.substring(0, at);
    })
    .join('\n');

/// Every `applicationId = "..."` in a Gradle build file, comments removed.
///
/// A list rather than a value: the policy quotes this id, and a build file
/// with two of them cannot be checked against anything.
List<String> applicationIdsIn(String gradleSource) =>
    RegExp(r'applicationId\s*=\s*"([^"]+)"')
        .allMatches(stripKotlinLineComments(gradleSource))
        .map((m) => m.group(1)!)
        .toList();

/// The `application_id:` recorded under `android:` in the project config.
String? configApplicationId(String configYaml) => RegExp(
  r'^\s+application_id:\s*(\S+)\s*$',
  multiLine: true,
).firstMatch(configYaml)?.group(1);

/// The config must record the id the build actually produces.
List<String> configIdOffenders(String configYaml, String applicationId) {
  final recorded = configApplicationId(configYaml);
  if (recorded == null) {
    return ['.n8/config.yml: no application_id under android:'];
  }
  if (recorded != applicationId) {
    return [
      '.n8/config.yml: records `$recorded`, the build produces '
          '`$applicationId`',
    ];
  }
  return const [];
}

/// The published policy must name the right package, carry a date, keep its
/// contact address, and keep claiming what the build actually does.
///
/// The last of those is the one worth having. A policy that stops saying "no
/// permissions" while the build still declares none is only stale; a policy
/// that keeps saying it while the build gains one is a false public statement,
/// and this rule is what a future permission would have to get past.
List<String> policyOffenders(String policy, String applicationId) {
  final offenders = <String>[];
  // Whitespace-normalised for the prose claims: the policy is hard-wrapped, so
  // "requests no permissions at all" really is split across two lines in the
  // file and a literal match on it finds nothing. A rule that silently misses
  // the sentence it exists to protect is the failure this whole file is about.
  final prose = policy.replaceAll(RegExp(r'\s+'), ' ');
  if (!policy.contains('`$applicationId`')) {
    offenders.add(
      'docs/privacy.md: does not name `$applicationId` in backticks — the '
      'policy would describe a different app',
    );
  }
  if (!RegExp(r'Effective date:\s*\d{4}-\d{2}-\d{2}').hasMatch(policy)) {
    offenders.add('docs/privacy.md: no "Effective date: YYYY-MM-DD"');
  }
  if (!policy.contains('support@honestarcade.app')) {
    offenders.add('docs/privacy.md: no contact address');
  }
  if (!prose.contains('no permissions at all')) {
    offenders.add(
      'docs/privacy.md: no longer claims the app requests no permissions at '
      'all — invariant 1 is what the policy publishes',
    );
  }
  if (!prose.contains('no network access')) {
    offenders.add(
      'docs/privacy.md: no longer claims the app has no network access',
    );
  }

  // The published URL rests on this one line of front matter. Delete it and
  // `/privacy` 404s, the README link breaks, and so does the URL M7 gives the
  // Play Console — and nothing noticed (#89). Liveness is deliberately out of
  // this guard's scope, but the permalink is a file fact, not a network one.
  if (!RegExp(
    r'^permalink:\s*/privacy\s*$',
    multiLine: true,
  ).hasMatch(policy)) {
    offenders.add(
      'docs/privacy.md: no `permalink: /privacy` in the front matter — the '
      'published policy URL depends on it',
    );
  }

  // The substantive claims. These are public statements a player or a Play
  // reviewer reads, and each was mutated to its opposite with the suite
  // staying green. The dependency blocklist guards the CODE behind two of
  // them; nothing guarded the SENTENCE, so the policy could be edited to say
  // the opposite of a true thing while the code stayed clean (#89).
  const claims = {
    'only on your device':
        'that player data never leaves the device — the Play data-safety claim',
    'no ads and contains no purchases':
        'that the app shows no ads and contains no purchases',
    'no advertising, analytics, attribution or crash-reporting SDKs':
        'that the app contains no advertising or analytics SDKs',
    'published by Honest Arcade': 'who publishes the app',
  };
  for (final claim in claims.entries) {
    if (!prose.contains(claim.key)) {
      offenders.add(
        'docs/privacy.md: no longer states ${claim.value} '
        '(looked for "${claim.key}")',
      );
    }
  }
  return offenders;
}

/// The site config must name the app, since the published `<title>` is it.
///
/// #16's AC2 requires it and nothing read it: mutating it to another app's
/// name left the suite green (#89).
List<String> siteConfigOffenders(String configYaml) =>
    RegExp(r'^title:\s*Honest Sudoku\s*$', multiLine: true).hasMatch(configYaml)
    ? const []
    : const ['docs/_config.yml: `title: Honest Sudoku` is missing or changed'];

/// The site root must link the policy, or the published policy is unreachable.
///
/// Matched as a markdown link whose destination is the policy, not as the word
/// "privacy" anywhere in the file. The word test was satisfied by a sentence
/// reading "The privacy page has been taken down." — it failed open on the
/// exact regression it exists to prevent (#89).
List<String> siteIndexOffenders(String indexMd) =>
    RegExp(r'\]\(\s*/?privacy(\.html|\.md)?\s*\)').hasMatch(indexMd)
    ? const []
    : const [
        'docs/index.md: no markdown link pointing at the privacy policy — '
            'the site root is how a reviewer reaches it',
      ];

/// MIT, naming the studio.
List<String> licenceOffenders(String licence) {
  final offenders = <String>[];
  if (!licence.contains('MIT License')) {
    offenders.add('LICENSE: not an MIT licence');
  }
  if (!licence.contains('Honest Arcade')) {
    offenders.add('LICENSE: does not name Honest Arcade');
  }
  if (!RegExp(r'Copyright \(c\)\s*\d{4}\s+Honest Arcade').hasMatch(licence)) {
    offenders.add('LICENSE: no `Copyright (c) <year> Honest Arcade` line');
  }
  // The body, not the header. A GPL body under an `MIT License` line passed,
  // including one reading "Commercial use is prohibited" (#89). These three
  // sentences are what make a licence MIT, rather than what it calls itself.
  final prose = licence.replaceAll(RegExp(r'\s+'), ' ');
  for (final phrase in const [
    'Permission is hereby granted, free of charge',
    'without restriction',
    'THE SOFTWARE IS PROVIDED "AS IS"',
  ]) {
    if (!prose.contains(phrase)) {
      offenders.add('LICENSE: the MIT body is missing "$phrase"');
    }
  }
  return offenders;
}

/// #12's AC5 and #16's README claims, in one rule.
///
/// The `-d chrome` clause is the only one of these that guards an ABSENCE, and
/// absences are what regress silently: the scaffold line was deleted once, by
/// hand, and until now nothing would have objected to it coming back. This app
/// is Android-only and has no web platform directory, so the example would not
/// even run.
List<String> readmeOffenders(String readme) {
  final offenders = <String>[];
  const intro =
      'A fully offline Sudoku game for Android phones, built with Flutter.';
  if (!readme.contains(intro)) {
    offenders.add('README.md: the intro sentence is missing or reworded');
  }
  if (!RegExp(r'Android 7\.0 \(API 24\) or newer').hasMatch(readme)) {
    offenders.add(
      'README.md: no Requirements line stating "Android 7.0 (API 24) or newer"',
    );
  }
  // `-dchrome` is ordinary shell habit and `--device-id chrome` is the long
  // form. Both are valid `flutter run` invocations and both slipped past the
  // original `-d\s+chrome` (#89).
  if (RegExp(r'(-d\s*|--device-id\s+)chrome').hasMatch(readme)) {
    offenders.add(
      'README.md: the `flutter run -d chrome` example is back — this project '
      'has no web platform',
    );
  }
  for (final platform in const ['iOS', 'macOS', 'Windows', 'the web']) {
    if (RegExp(r'runs on .*' + RegExp.escape(platform)).hasMatch(readme)) {
      offenders.add('README.md: claims the app runs on $platform');
    }
  }
  if (!readme.contains('honestarcade.github.io/HonestSudoku/privacy')) {
    offenders.add('README.md: does not link the published policy');
  }
  if (!readme.contains('trademark')) {
    offenders.add(
      'README.md: the License section no longer states that a copyright '
      'licence grants no trademark rights',
    );
  }
  return offenders;
}
