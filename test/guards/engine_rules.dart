// The rules behind engine_imports_test.dart, as pure functions so each one is
// exercised against an inline fixture as well as against the real engine.
//
// The engine runs in a background isolate and in plain tests, so it may use
// only core Dart libraries and `package:meta` (which ships with the SDK and
// carries `@visibleForTesting`). A relative import that leaves `lib/engine/`
// is a way round the list — the file it reaches could import anything — so
// that is refused as well.

import 'repo_files.dart';

/// The libraries the engine may import.
const engineAllowedLibraries = {
  'dart:core',
  'dart:collection',
  'dart:math',
  'dart:typed_data',
  'dart:async',
  'dart:isolate',
};

/// `package:meta` is allowed; any other package — this app's own included —
/// is not.
const engineAllowedPackage = 'package:meta/';

final _directive = RegExp(
  r'''^\s*(?:import|export|part)\b([^;]*);''',
  multiLine: true,
);
final _quoted = RegExp(r'''(?:'([^']*)'|"([^"]*)")''');

/// Every URI a Dart source's `import`, `export` and `part` directives name,
/// including each branch of a conditional import. Comments are stripped
/// first.
List<String> directiveUris(String source) => [
  for (final d in _directive.allMatches(stripDartComments(source)))
    for (final q in _quoted.allMatches(d.group(1)!)) q.group(1) ?? q.group(2)!,
];

/// Offending URIs in the engine file at [path] (repository-relative, under
/// `lib/engine/`).
List<String> engineImportOffenders(String path, String source) =>
    importOffenders(
      path,
      source,
      folder: 'engine',
      libraries: engineAllowedLibraries,
      packages: const [engineAllowedPackage],
    );

/// Offending URIs in the file at [path] under `lib/<folder>/`: a `dart:`
/// library not in [libraries], a `package:` URI not starting with one of
/// [packages], any other scheme, or a relative import that leaves the
/// folder.
List<String> importOffenders(
  String path,
  String source, {
  required String folder,
  required Set<String> libraries,
  required List<String> packages,
}) {
  final offenders = <String>[];
  for (final uri in directiveUris(source)) {
    if (uri.startsWith('dart:')) {
      if (!libraries.contains(uri)) offenders.add('$path: $uri');
    } else if (uri.startsWith('package:')) {
      if (!packages.any(uri.startsWith)) offenders.add('$path: $uri');
    } else if (uri.contains(':')) {
      offenders.add('$path: $uri');
    } else if (!_staysIn(folder, path, uri)) {
      offenders.add('$path: $uri (leaves lib/$folder/)');
    }
  }
  return offenders;
}

bool _staysIn(String folder, String path, String uri) {
  final parts = path.split('/')..removeLast();
  for (final segment in uri.split('/')) {
    if (segment == '..') {
      if (parts.isEmpty) return false;
      parts.removeLast();
    } else if (segment != '.' && segment.isNotEmpty) {
      parts.add(segment);
    }
  }
  return parts.length >= 3 && parts[0] == 'lib' && parts[1] == folder;
}

final _random = RegExp(r'\bRandom\b');

/// Lines of [source] that reference `dart:math`'s `Random`, comments
/// stripped. The engine's PRNG is seeded and hand-rolled; an unseeded
/// `Random` would break determinism (invariant 4).
List<String> engineRandomOffenders(String path, String source) {
  final lines = stripDartComments(source).split('\n');
  return [
    for (var i = 0; i < lines.length; i++)
      if (_random.hasMatch(lines[i])) '$path:${i + 1}: ${lines[i].trim()}',
  ];
}

/// Clock and timer forms the engine may not use: generation must depend on
/// the seed alone (invariant 4). Only the off-thread wrapper, which enforces
/// the time ceiling, may use them — and never `Random`.
const engineClockForms = [
  'DateTime.now(',
  'Stopwatch(',
  'Timer(',
  'Timer.periodic(',
  'Future.delayed',
  '.timeout(',
];

/// The one engine file allowed [engineClockForms].
const engineClockAllowed = 'lib/engine/isolate_generator.dart';

/// Lines of [source] using a clock or timer form, comments stripped. Empty
/// for [engineClockAllowed].
List<String> engineClockOffenders(String path, String source) {
  if (path == engineClockAllowed) return const [];
  final lines = stripDartComments(source).split('\n');
  return [
    for (var i = 0; i < lines.length; i++)
      for (final form in engineClockForms)
        if (lines[i].contains(form)) '$path:${i + 1}: $form',
  ];
}
