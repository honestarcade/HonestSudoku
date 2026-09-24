// Shared helpers for the guard tests in this directory.
//
// Guards read the repository's own files and assert facts about them.
//
// This header used to say guards add no dependencies, on the reasoning that a
// guard needing a YAML package could be satisfied by a build that removed the
// package. #154 reversed that for workflows and the reversal won: a line scan
// cannot assert STRUCTURE, and every bypass it missed — a flow mapping, a
// quoted scalar, a value on the next line — was a real hole rather than a
// theoretical one. `package:yaml` is a dev dependency, so it is not in the
// shipped bundle, and a test asserts that. The argument is set out in full in
// workflow_yaml.dart's header; this file's hand-rolled helpers remain for the
// formats that have no parser here (#154, #180).
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

/// Removes `//` and `/* */` comments from Dart source, leaving string
/// literals — single, double, triple-quoted and raw — alone, so a URI or a
/// name inside a string is still seen and one inside a comment is not.
///
/// Block comments nest, as Dart's do. Line breaks are kept so offsets into
/// the result still fall on the source's lines.
String stripDartComments(String source) {
  final out = StringBuffer();
  var i = 0;
  final n = source.length;
  while (i < n) {
    final ch = source[i];
    final next = i + 1 < n ? source[i + 1] : '';
    if (ch == '/' && next == '/') {
      while (i < n && source[i] != '\n') {
        i++;
      }
      continue;
    }
    if (ch == '/' && next == '*') {
      var depth = 1;
      i += 2;
      while (i < n && depth > 0) {
        if (source.startsWith('/*', i)) {
          depth++;
          i += 2;
        } else if (source.startsWith('*/', i)) {
          depth--;
          i += 2;
        } else {
          if (source[i] == '\n') out.write('\n');
          i++;
        }
      }
      continue;
    }
    if (ch == "'" || ch == '"') {
      final raw = i > 0 && source[i - 1] == 'r';
      final triple = source.startsWith(ch * 3, i);
      final quote = triple ? ch * 3 : ch;
      out.write(quote);
      i += quote.length;
      while (i < n && !source.startsWith(quote, i)) {
        if (!raw && source[i] == r'\' && i + 1 < n) {
          out.write(source.substring(i, i + 2));
          i += 2;
          continue;
        }
        if (!triple && source[i] == '\n') break;
        out.write(source[i]);
        i++;
      }
      if (i < n && source.startsWith(quote, i)) {
        out.write(quote);
        i += quote.length;
      }
      continue;
    }
    out.write(ch);
    i++;
  }
  return out.toString();
}
