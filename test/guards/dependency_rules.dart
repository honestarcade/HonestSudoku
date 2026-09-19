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

    // Package names sit at exactly two spaces of indent: `  http:`.
    final match = RegExp(r'^  ([A-Za-z0-9_]+):\s*$').firstMatch(line);
    if (match == null) continue;
    final name = match.group(1)!;
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
  final offenders = <Offender>[];
  final lines = pubspecText.split('\n');

  for (var i = 0; i < lines.length; i++) {
    if (RegExp(r'^dependency_overrides:\s*$').hasMatch(lines[i])) {
      offenders.add(
        Offender(
          'pubspec.yaml:${i + 1}',
          'dependency_overrides',
          'overrides can swap any package silently — not allowed',
        ),
      );
    }
  }

  for (final section in ['dependencies', 'dev_dependencies']) {
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

List<_Entry> _sectionEntries(String pubspecText, String section) {
  final entries = <_Entry>[];
  final lines = pubspecText.split('\n');
  var inSection = false;
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    if (RegExp('^$section:\\s*\$').hasMatch(line)) {
      inSection = true;
      continue;
    }
    if (inSection &&
        line.trim().isNotEmpty &&
        !line.startsWith(' ') &&
        !line.startsWith('#')) {
      inSection = false;
    }
    if (!inSection) continue;
    // Dependency keys sit at exactly two spaces; anything deeper belongs to a
    // multi-line entry whose key line was already seen.
    final match = RegExp(r'^  ([A-Za-z0-9_]+):').firstMatch(line);
    if (match != null) {
      entries.add(_Entry(match.group(1)!, line, i + 1));
    }
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
