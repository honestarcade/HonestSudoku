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

/// Strips a byte-order mark and every carriage return before any rule reads.
///
/// This is not tidiness. Dart's `.` excludes `\r` and its non-multiline `$`
/// anchors before it, so under CRLF **every** top-level line failed to match
/// and the whole justification rule went silent: no `# why:` check, no
/// `dependency_overrides` refusal, and a direct dependency relabelled
/// transitive. `flutter pub get` installs such a pubspec happily, and a
/// Windows clone with `core.autocrlf=true` produces one by accident (#96).
///
/// `.gitattributes` normalises the file in the working tree; this normalises
/// it in the rules, because a guard whose correctness depends on line endings
/// is not a guard.
String normaliseText(String text) {
  var out = text;
  if (out.startsWith('﻿')) out = out.substring(1);
  // TRANSLATE, do not delete. Deleting works for CRLF because the `\n`
  // survives, but a file terminated with lone `\r` — classic Mac endings,
  // still produced by some editors and Git filters — collapsed into a single
  // line, so every rule saw one unparseable string and the whole guard went
  // silent. That is the same failure #96 was filed for, reintroduced by its
  // own fix (#112).
  return out.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
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
  lockText = normaliseText(lockText);
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
  lockText = normaliseText(lockText);
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
  lockText = normaliseText(lockText);
  pubspecText = normaliseText(pubspecText);
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

int _indentOf(String line) => line.length - line.trimLeft().length;

/// Lines inside a dependency section that this rule cannot read as an entry.
///
/// `unreadableDependencySections` refuses a section *header* it cannot parse.
/// It never looked inside, and `_sectionEntries` silently skipped any line it
/// could not match — so YAML's explicit-key form walked straight through:
///
///     dependencies:
///       flutter:
///         sdk: flutter
///       ? path_provider
///       : ^2.1.0
///
/// `flutter pub get` installs that. The guard reported nothing (#96).
///
/// Fail-closed one level down: a non-blank, non-comment line at the section's
/// entry depth that is not a readable `name:` key is an offender in itself.
/// Deeper lines belong to a multi-line entry whose key was already seen, so
/// they are not inspected — `sdk: flutter` under `flutter:` must stay legal.
List<Offender> unreadableSectionEntries(String pubspecText) {
  pubspecText = normaliseText(pubspecText);
  final offenders = <Offender>[];
  final lines = pubspecText.split('\n');

  for (final section in dependencySections) {
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
      if (_topLevelOf(line) != null) {
        inSection = false;
        entryIndent = null;
        continue;
      }
      if (!inSection) continue;
      if (line.trimLeft().startsWith('#')) continue;

      final match = _entryKey.firstMatch(line);
      final indent = _indentOf(line);
      if (match != null && _entryNameOf(match) != null) {
        entryIndent ??= indent;
        continue;
      }
      // Unreadable. Only a line at the entry depth is this rule's business;
      // until the depth is known, the first indented line sets it.
      entryIndent ??= indent;
      if (indent != entryIndent) continue;
      offenders.add(
        Offender(
          'pubspec.yaml:${i + 1}',
          line.trim(),
          'this line sits where a dependency goes and is not a readable '
              '`name:` key — an unreadable shape is refused, never ignored '
              '(invariant 3)',
        ),
      );
    }
  }
  return offenders;
}

