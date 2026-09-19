// The dependency-policy rules, as pure functions over strings.
//
// They are pure so that every failure case in #15's test plan becomes a
// permanent unit test with inline fixture text, instead of something an
// executor synthesizes once by hand and then throws away. A rule that has only
// ever been proven against a temporary edit is a rule nobody re-proves.
library;

import 'dependency_policy.dart';

/// One refusal, with enough detail for the failure line to explain itself.
class Offender {
  const Offender(this.where, this.what, this.why);

  /// File and, where it makes sense, line — e.g. `pubspec.yaml:12`.
  final String where;

  /// The package or token refused.
  final String what;

  /// The blocklist entry, pattern, or rule that refused it.
  final String why;

  @override
  String toString() => '$where: $what ($why)';
}

/// Why the lockfile itself cannot be trusted to be there and be whole.
///
/// `lockOffenders` scans the `packages:` section. Given empty text, or text
/// with no `packages:` section, it finds no packages and therefore no
/// offenders — so a truncated, emptied or half-written lockfile reads exactly
/// like a clean one. That is the blocklist failing open, and the blocklist is
/// what stands between this project and an ads SDK (#83).
///
/// The obvious probe for this — delete `pubspec.lock` and run the suite — does
/// not work and is not worth re-deriving: `flutter test` runs an implicit
/// `pub get`, which regenerates the file before a single test loads. Hence a
/// precondition on the content rather than an experiment on the file.
///
/// `minimumPackages` is a floor, not a count: Flutter's own transitive set is
/// far larger, and the number exists to reject a stub, not to pin a version.
List<Offender> lockfilePreconditions(
  String lockText, {
  int minimumPackages = 10,
}) {
  final offenders = <Offender>[];
  if (lockText.trim().isEmpty) {
    offenders.add(
      const Offender(
        'pubspec.lock',
        'empty',
        'an empty lockfile scans clean because there is nothing in it to scan',
      ),
    );
    return offenders;
  }
  if (!RegExp(r'^packages:\s*$', multiLine: true).hasMatch(lockText)) {
    offenders.add(
      const Offender(
        'pubspec.lock',
        'no `packages:` section',
        'the blocklist scans that section and nothing else, so its absence '
            'silences the rule entirely',
      ),
    );
    return offenders;
  }
  final count = lockedPackageNames(lockText).length;
  if (count < minimumPackages) {
    offenders.add(
      Offender(
        'pubspec.lock',
        '$count locked packages',
        'fewer than $minimumPackages — a Flutter app resolves far more than '
            'this, so the lockfile is truncated or half-written',
      ),
    );
  }
  return offenders;
}

/// Every package name in the lockfile's `packages:` section.
Set<String> lockedPackageNames(String lockText) {
  final names = <String>{};
  var inPackages = false;
  int? packageIndent;
  for (final line in lockText.split('\n')) {
    if (RegExp(r'^packages:\s*$').hasMatch(line)) {
      inPackages = true;
      continue;
    }
    if (inPackages && RegExp(r'^[a-z_]+:\s*$').hasMatch(line)) {
      inPackages = false;
    }
    if (!inPackages) continue;
    final match = _entryKey.firstMatch(line);
    if (match == null) continue;
    final name = _entryNameOf(match);
    final indent = match.group(1)!.length;
    if (name == null || indent == 0) continue;
    packageIndent ??= indent;
    if (indent != packageIndent) continue;
    names.add(name);
  }
  return names;
}

/// Blocklisted packages present in the lockfile.
///
/// Scans the `packages:` section only, stopping at `sdks:`, and labels each hit
/// `direct`, `direct dev` or `transitive` by looking the name up in the
/// pubspec. Transitive hits matter as much as direct ones: an ads SDK pulled in
/// by something innocent still ships.
List<Offender> lockOffenders(String lockText, String pubspecText) {
  final offenders = <Offender>[];
  final direct = _directDependencyNames(pubspecText);
  final directDev = _directDependencyNames(pubspecText, dev: true);

  var inPackages = false;
  int? packageIndent;
  final lines = lockText.split('\n');
  for (final line in lines) {
    if (RegExp(r'^packages:\s*$').hasMatch(line)) {
      inPackages = true;
      continue;
    }
    // A lockfile without an `sdks:` section is scanned to the end.
    if (RegExp(r'^[a-z_]+:\s*$').hasMatch(line) && !line.startsWith(' ')) {
      if (inPackages && !RegExp(r'^packages:\s*$').hasMatch(line)) {
        inPackages = false;
      }
    }
    if (!inPackages) continue;

    // The first indented key inside `packages:` sets the package depth, the
    // same way a pubspec section's entry depth is found. Pinning it to exactly
    // two spaces let a quoted or four-space entry escape the blocklist
    // entirely, which is #86's defect wearing a lockfile (#94 review).
    final match = _entryKey.firstMatch(line);
    if (match == null) continue;
    final name = _entryNameOf(match);
    if (name == null) continue;
    final indent = match.group(1)!.length;
    if (indent == 0) continue;
    packageIndent ??= indent;
    if (indent != packageIndent) continue;
    final reason = matches(name);
    if (reason == null) continue;

    final kind = direct.contains(name)
        ? 'direct'
        : directDev.contains(name)
        ? 'direct dev'
        : 'transitive';
    offenders.add(
      Offender(
        'pubspec.lock',
        '$name ($kind)',
        'blocked by "$reason" — invariant 1',
      ),
    );
  }
  return offenders;
}

