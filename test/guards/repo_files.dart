// Shared helpers for the guard tests in this directory.
//
// Guards read the repository's own files as text and assert facts about them.
// They add no dependencies: a guard that needed a YAML or XML package could be
// satisfied by a build that removed the package, which is the opposite of the
// point. Comment stripping is therefore hand-rolled and deliberately simple.
import 'dart:convert';
import 'dart:io';

/// The repository root, asserted rather than assumed.
///
/// Every guard resolves paths from here. Tests run with the package root as the
/// current directory; if `pubspec.yaml` is not there we are somewhere
/// unexpected and failing loudly beats reading the wrong files.
Directory get repoRoot {
  final dir = Directory.current;
  final pubspec = File('${dir.path}/pubspec.yaml');
  if (!pubspec.existsSync()) {
    throw StateError(
      'guard: expected pubspec.yaml in ${dir.path} — guards resolve every path '
      'from the repository root and cannot run from anywhere else',
    );
  }
  return dir;
}

/// Reads a repository-relative file. A missing file is a hard failure, never a
/// skip: a guard that silently passes because its subject vanished is worse
/// than no guard.
String readFile(String relativePath) {
  final file = File('${repoRoot.path}/$relativePath');
  if (!file.existsSync()) {
    throw StateError('guard: missing file $relativePath');
  }
  return file.readAsStringSync();
}

/// True when a repository-relative path exists as a file or a directory.
bool pathExists(String relativePath) {
  final full = '${repoRoot.path}/$relativePath';
  return File(full).existsSync() || Directory(full).existsSync();
}

/// Removes `<!-- ... -->` comments, so a commented-out XML element is not
/// treated as an offender.
String stripXmlComments(String source) =>
    source.replaceAll(RegExp(r'<!--.*?-->', dotAll: true), '');

/// Removes `#` comments from YAML, leaving `#` inside single or double quotes
/// alone — `name: "a#b"` is a value, not a comment.
String stripYamlComments(String source) {
  final out = StringBuffer();
  for (final line in const LineSplitter().convert(source)) {
    out.writeln(_stripYamlCommentFromLine(line));
  }
  return out.toString();
}

String _stripYamlCommentFromLine(String line) {
  var single = false;
  var double = false;
  for (var i = 0; i < line.length; i++) {
    final ch = line[i];
    if (ch == "'" && !double) {
      single = !single;
    } else if (ch == '"' && !single) {
      double = !double;
    } else if (ch == '#' && !single && !double) {
      return line.substring(0, i).trimRight();
    }
  }
  return line;
}

/// Every file under [relativeDir] that exists on disk, tracked or not.
///
/// Use this where the rule is about what a build would *see*, rather than
/// about what the repository holds. `git ls-files` is blind to an untracked
/// file, so a locally created manifest could carry a removal rule the guard
/// never read (#105).
List<String> filesUnder(String relativeDir) {
  final dir = Directory('${repoRoot.path}/$relativeDir');
  if (!dir.existsSync()) return const [];
  return dir
      .listSync(recursive: true)
      .whereType<File>()
      .map((f) => f.path.substring(repoRoot.path.length + 1))
      .toList()
    ..sort();
}

/// Every tracked file under [relativeDir], via git, so untracked build output
/// (`.gradle/`, `local.properties`, wrapper jars) is skipped by construction
/// rather than by an exclusion list that would rot.
List<String> trackedFilesUnder(String relativeDir) {
  final result = Process.runSync('git', [
    'ls-files',
    relativeDir,
  ], workingDirectory: repoRoot.path);
  if (result.exitCode != 0) {
    throw StateError(
      'guard: git ls-files $relativeDir failed: ${result.stderr}',
    );
  }
  return const LineSplitter()
      .convert(result.stdout as String)
      .where((line) => line.trim().isNotEmpty)
      .toList();
}

/// Builds the one-line-per-offender failure reason every guard uses:
/// `<rule> <path>: <offender>`.
String describeOffenders(String rule, List<String> offenders) =>
    '$rule: ${offenders.length} offender(s)\n${offenders.map((o) => '  $rule $o').join('\n')}';
