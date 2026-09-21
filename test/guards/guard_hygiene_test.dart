@Tags(['guard'])
library;

// Properties of the guard suite itself.
//
// Two passes in a row spliced a test in and left its predecessor behind, so
// the same test name was defined twice. Neither duplicate failed — they
// agreed with their replacements — and the first was found only because an
// unrelated mutation reported WRONG-REASON and printed the same reason twice
// (#221). A duplicate that agrees with what it duplicates is invisible until
// the two disagree, at which point the failure is confusing rather than
// informative.
//
// So the property is asserted rather than left to whoever notices.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'repo_files.dart';

void main() {
  test('no guard file declares the same test name twice', () {
    // WITHIN a file, not across files. Two files may each declare
    // `the script exists and is executable` — the suites are separate and a
    // reported failure carries the path, so there is no ambiguity. Within one
    // file there is: two declarations, one name, and no way to tell from a
    // failure which body ran.
    final duplicated = <String>[];
    final files =
        Directory('${repoRoot.path}/test/guards')
            .listSync()
            .whereType<File>()
            .where((f) => f.path.endsWith('_test.dart'))
            .toList()
          ..sort((a, b) => a.path.compareTo(b.path));

    expect(
      files,
      isNotEmpty,
      reason: 'hygiene: no guard test files found, so this asserts nothing',
    );

    // `test('…'` and `group('…'`, single- or double-quoted. A name built from
    // a variable is skipped rather than guessed at: this rule exists to catch
    // an accidental copy, and an accidental copy is a literal.
    final declaration = RegExp(
      '''^\\s*(?:test|group)\\(\\s*(?:'([^']*)'|"([^"]*)")''',
      multiLine: true,
    );

    for (final file in files) {
      final relative = file.path.substring(repoRoot.path.length + 1);
      final seen = <String, int>{};
      for (final match in declaration.allMatches(file.readAsStringSync())) {
        final name = match.group(1) ?? match.group(2)!;
        seen[name] = (seen[name] ?? 0) + 1;
      }
      for (final entry in seen.entries) {
        if (entry.value > 1) {
          duplicated.add('$relative declares `${entry.key}` ${entry.value}x');
        }
      }
    }

    expect(
      duplicated,
      isEmpty,
      reason:
          'hygiene: a file declares the same test name more than once. A '
          'duplicate that agrees with what it duplicates passes, so it is '
          'invisible until the two disagree — and then the failure names a '
          'test you cannot find:\n${duplicated.join('\n')}',
    );
  });

  test('the repository root holds only the files it is meant to', () {
    // A CLOSED list, not a pattern. The first version of this test matched
    // probe-shaped NAMES — `leak`, `debug`, `probe`, `tmp`, `scratch` — and
    // caught `hs-leak-probe.txt`, the artefact that prompted it. It then
    // missed `hs-workspace-leak.txt`, committed by the very next pass, for
    // the sole reason that `workspace` was not a word I had thought of.
    //
    // That file mattered: it held a fixture password, and being TRACKED took
    // it out of the workspace leak scan, which is the second time debugging
    // debris blinded that guard (#213). Subtracting modified files did not
    // help, because the mutation writes the same bytes the commit contains.
    //
    // The root is small and changes rarely, so enumerate it. Anything new
    // must be added here deliberately — which is the whole point, since
    // everything that went wrong here arrived by `git add -A`.
    const expected = {
      '.fvmrc',
      '.gitattributes',
      '.gitignore',
      '.metadata',
      'analysis_options.yaml',
      'CLAUDE.md',
      'dart_test.yaml',
      'LICENSE',
      'pubspec.lock',
      'pubspec.yaml',
      'README.md',
      'SECURITY.md',
    };

    // chokepoint-exempt: lists tracked paths to compare against the set
    // above; passes no secret and its output is a list of file names.
    final tracked = Process.runSync(
      'git',
      ['ls-files'],
      workingDirectory: repoRoot.path,
      stdoutEncoding: systemEncoding,
    ).stdout.toString().split('\n');

    final atRoot = {
      for (final path in tracked)
        if (path.isNotEmpty && !path.contains('/')) path,
    };

    expect(
      atRoot,
      expected,
      reason:
          'hygiene: the set of tracked files at the repository root has '
          'changed. A file that arrives here unannounced is usually debris '
          'from a debugging session, and a TRACKED file is skipped by the '
          'workspace leak scan — so committing one blinds that guard for its '
          'path (#213). If the new file belongs, add it to this list',
    );
  });
}