/// Third-party dependencies with no `# why:` justification on their key line.
///
/// Reads raw text rather than parsed YAML because the justification lives in a
/// comment, which a parser would discard. A `dependency_overrides:` section is
/// refused outright: it can silently swap any package for another.
List<Offender> unjustifiedDependencies(String pubspecText) {
  // Refused first, because a section this rule cannot read would otherwise
  // contribute no entries and so read as a clean section (#86).
  final offenders = <Offender>[...unreadableDependencySections(pubspecText)];
  final lines = pubspecText.split('\n');

  for (var i = 0; i < lines.length; i++) {
    if (_sectionKeyOf(lines[i]) == 'dependency_overrides') {
      offenders.add(
        Offender(
          'pubspec.yaml:${i + 1}',
          'dependency_overrides',
          'overrides can swap any package silently — not allowed',
        ),
      );
    }
  }

  // dependency_overrides is walked for justification as well as refused
  // outright: an override can substitute any package for any other, so it is
  // the last place an unexplained entry belongs (#79).
  for (final section in [
    'dependencies',
    'dev_dependencies',
    'dependency_overrides',
  ]) {
    for (final entry in _sectionEntries(pubspecText, section)) {
      if (exemptFromJustification.contains(entry.name)) continue;
      if (!_hasWhy(entry.line)) {
        offenders.add(
          Offender(
            'pubspec.yaml:${entry.lineNumber}',
            entry.name,
            'no `# why:` justification — invariant 3',
          ),
        );
      }
    }
  }
  return offenders;
}

/// `# why:` followed by at least one non-space character.
bool _hasWhy(String line) => RegExp(r'#\s*why:\s*\S').hasMatch(line);

class _Entry {
  const _Entry(this.name, this.line, this.lineNumber);
  final String name;
  final String line;
  final int lineNumber;
}

/// The dependency sections this rule governs.
const dependencySections = [
  'dependencies',
  'dev_dependencies',
  'dependency_overrides',
];

/// A top-level key line, split into the key and whatever follows the colon.
class _TopLevel {
  const _TopLevel(this.key, this.rest);

  /// The key with any surrounding quotes removed. `"dependencies":` is legal
  /// YAML that `flutter pub get` accepts, and it hid the whole section (#86).
  final String key;

  /// What followed the colon, trailing comment removed and trimmed. Empty
  /// means the line opens a block; anything else is a value on the same line.
  final String rest;
}

_TopLevel? _topLevelOf(String line) {
  if (line.isEmpty || line.startsWith(' ') || line.startsWith('\t')) {
    return null;
  }
  if (line.trimLeft().startsWith('#')) return null;
  final match = RegExp('^(?:"([^"]+)"|\'([^\']+)\'|([A-Za-z0-9_]+))\\s*:(.*)\$')
      .firstMatch(line);
  if (match == null) return null;
  final key = match.group(1) ?? match.group(2) ?? match.group(3)!;
  var rest = match.group(4)!;
  final hash = rest.indexOf('#');
  if (hash != -1) rest = rest.substring(0, hash);
  return _TopLevel(key, rest.trim());
}

/// The section key a line opens, or null if it opens none.
///
/// A line only opens a section when nothing follows the colon. A trailing
/// comment does not count as something following it: `dependencies: # app deps`
/// is valid YAML, and matching against the whole line made every dependency
/// beneath it invisible (#79).
String? _sectionKeyOf(String line) {
  final top = _topLevelOf(line);
  if (top == null || top.rest.isNotEmpty) return null;
  return top.key;
}

/// A key line shaped `<name>:`, quoted or not, with its indent.
final _entryKey = RegExp(
  '^(\\s*)(?:"([^"]+)"|\'([^\']+)\'|([A-Za-z0-9_]+))\\s*:',
);

String? _entryNameOf(RegExpMatch match) =>
    match.group(2) ?? match.group(3) ?? match.group(4);