/// Third-party dependencies with no `# why:` justification on their key line.
///
/// Reads raw text rather than parsed YAML because the justification lives in a
/// comment, which a parser would discard. A `dependency_overrides:` section is
/// refused outright: it can silently swap any package for another.
List<Offender> unjustifiedDependencies(String pubspecText) {
  pubspecText = normaliseText(pubspecText);
  // Refused first, because a section this rule cannot read would otherwise
  // contribute no entries and so read as a clean section (#86).
  final offenders = <Offender>[
    ...unreadableDependencySections(pubspecText),
    ...unreadableSectionEntries(pubspecText),
  ];
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
/// What must be true of pubspec.yaml before any rule's silence means
/// anything.
///
/// The rules are line scans, and a file they cannot split into lines
/// produces no lines, no matches and no offenders — which reads exactly like
/// a clean pubspec. A lone-`\r` file collapsed into one string and silenced
/// every dependency rule while `path_provider` sat in the lockfile and 190
/// tests passed. normaliseText now translates those endings, and this is the
/// backstop for whatever the next unreadable shape turns out to be: a
/// pubspec that does not look like a pubspec is an offender, not a pass
/// (#96, #112).
///
/// Its own rule, applied to the real file, rather than a prelude inside
/// another rule: the unit fixtures are deliberately small fragments, and
/// folding this in would have failed them all for being short.
List<Offender> pubspecPreconditions(String pubspecText) {
  final text = normaliseText(pubspecText);
  if (text.trim().isEmpty) {
    return [
      const Offender(
        'pubspec.yaml:1',
        '',
        'pubspec.yaml is empty; every dependency rule would report nothing',
      ),
    ];
  }
  final lines = text.split('\n');
  if (lines.length < 5) {
    return [
      Offender(
        'pubspec.yaml:1',
        '${lines.length} line(s)',
        'pubspec.yaml did not split into lines, so every rule below scans '
            'one unparseable string and finds nothing. Check its line '
            'endings',
      ),
    ];
  }
  if (!RegExp(r'^name:\s*\S', multiLine: true).hasMatch(text) ||
      !RegExp(r'^dependencies:\s*$', multiLine: true).hasMatch(text)) {
    return [
      const Offender(
        'pubspec.yaml:1',
        '',
        'pubspec.yaml has no top-level `name:` or no `dependencies:` block, '
            'so the rules cannot locate what they check',
      ),
    ];
  }
  return const [];
}

List<Offender> unreadableDependencySections(String pubspecText) {
  pubspecText = normaliseText(pubspecText);
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

/// The entry names of one dependency section, for guards that care where a
/// package is declared rather than whether it is blocked (#185).
Set<String> sectionNames(String pubspecText, String section) => _sectionEntries(
  normaliseText(pubspecText),
  section,
).map((e) => e.name).toSet();

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
  text = normaliseText(text);
  final offenders = <Offender>[];
  final lines = text.split('\n');

  // Case-insensitive: hosts and scheme.
  final hostPatterns = <String, String>{
    'fonts.googleapis.com': 'web font service — fonts are bundled',
    'fonts.gstatic.com': 'web font service — fonts are bundled',
    'googlefonts.': 'GoogleFonts API — fonts are bundled',
  };

  // The dart:io networking names, listed rather than pattern-matched.
  //
  // #90 made these a suffix match so `SecureSocket` would be caught. It
  // overshot onto `MockSocket`, `FakeHttpClient` and `TestWebSocket` — exactly
  // what a test file is full of — and undershot on `_Socket`, which fell
  // between the lookbehind and the uppercase-prefix branch (#98).
  //
  // Naming the classes is both more precise and easier to read than a rule
  // that tries to infer them. The boundary below allows a leading underscore
  // and forbids a leading alphanumeric, so `_Socket` is caught and
  // `MockSocket` is not.
  final identifiers = <String>[
    'HttpClient',
    'HttpServer',
    'Socket',
    'RawSocket',
    'SecureSocket',
    'RawSecureSocket',
    'ServerSocket',
    'RawServerSocket',
    'SecureServerSocket',
    'WebSocket',
    'RawDatagramSocket',
    'SecurityContext',
    'InternetAddress',
    // #98 listed thirteen. These open connections and were not on it (#118).
    'RawSynchronousSocket',
    'RawSecureServerSocket',
    'WebSocketTransformer',
    'HttpOverrides',
    'IOOverrides',
    'NetworkInterface',
    'ConnectionTask',
  ];

  // lib/links.dart is the one file allowed to hold a URL.
  final allowsHttps = path == 'lib/links.dart';
  // lib/store/ alone reads and writes files: the player's settings, game and
  // statistics (#38, planned with the owner on 2026-09-18 together with
  // path_provider, whose manifest declares no permissions). Everything else
  // in lib/ still may not import dart:io, and the networking names below
  // stay banned in lib/store/ as everywhere.
  final allowsDartIo = path.startsWith('lib/store/');

  // The one a name list cannot catch: `Process.run('curl', [url])`.
  //
  // A name list is a floor. The rule bans class names rather than
  // `import 'dart:io'`, and banning the import in lib/ would be one line and
  // would catch every name above plus the ones nobody has thought of — at
  // the cost of refusing legitimate file IO, which this app does not do yet
  // (#118). Until it does, the import is the honest thing to ban, and this
  // is the line that does it. It applies to lib/ only: the guards
  // themselves, and anything under test/, read files for a living.
  if (path.startsWith('lib/') && !allowsDartIo) {
    for (var i = 0; i < lines.length; i++) {
      if (RegExp('''^\\s*import\\s+['"]dart:io['"]''').hasMatch(lines[i])) {
        offenders.add(
          Offender(
            '$path:${i + 1}',
            "import 'dart:io'",
            'the app imports dart:io, which is how every networking class '
                'above arrives — including ones no name list has. If this '
                'file genuinely needs file IO, that is a conversation about '
                'invariant 1 and a change to this rule, not a local '
                'exception',
          ),
        );
      }
    }
  }

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
      // (?<![A-Za-z0-9]) — not preceded by an alphanumeric, so `MockSocket`
      // and `mySocketName` pass while `_Socket` is caught.
      // (?![A-Za-z0-9_]) — not followed by one, so `WebSocketish` passes.
      //
      // The underscore is allowed before the name but only at the start of
      // an identifier: `_Socket` is a real private dart:io class, and
      // `Test_Socket` and `A_HttpClient` are not — they were flagged,
      // because a leading underscore was permitted anywhere. Same class as
      // the `MockSocket` overshoot this boundary was written to fix, at
      // lower likelihood (#98, #118). `(?<![A-Za-z0-9])` still allows the
      // underscore; `(?<![A-Za-z0-9_][_]?)` would not allow `_Socket`, so
      // the check is explicit instead.
      final pattern = RegExp(
        '(?<![A-Za-z0-9])${RegExp.escape(identifier)}(?![A-Za-z0-9_])',
      );
      final match = pattern.firstMatch(line);
      if (match != null) {
        // An underscore-joined name like `Test_Socket` is not the dart:io
        // class: the character before the underscore continues an
        // identifier, so the whole thing is one name of someone else's
        // choosing (#118).
        final before = match.start - 1;
        final joined =
            before >= 0 &&
            line[before] == '_' &&
            before > 0 &&
            RegExp('[A-Za-z0-9]').hasMatch(line[before - 1]);
        if (!joined) {
          offenders.add(Offender(at, match.group(0)!, 'dart:io networking'));
        }
      }
    }
  }
  return offenders;
}

/// True for files the source rule SCANS: first-party Dart under `lib/`.
///
/// Generated code (`.g.dart`, `.freezed.dart`) and localisations return false
/// — they are the exclusions, not the subject. This docstring described the
/// exact inverse of the body for as long as it stood, and anyone "fixing" a
/// caller to match it would have inverted the invariant-1 source scan (#218).
bool isScannedSourceFile(String relativePath) {
  if (!relativePath.endsWith('.dart')) return false;
  if (relativePath.endsWith('.g.dart')) return false;
  if (relativePath.endsWith('.freezed.dart')) return false;
  if (relativePath.startsWith('lib/l10n/')) return false;
  return relativePath.startsWith('lib/');
}
