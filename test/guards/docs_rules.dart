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
/// Text that Jekyll will not publish: fenced code and HTML comments.
///
/// A link inside either satisfied the rule while the rendered page carried no
/// link at all — reproduced on the real `docs/index.md` by moving its only
/// link into a fenced block, with the suite green (#110).
String _renderedOnly(String markdown) => markdown
    .replaceAll(RegExp(r'^```[\s\S]*?^```', multiLine: true), '')
    .replaceAll(RegExp(r'^~~~[\s\S]*?^~~~', multiLine: true), '')
    .replaceAll(RegExp(r'<!--[\s\S]*?-->'), '')
    .replaceAll(RegExp(r'`[^`\n]*`'), '');

/// Whether a path, once the project prefix is accounted for, is the policy.
///
/// [hasPrefix] says whether the path is expected to carry `/HonestSudoku`
/// itself, which is true for a root-absolute path and false for one Jekyll
/// will prefix.
bool _isPolicyPath(String path, {required bool hasPrefix}) {
  // A fragment or a query string does not change which page is served, and
  // both were refused. Curled: /privacy#section and /privacy?utm=x are 200.
  var p = path.split('#').first.split('?').first.trim();
  if (hasPrefix) {
    if (!p.startsWith('/HonestSudoku/')) return false;
    p = p.substring('/HonestSudoku'.length);
  }
  p = p.replaceFirst(RegExp(r'^\./'), '');
  p = p.replaceFirst(RegExp(r'^/'), '');
  // `privacy.md` is the SOURCE extension; Jekyll serves privacy.html. A
  // trailing slash 404s too. Both are refused by name, and a negative
  // fixture blessed each of them in turn (#101, #110).
  return p == 'privacy' || p == 'privacy.html';
}

/// Whether one link destination reaches the published privacy policy.
///
/// Enumerated rather than normalised. The previous rule guessed at URL
/// resolution from the source text and got it wrong in both directions: it
/// blessed `privacy.md` and `privacy/` (both 404), accepted a link to a
/// FOREIGN host because it compared only the path, and refused six spellings
/// that return 200 — including `absolute_url`, which it told the author
/// resolves to a 404 while the live URL returns 200.
///
/// Every form below was curled against the live site on 2026-09-20:
///
///     /privacy         200      /privacy.md      404
///     /privacy.html    200      /privacy/        404
///     /privacy#section 200      bare /privacy    404
///     /privacy?utm=x   200
bool _reachesPolicy(String raw) {
  var dest = raw.trim();
  if (dest.isEmpty) return false;
  // CommonMark pointy brackets.
  if (dest.startsWith('<') && dest.endsWith('>')) {
    dest = dest.substring(1, dest.length - 1).trim();
  }

  // An absolute URL must match HOST and path. Comparing only the path let
  // `https://evil.example.com/HonestSudoku/privacy` pass (#110).
  final absolute = RegExp(r'^https?://([^/]+)(/.*)?$').firstMatch(dest);
  if (absolute != null) {
    if (absolute.group(1) != 'honestarcade.github.io') return false;
    return _isPolicyPath(absolute.group(2) ?? '', hasPrefix: true);
  }

  // Liquid. `relative_url` and `absolute_url` both prepend site.baseurl, and
  // `absolute_url` prepends site.url as well, so both resolve; the filtered
  // value is what matters.
  final filter = RegExp(
    r'''\{\{\s*['"]([^'"]+)['"]\s*\|\s*(relative_url|absolute_url)\s*\}\}''',
  ).firstMatch(dest);
  if (filter != null) {
    return _isPolicyPath(filter.group(1)!, hasPrefix: false);
  }

  // `{{ site.baseurl }}/privacy`, with or without `{{ site.url }}` in front.
  final baseurl = RegExp(r'\{\{\s*site\.baseurl\s*\}\}');
  if (baseurl.hasMatch(dest)) {
    final rest = dest
        .replaceAll(RegExp(r'\{\{\s*site\.url\s*\}\}'), '')
        .replaceAll(baseurl, '');
    if (rest.contains('{{')) return false;
    return _isPolicyPath(rest, hasPrefix: false);
  }

  // Anything with Liquid left in it is not something this rule can resolve.
  if (dest.contains('{{')) return false;

  // A bare root-absolute path. This is a PROJECT page under /HonestSudoku/,
  // so `/privacy` really does 404 — curled.
  if (dest.startsWith('/')) return _isPolicyPath(dest, hasPrefix: true);
  return _isPolicyPath(dest, hasPrefix: false);
}