/// Dependency sections written in a shape this rule cannot read.
///
/// This is the rule that matters, and it is the one three passes at #79 and
/// #86 were missing. Every previous fix taught the parser one more spelling of
/// YAML, and every time another legal spelling turned up that the rule saw as
/// nothing at all:
///
///     dependencies: {path_provider: ^2.1.0}    # flow mapping
///     dependencies: &deps                      # anchor
///     dependencies: *deps                      # alias
///
/// `flutter pub get --enforce-lockfile` accepts all three. So rather than
/// recognising them one at a time, anything that is not a plain block opener
/// is refused **because** the rule cannot read it. "I cannot read this" must
/// never render as "there is nothing here" — that is the whole defect class.
List<Offender> unreadableDependencySections(String pubspecText) {
  final offenders = <Offender>[];
  final lines = pubspecText.split('\n');
  for (var i = 0; i < lines.length; i++) {
    final top = _topLevelOf(lines[i]);
    if (top == null) continue;
    if (!dependencySections.contains(top.key)) continue;
    if (top.rest.isEmpty) continue;
    offenders.add(
      Offender(
        'pubspec.yaml:${i + 1}',
        '${top.key}: ${top.rest}',
        'this section is not written as a plain block, so the justification '
            'rule cannot read it — an unreadable shape is refused, never '
            'ignored (invariant 3)',
      ),
    );
  }
  return offenders;
}

List<_Entry> _sectionEntries(String pubspecText, String section) {
  final entries = <_Entry>[];
  final lines = pubspecText.split('\n');
  var inSection = false;
  int? entryIndent;
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    if (line.trim().isEmpty) continue;

    final key = _sectionKeyOf(line);
    if (key != null) {
      inSection = key == section;
      entryIndent = null;
      continue;
    }
    // A top-level line that is not a block opener still ends the section.
    if (_topLevelOf(line) != null) {
      inSection = false;
      entryIndent = null;
      continue;
    }
    if (!inSection) continue;
    if (line.trimLeft().startsWith('#')) continue;

    // The first indented key sets this section's entry depth; anything deeper
    // belongs to a multi-line entry whose key line was already seen. Two
    // spaces is the convention, not the rule — four-space pubspecs are legal
    // and used to escape this scan entirely (#79).
    final match = _entryKey.firstMatch(line);
    if (match == null) continue;
    final name = _entryNameOf(match);
    if (name == null) continue;
    final indent = match.group(1)!.length;
    entryIndent ??= indent;
    if (indent != entryIndent) continue;
    entries.add(_Entry(name, line, i + 1));
  }
  return entries;
}

Set<String> _directDependencyNames(String pubspecText, {bool dev = false}) =>
    _sectionEntries(
      pubspecText,
      dev ? 'dev_dependencies' : 'dependencies',
    ).map((e) => e.name).toSet();

/// Forbidden references in one source file.
///
/// Scanned as raw text, comments included: a commented-out socket is a plan to
/// use one, and this guard would rather be loud than clever.
List<Offender> sourceOffenders(String path, String text) {
  final offenders = <Offender>[];
  final lines = text.split('\n');

  // Case-insensitive: hosts and scheme.
  final hostPatterns = <String, String>{
    'fonts.googleapis.com': 'web font service — fonts are bundled',
    'fonts.gstatic.com': 'web font service — fonts are bundled',
    'googlefonts.': 'GoogleFonts API — fonts are bundled',
  };

  // Case-sensitive identifiers, whole word: dart:io networking.
  final identifiers = <String>[
    'HttpClient',
    'Socket',
    'WebSocket',
    'RawDatagramSocket',
    'SecurityContext',
  ];

  // lib/links.dart is the one file allowed to hold a URL.
  final allowsHttps = path == 'lib/links.dart';

  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    final lower = line.toLowerCase();
    final at = '$path:${i + 1}';

    for (final pattern in hostPatterns.entries) {
      if (lower.contains(pattern.key)) {
        offenders.add(Offender(at, pattern.key, pattern.value));
      }
    }
    if (lower.contains('http://')) {
      offenders.add(Offender(at, 'http://', 'the app makes no network calls'));
    }
    if (!allowsHttps && lower.contains('https://')) {
      offenders.add(
        Offender(at, 'https://', 'URLs live only in lib/links.dart'),
      );
    }
    for (final identifier in identifiers) {
      if (RegExp('\\b${RegExp.escape(identifier)}\\b').hasMatch(line)) {
        offenders.add(Offender(at, identifier, 'dart:io networking'));
      }
    }
  }
  return offenders;
}

/// True for files the source rule skips: generated code and localisations.
bool isScannedSourceFile(String relativePath) {
  if (!relativePath.endsWith('.dart')) return false;
  if (relativePath.endsWith('.g.dart')) return false;
  if (relativePath.endsWith('.freezed.dart')) return false;
  if (relativePath.startsWith('lib/l10n/')) return false;
  return relativePath.startsWith('lib/');
}
