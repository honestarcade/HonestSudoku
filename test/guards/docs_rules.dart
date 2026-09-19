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
      'docs/privacy.md: no longer claims the app has no network '
      'access',
    );
  }
  return offenders;
}

/// The site root must link the policy, or the published policy is unreachable.
List<String> siteIndexOffenders(String indexMd) => indexMd.contains('privacy')
    ? const []
    : const ['docs/index.md: does not link the privacy policy'];

/// MIT, naming the studio.
List<String> licenceOffenders(String licence) {
  final offenders = <String>[];
  if (!licence.contains('MIT License')) {
    offenders.add('LICENSE: not an MIT licence');
  }
  if (!licence.contains('Honest Arcade')) {
    offenders.add('LICENSE: does not name Honest Arcade');
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
  if (RegExp(r'-d\s+chrome').hasMatch(readme)) {
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
