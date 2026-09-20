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

/// Lowercased, comma-stripped, whitespace-collapsed.
///
/// The policy is hard-wrapped prose that a non-engineer may edit. Matching raw
/// substrings meant one Oxford comma turned the suite red with a message
/// saying the policy "no longer states" something it plainly still stated
/// (#102). Normalising the punctuation that carries no meaning removes the
/// silliest of those false alarms.
String proseOf(String text) => text
    .toLowerCase()
    // Markdown emphasis and code ticks carry no meaning for these claims, and
    // the policy bolds half of them.
    .replaceAll(RegExp(r'[*`]'), '')
    .replaceAll(',', '')
    .replaceAll(RegExp(r'\s+'), ' ');

/// A sentence this guard pins, with the reason it is pinned.
///
/// The wording IS the thing being protected — these sentences are what a Play
/// reviewer reads and what the data-safety form quotes — so the check is a
/// literal one on purpose. What changed is the message: "no longer states"
/// reads as an accusation when someone has merely reworded, and the fastest
/// way past an accusation is to delete the check.
class PinnedClaim {
  const PinnedClaim(this.text, this.about);
  final String text;
  final String about;
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
  final prose = proseOf(policy);
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
    r'''^permalink:\s*["']?/privacy["']?\s*$''',
    multiLine: true,
  ).hasMatch(policy)) {
    offenders.add(
      'docs/privacy.md: no `permalink: /privacy` in the front matter — the '
      'published policy URL depends on it. Quoted forms are fine; a trailing '
      'slash is not, because it changes the published URL.',
    );
  }

  // The substantive claims. These are public statements a player or a Play
  // reviewer reads, and each was mutated to its opposite with the suite
  // staying green. The dependency blocklist guards the CODE behind some of
  // them; nothing guarded the SENTENCE, so the policy could be edited to say
  // the opposite of a true thing while the code stayed clean (#89, #104).
  const claims = [
    PinnedClaim('collects no data. none.', 'that the app collects nothing'),
    PinnedClaim(
      'only on your device',
      'that player data never leaves the '
          'device — the claim Play\'s data-safety form quotes',
    ),
    PinnedClaim(
      'no ads and contains no purchases',
      'that the app shows no ads and contains no purchases',
    ),
    PinnedClaim(
      'no advertising analytics attribution or crash-reporting sdks',
      'that the app contains no advertising or analytics SDKs',
    ),
    PinnedClaim('published by honest arcade', 'who publishes the app'),
    PinnedClaim(
      'no data is collected from children',
      "children's privacy, which #16's AC1 requires",
    ),
    PinnedClaim(
      'nothing for you to request a copy of or ask us to delete',
      'that there is nothing to request or delete',
    ),
    PinnedClaim(
      'uninstalling the app deletes them',
      'that uninstalling removes the stored data',
    ),
  ];
  for (final claim in claims) {
    if (!prose.contains(claim.text)) {
      offenders.add(
        'docs/privacy.md: the pinned sentence about ${claim.about} is not '
        'there. Looked for "${claim.text}". If you reworded it deliberately, '
        'update test/guards/docs_rules.dart in the same commit — this text is '
        'published and some of it is quoted in the Play listing.',
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
    RegExp(
      r'''^title:\s*["']?Honest Sudoku["']?\s*(#.*)?$''',
      multiLine: true,
    ).hasMatch(configYaml)
    ? const []
    : const ['docs/_config.yml: `title: Honest Sudoku` is missing or changed'];

/// The site root must link the policy, or the published policy is unreachable.
///
/// Wrong in both directions before (#101). It refused every idiomatic Jekyll
/// spelling — `{{ site.baseurl }}/privacy`, `relative_url`, an absolute URL, a
/// title attribute, a reference link, an HTML anchor — and it ACCEPTED
/// `](/privacy)`, which on a project page resolves to
/// `honestarcade.github.io/privacy` and returns 404. A negative fixture
/// asserted that broken spelling must pass, calling it "a real link".
///
/// So this resolves the destination rather than matching the href text:
/// Liquid wrappers are unwrapped, an absolute URL is reduced to its path, and
/// the root-absolute form is refused by name, with the reason.
List<String> siteIndexOffenders(String indexMd) {
  final destinations = <String>[];
  // [text](dest) and [text](dest "title"). The destination may contain spaces
  // when it is a Liquid expression, so this matches to the closing paren and
  // strips a trailing title rather than forbidding whitespace.
  for (final m in RegExp(r'\]\(([^)]*)\)').allMatches(indexMd)) {
    destinations.add(m.group(1)!.replaceAll(RegExp(r'\s+"[^"]*"$'), ''));
  }
  // [ref]: dest
  for (final m in RegExp(
    r'^\s*\[[^\]]+\]:\s*(\S+)',
    multiLine: true,
  ).allMatches(indexMd)) {
    destinations.add(m.group(1)!);
  }
  // <a href="dest">
  for (final m in RegExp(
    '<a[^>]+href=["\']([^"\']+)["\']',
  ).allMatches(indexMd)) {
    destinations.add(m.group(1)!);
  }

  var rootAbsolute = false;
  for (final raw in destinations) {
    var dest = raw.trim();
    // A Liquid wrapper means the author asked Jekyll to prepend the project
    // prefix, so what is left is site-relative and correct — the opposite of
    // a bare `/privacy`, which is not.
    final viaBaseurl =
        dest.contains('site.baseurl') || dest.contains('relative_url');
    dest = dest.replaceAll(RegExp(r'\{\{\s*site\.baseurl\s*\}\}'), '');
    final liquid = RegExp(r'''\{\{\s*['"]([^'"]+)['"]\s*\|\s*\w+\s*\}\}''')
        .firstMatch(dest);
    if (liquid != null) dest = liquid.group(1)!;
    // An absolute URL is reduced to its path.
    final absolute = RegExp(r'^https?://[^/]+(/.*)$').firstMatch(dest);
    if (absolute != null) dest = absolute.group(1)!;
    dest = dest.replaceAll(RegExp(r'\.(html|md)$'), '');
    dest = dest.replaceAll(RegExp(r'/$'), '');
    if (viaBaseurl) dest = dest.replaceFirst(RegExp(r'^/'), '');

    if (dest == 'privacy' || dest.endsWith('/HonestSudoku/privacy')) {
      return const [];
    }
    if (dest == '/privacy') rootAbsolute = true;
  }

  if (rootAbsolute) {
    return const [
      'docs/index.md: the policy link is root-absolute (`/privacy`). This is '
          'a GitHub Pages PROJECT page served under /HonestSudoku/, so that '
          'resolves to honestarcade.github.io/privacy and 404s. Write '
          '`privacy` or `{{ site.baseurl }}/privacy`.',
    ];
  }
  return const [
    'docs/index.md: no link that resolves to the privacy policy — the site '
        'root is how a reviewer reaches it',
  ];
}

/// MIT, naming the studio.
List<String> licenceOffenders(String licence) {
  final offenders = <String>[];
  if (!licence.contains('MIT License')) {
    offenders.add('LICENSE: not an MIT licence');
  }
  if (!licence.contains('Honest Arcade')) {
    offenders.add('LICENSE: does not name Honest Arcade');
  }
  // A year range and either spelling of the symbol are ordinary ways to
  // write this notice; refusing them was a false alarm (#102).
  if (!RegExp(
    r'Copyright\s+(\((c|C)\)|©)\s*\d{4}(\s*[-–]\s*\d{4})?\s+Honest Arcade',
  ).hasMatch(licence)) {
    offenders.add('LICENSE: no `Copyright (c) <year> Honest Arcade` line');
  }
  // The body, not the header. A GPL body under an `MIT License` line passed,
  // including one reading "Commercial use is prohibited" (#89). These three
  // sentences are what make a licence MIT, rather than what it calls itself.
  final prose = licence.replaceAll(RegExp(r'\s+'), ' ');
  for (final phrase in const [
    'Permission is hereby granted, free of charge',
    'without restriction',
    // The licence's ONE condition. Without it this is a bare grant with no
    // attribution requirement and is no longer MIT — and nothing checked it
    // (#104).
    'The above copyright notice and this permission notice shall be included',
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
/// The README must carry a Release section that names the tag flow, the
/// version-code rule, all five secrets and the never-re-tag rule.
///
/// #20's seventh acceptance criterion asked for this section, it was reported
/// done, and it did not exist — because nothing asserted it (#132). A docs
/// criterion with no rule is only as strong as the author's memory of having
/// met it.
List<String> readmeReleaseOffenders(String readme) {
  final offenders = <String>[];
  // Sliced by index rather than with a `(?=^## |\Z)` lookahead: Dart's RegExp
  // has no `\Z`, so that escape matched a literal `Z` and the section was only
  // ever found when another `## ` heading happened to follow it.
  final heading = RegExp(
    r'^## Release[ \t]*$',
    multiLine: true,
  ).firstMatch(readme);
  if (heading == null) {
    return ['README.md: no `## Release` section'];
  }
  final rest = readme.substring(heading.end);
  final next = RegExp(r'^## ', multiLine: true).firstMatch(rest);
  final body = next == null ? rest : rest.substring(0, next.start);

  for (final secret in const [
    'HS_KEYSTORE_B64',
    'HS_KEYSTORE_PASS',
    'HS_KEY_ALIAS',
    'HS_KEY_PASS',
    'PLAY_SERVICE_ACCOUNT_JSON',
  ]) {
    if (!body.contains(secret)) {
      offenders.add('README.md: the Release section does not name $secret');
    }
  }
  if (!RegExp(r'never re-?tag', caseSensitive: false).hasMatch(body)) {
    offenders.add(
      'README.md: the Release section does not say never to re-tag a version',
    );
  }
  if (!body.contains('release.yml')) {
    offenders.add(
      'README.md: the Release section does not name the release workflow',
    );
  }
  if (!body.contains('ci_version.sh')) {
    offenders.add(
      'README.md: the Release section does not state the version-code rule',
    );
  }
  if (!RegExp(r'v\d+\.\d+\.\d+').hasMatch(body)) {
    offenders.add(
      'README.md: the Release section shows no `v<major>.<minor>.<patch>` tag',
    );
  }
  return offenders;
}

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
  // "trade mark" is the British spelling and means the same thing (#102).
  if (!RegExp(r'trade ?marks?', caseSensitive: false).hasMatch(readme)) {
    offenders.add(
      'README.md: the License section no longer states that a copyright '
      'licence grants no trademark rights',
    );
  }
  return offenders;
}
