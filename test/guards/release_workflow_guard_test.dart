@Tags(['guard'])
library;

// A release carrying a placeholder clip can never be uploaded (#63).
//
// Two halves, both executed. `tools/check_no_placeholder_audio.sh` is run
// against temporary trees, with and without a placeholder, and must refuse
// the first and pass the second. And `release.yml` is parsed to prove the
// step running it sits in the upload's job, before the upload, with nothing
// that lets the upload be reached after it fails: a check that fires after
// the upload protects nothing. The ordering rule is then fed the workflow
// with the two steps swapped, from a temporary copy, and must refuse it.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'leak_scan.dart';
import 'repo_files.dart';
import 'workflow_yaml.dart';

const _script = 'tools/check_no_placeholder_audio.sh';
const _release = '.github/workflows/release.yml';

/// Everything wrong with where [wf] runs the placeholder check.
List<String> placeholderGateProblems(Workflow wf) {
  if (wf.problem != null) return ['release-placeholder: ${wf.problem}'];
  final uploads = [
    for (final job in wf.jobs)
      for (final step in job.steps)
        if ((step.uses ?? '').startsWith('r0adkll/upload-google-play@'))
          (job: job, step: step),
  ];
  if (uploads.length != 1) {
    return [
      'release-placeholder: expected one Play upload step, found '
          '${uploads.length}',
    ];
  }
  final (:job, step: upload) = uploads.single;
  final checks = [
    for (final s in job.steps)
      if ((s.run ?? '').trim() == _script) s,
  ];
  if (checks.length != 1) {
    return [
      'release-placeholder: job `${job.name}` runs `$_script` as its whole '
          'step ${checks.length} times; it must once, in the job that '
          'uploads',
    ];
  }
  final check = checks.single;
  final problems = <String>[];
  final at = job.steps.indexOf(check);
  if (at > job.steps.indexOf(upload)) {
    problems.add(
      'release-placeholder: `${check.id}` runs after the Play upload '
      '`${upload.id}`, so a placeholder is reported once it has shipped',
    );
  }
  final scan = job.indexOfId('scan');
  if (scan < 0 || at != scan + 1) {
    problems.add(
      'release-placeholder: `${check.id}` is not the step immediately after '
      '`scan` (tools/check_aab.sh)',
    );
  }
  if (!check.isUnconditional) {
    problems.add(
      'release-placeholder: `${check.id}` is conditional (if: '
      '${check.ifExpression}, continue-on-error: ${check.continueOnError}), '
      'so its failure need not stop the upload',
    );
  }
  if (!upload.isUnconditional) {
    problems.add(
      'release-placeholder: the upload `${upload.id}` is conditional (if: '
      '${upload.ifExpression}), so it can run after the check has failed',
    );
  }
  return problems;
}

/// A tree holding [files] under assets/audio/, with the script run over it.
({int code, String out, String err, String summary}) _check(
  List<String> files,
) {
  final dir = Directory.systemTemp.createTempSync('hs-placeholder-audio');
  addTearDown(() => dir.deleteSync(recursive: true));
  for (final name in files) {
    File('${dir.path}/assets/audio/$name')
      ..createSync(recursive: true)
      ..writeAsStringSync('RIFF');
  }
  final summary = File('${dir.path}/summary.md');
  final r = runSealed(
    '/bin/bash',
    ['${repoRoot.path}/$_script', dir.path],
    workingDirectory: dir.path,
    environment: {'GITHUB_STEP_SUMMARY': summary.path},
  );
  return (
    code: r.exitCode,
    out: r.stdout.toString(),
    err: r.stderr.toString(),
    summary: summary.existsSync() ? summary.readAsStringSync() : '',
  );
}

String _annotation(String path) =>
    '::error file=$path::Placeholder audio cannot ship: $path is a '
    'placeholder. Run tools/sfx.py --install to replace it.';

void main() {
  group('the check', () {
    test('a tree holding placeholders fails, naming each one', () {
      final r = _check([
        'placeholder-place.wav',
        'placeholder-lose.wav',
        'solve.wav',
        'LICENSES.md',
      ]);
      expect(
        r.code,
        1,
        reason: 'placeholder-check: exited ${r.code} over two placeholders',
      );
      final errors = r.out
          .split('\n')
          .where((l) => l.startsWith('::error'))
          .toList();
      expect(errors, [
        _annotation('assets/audio/placeholder-lose.wav'),
        _annotation('assets/audio/placeholder-place.wav'),
      ], reason: 'placeholder-check: not one annotation per placeholder');
      expect(
        r.out,
        contains('2 placeholder clip(s) in assets/audio/'),
        reason: 'placeholder-check: the summary line does not name the count',
      );
      expect(
        r.summary,
        allOf(
          contains('### Placeholder audio blocked this release'),
          contains('- assets/audio/placeholder-place.wav'),
          isNot(contains('solve.wav')),
        ),
        reason: 'placeholder-check: the job summary does not read as a block',
      );
    });

    test('a single placeholder is enough to fail', () {
      final r = _check(['place.wav', 'placeholder-mistake.wav']);
      expect(
        r.code,
        1,
        reason: 'placeholder-check: exited ${r.code} over one placeholder',
      );
      expect(
        r.out,
        contains(_annotation('assets/audio/placeholder-mistake.wav')),
      );
    });

    test('a tree of licensed clips passes, and says nothing is blocked', () {
      final r = _check([
        'place.wav',
        'mistake.wav',
        'solve.wav',
        'lose.wav',
        'LICENSES.md',
      ]);
      expect(
        r.code,
        0,
        reason: 'placeholder-clean: a clean tree exited ${r.code}: ${r.err}',
      );
      expect(r.out, isNot(contains('::error')));
      expect(r.summary, isEmpty, reason: 'placeholder-clean: ${r.summary}');
    });
  });

  group('the release workflow', () {
    test('runs the check right after the scan and before the upload', () {
      final problems = placeholderGateProblems(
        Workflow.parse(_release, readFile(_release)),
      );
      expect(problems, isEmpty, reason: problems.join('\n'));
    });

    test('the ordering rule refuses the check moved past the upload', () {
      // The swap is made in a temporary copy and parsed from there, so what
      // is refused is a real file a mis-ordered release.yml could be.
      final text = readFile(_release);
      final step = RegExp(
        r'\n(      # [^\n]*\n)*      - id: placeholder_audio\n(        [^\n]*\n)+',
      ).firstMatch(text);
      expect(step, isNotNull, reason: 'sanity: the step was not found');
      final without = text.replaceFirst(step![0]!, '\n');
      final play = RegExp(r'      - id: play\n(        [^\n]*\n)+')
          .firstMatch(without)!;
      final swapped = without.replaceFirst(
        play[0]!,
        '${play[0]}${step[0]!.substring(1)}',
      );
      final copy = File(
        '${Directory.systemTemp.createTempSync('hs-release-copy').path}'
        '/release.yml',
      )..writeAsStringSync(swapped);
      addTearDown(() => copy.parent.deleteSync(recursive: true));

      final wf = Workflow.parse(copy.path, copy.readAsStringSync());
      expect(wf.problem, isNull, reason: 'sanity: ${wf.problem}');
      final ship = wf.job('ship')!;
      expect(
        ship.indexOfId('placeholder_audio'),
        greaterThan(ship.indexOfId('play')),
        reason: 'sanity: the copy does not have the steps swapped',
      );
      expect(
        placeholderGateProblems(wf),
        contains(contains('runs after the Play upload')),
        reason: 'release-placeholder-negative: the swap was not refused',
      );
    });
  });
}
