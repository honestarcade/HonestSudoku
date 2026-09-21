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

  test('no test file writes into the repository it reads', () {
    // `hs-leak-probe.txt`, a 0-byte artefact from a debugging session, was
    // committed to `main` by a `git add -A`. Being TRACKED then put it in the
    // leak scan's skip set, so a secret written to that path was never read —
    // the guard was blinded by its own debris (#213).
    //
    // The general rule is cheap: nothing at the repository root should be
    // untracked-and-unignored after a suite run, and no file matching a
    // probe-shaped name should be tracked at all.
    final tracked = Process.runSync(
      'git',
      ['ls-files'],
      workingDirectory: repoRoot.path,
      stdoutEncoding: systemEncoding,
    ).stdout.toString().split('\n');

    final debris = tracked
        .where(
          (p) =>
              RegExp(r'(^|/)(hs-)?(leak|debug|probe|tmp|scratch)[-_.][^/]*$')
                  .hasMatch(p),
        )
        .toList();

    expect(
      debris,
      isEmpty,
      reason:
          'hygiene: these look like debugging artefacts and they are TRACKED. '
          'A tracked file is skipped by the workspace leak scan, so committed '
          'debris can blind a guard (#213):\n${debris.join('\n')}',
    );
  });
}