List<String> siteIndexOffenders(String indexMd) {
  final rendered = _renderedOnly(indexMd);
  final destinations = <String>[];
  // [text](dest) and [text](dest "title"). The destination may contain spaces
  // when it is a Liquid expression, so this matches to the closing paren and
  // strips a trailing title rather than forbidding whitespace.
  for (final m in RegExp(r'\]\(([^)]*)\)').allMatches(rendered)) {
    destinations.add(m.group(1)!.replaceAll(RegExp(r'\s+"[^"]*"$'), ''));
  }
  // [ref]: dest
  for (final m in RegExp(
    r'^\s*\[[^\]]+\]:\s*(\S+)',
    multiLine: true,
  ).allMatches(rendered)) {
    destinations.add(m.group(1)!);
  }
  // <a href="dest">
  for (final m in RegExp(
    '<a[^>]+href=["\']([^"\']+)["\']',
  ).allMatches(rendered)) {
    destinations.add(m.group(1)!);
  }

  if (destinations.any(_reachesPolicy)) return const [];

  // Name the near-misses, because "no link" is unhelpful when there is a
  // link that is one character wrong.
  final nearMisses = destinations
      .map((d) => d.trim())
      .where(
        (d) =>
            d.toLowerCase().contains('privacy') ||
            d.toLowerCase().contains('policy'),
      )
      .toList();
  if (nearMisses.isEmpty) {
    return const [
      'docs/index.md: no link that resolves to the privacy policy — the site '
          'root is how a reviewer reaches it. A link inside a code fence or '
          'an HTML comment does not count; it is not published.',
    ];
  }
  return [
    'docs/index.md: no link that RESOLVES to the privacy policy. Found '
        '${nearMisses.map((d) => '`$d`').join(', ')}. This is a GitHub Pages '
        'PROJECT page served under /HonestSudoku/, and these were curled on '
        '2026-09-20: `privacy` 200, `privacy.html` 200, `privacy.md` 404 '
        '(the source extension is not served), `privacy/` 404, bare '
        '`/privacy` 404 (it resolves to honestarcade.github.io/privacy). '
        'Write `privacy`.',
  ];
}

/// MIT, naming the studio.
/// The canonical MIT body, from the header line to the end, with the
/// copyright line removed. Whitespace-normalised on both sides before
/// comparison, so re-wrapping is fine and a word is not.
const _mitBody =
    'MIT License '
    'Permission is hereby granted, free of charge, to any person obtaining a '
    'copy of this software and associated documentation files (the '
    '"Software"), to deal in the Software without restriction, including '
    'without limitation the rights to use, copy, modify, merge, publish, '
    'distribute, sublicense, and/or sell copies of the Software, and to '
    'permit persons to whom the Software is furnished to do so, subject to '
    'the following conditions: '
    'The above copyright notice and this permission notice shall be included '
    'in all copies or substantial portions of the Software. '
    'THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS '
    'OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF '
    'MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. '
    'IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY '
    'CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, '
    'TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE '
    'SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.';

List<String> licenceOffenders(String licence) {
  final offenders = <String>[];
  if (!licence.contains('Honest Arcade')) {
    offenders.add('LICENSE: does not name Honest Arcade');
  }
  // A year range and either spelling of the symbol are ordinary ways to
  // write this notice; refusing them was a false alarm (#102).
  final copyright = RegExp(
    r'Copyright\s+(\((c|C)\)|©)\s*\d{4}(\s*[-–]\s*\d{4})?\s+Honest Arcade',
  );
  if (!copyright.hasMatch(licence)) {
    offenders.add('LICENSE: no `Copyright (c) <year> Honest Arcade` line');
  }

  // EQUALITY, not four substrings. The substring form asked whether certain
  // phrases appear, and a licence can contain all four while saying the
  // opposite around them: "THIS IS NOT AN MIT LICENCE. Commercial use ... is
  // PROHIBITED", followed by a paragraph quoting each required phrase inside
  // a disclaimer, passed every check (#89, #104, #111).
  //
  // MIT is a fixed text, so the check that cannot be talked around is
  // whether this IS that text. Whitespace is normalised, so re-wrapping the
  // file is fine; adding a sentence is not.
  final body = licence
      .replaceAll(copyright, '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  if (body != _mitBody) {
    // Name the first divergence rather than printing two licences.
    var i = 0;
    while (i < body.length && i < _mitBody.length && body[i] == _mitBody[i]) {
      i++;
    }
    final at = i > 40 ? i - 40 : 0;
    offenders.add(
      'LICENSE: the body is not the MIT text. It first differs at character '
      '$i:\n'
      '  expected: ...${_mitBody.substring(at, (i + 40).clamp(0, _mitBody.length))}\n'
      '  found:    ...${body.substring(at, (i + 40).clamp(0, body.length))}',
    );
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
