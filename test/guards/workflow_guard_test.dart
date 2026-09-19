@Tags(['guard'])
library;

// Guard for #18: every action in every workflow is pinned, every workflow
// declares its permissions and its concurrency, and the two files that state
// the Flutter version agree.
//
// Why a guard rather than review: an unpinned action is a third party that can
// change between the run that went green and the run that ships, inside the
// merge gate. The plugin's own lessons name this as the failure that has
// bitten before, and "we will remember to pin" is not a control.
//
// What this does NOT cover: whether a pinned major is current — that is
// Dependabot's job, which is why the `github-actions` ecosystem is asserted
// here too. Nor whether the required-status-check context string matches the
// job name; that lives in the repository ruleset and is recorded on the issue.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'repo_files.dart';
import 'workflow_rules.dart';

const _workflowDir = '.github/workflows';

List<String> _workflowFiles() {
  final dir = Directory('${repoRoot.path}/$_workflowDir');
  if (!dir.existsSync()) return const [];
  return dir
      .listSync() // top level only, deliberately: nothing nested runs
      .whereType<File>()
      .map((f) => f.path.substring(repoRoot.path.length + 1))
      .where((p) => p.endsWith('.yml') || p.endsWith('.yaml'))
      .toList()
    ..sort();
}

void main() {
  group('the repository as it stands', () {
    test('there is at least one workflow', () {
      // An empty or missing directory fails rather than passing vacuously.
      // Every other test in this group iterates the list, so without this one
      // the whole file would go green the moment CI was deleted.
      expect(
        _workflowFiles(),
        isNotEmpty,
        reason:
            'no-workflows: $_workflowDir holds no .yml or .yaml file, so '
            'nothing gates a pull request',
      );
    });

    test('every action is pinned to a fixed, non-floating ref', () {
      final offenders = <String>[];
      for (final path in _workflowFiles()) {
        offenders.addAll(
          unpinnedUses(path, readFile(path)).map((o) => o.toString()),
        );
      }
      expect(offenders, isEmpty, reason: describeOffenders('pins', offenders));
    });

    test('every workflow declares its permissions and never write-all', () {
      final offenders = <String>[];
      for (final path in _workflowFiles()) {
        offenders.addAll(
          permissionOffenders(path, readFile(path)).map((o) => o.toString()),
        );
      }
      expect(
        offenders,
        isEmpty,
        reason: describeOffenders('permissions', offenders),
      );
    });

    test('every workflow declares a concurrency group', () {
      final offenders = <String>[];
      for (final path in _workflowFiles()) {
        offenders.addAll(
          concurrencyOffenders(path, readFile(path)).map((o) => o.toString()),
        );
      }
      expect(
        offenders,
        isEmpty,
        reason: describeOffenders('concurrency', offenders),
      );
    });

    test('no workflow prints a secret or traces its shell', () {
      final offenders = <String>[];
      for (final path in _workflowFiles()) {
        final text = readFile(path);
        offenders.addAll(
          secretEchoOffenders(path, text).map((o) => o.toString()),
        );
        offenders.addAll(
          shellTraceOffenders(path, text).map((o) => o.toString()),
        );
      }
      expect(
        offenders,
        isEmpty,
        reason: describeOffenders('secrets', offenders),
      );
    });

    test('dependabot watches both ecosystems', () {
      final offenders = dependabotOffenders(
        pathExists('.github/dependabot.yml')
            ? readFile('.github/dependabot.yml')
            : null,
      );
      expect(
        offenders,
        isEmpty,
        reason: describeOffenders('dependabot', offenders),
      );
    });

    test('the .fvmrc pin satisfies the pubspec range', () {
      final offenders = flutterPinOffenders(
        readFile('.fvmrc'),
        readFile('pubspec.yaml'),
      );
      expect(
        offenders,
        isEmpty,
        reason: describeOffenders('flutter-pin', offenders),
      );
    });
  });

  // Each rule proven to fire. Without these the group above cannot distinguish
  // a working rule from one that returns an empty list unconditionally.
  group('each rule fires', () {
    test('a uses: with no ref is refused', () {
      const bad = 'jobs:\n  a:\n    steps:\n      - uses: actions/checkout\n';
      final offenders = unpinnedUses('bad.yml', bad);
      expect(offenders, hasLength(1));
      expect(offenders.single.line, 4);
      expect(offenders.single.message, contains('no @ref'));
    });

    test('a trailing @ with nothing after it is refused', () {
      expect(
        unpinnedUses('bad.yml', '      - uses: actions/checkout@\n'),
        hasLength(1),
      );
    });

    for (final ref in floatingRefs) {
      test('a ref of `$ref` is refused', () {
        final offenders = unpinnedUses(
          'bad.yml',
          '      - uses: actions/checkout@$ref\n',
        );
        expect(offenders, hasLength(1));
        expect(offenders.single.message, contains('moving ref'));
      });
    }

    test('a pinned ref, a local action and a container are all allowed', () {
      const good =
          '      - uses: actions/checkout@v7\n'
          '      - uses: "subosito/flutter-action@v2"\n'
          "      - uses: 'ludeeus/action-shellcheck@2.0.0'\n"
          '      - uses: ./.github/workflows/ci.yml\n'
          '      - uses: docker://alpine:3.20\n'
          '      - uses: actions/checkout@v7  # trailing comment\n'
          '      # - uses: actions/checkout\n';
      expect(
        unpinnedUses('good.yml', good),
        isEmpty,
        reason: 'pins-negative: refused a legitimate uses: line',
      );
    });

    test('a ref that merely contains a floating word is allowed', () {
      // `v2-main-branch` is a real tag shape; only the whole ref counts.
      expect(
        unpinnedUses('good.yml', '  - uses: a/b@v2-main-branch\n'),
        isEmpty,
      );
      expect(
        unpinnedUses('good.yml', '  - uses: a/b@latest-stable\n'),
        isEmpty,
      );
    });

    test('a workflow without top-level permissions is refused', () {
      const bad =
          'name: X\njobs:\n  a:\n    permissions:\n      contents: read\n';
      final offenders = permissionOffenders('bad.yml', bad);
      expect(offenders, hasLength(1));
      expect(offenders.single.message, contains('no top-level'));
    });

    test('write-all is refused at any level', () {
      const bad =
          'permissions: read-all\njobs:\n  a:\n    permissions: write-all\n';
      final offenders = permissionOffenders('bad.yml', bad);
      expect(offenders, hasLength(1));
      expect(offenders.single.message, contains('write-all'));
    });

    test('read-all at the top level is allowed', () {
      expect(
        permissionOffenders('good.yml', 'permissions: read-all\n'),
        isEmpty,
      );
    });

    test('a workflow without concurrency is refused', () {
      expect(concurrencyOffenders('bad.yml', 'name: X\n'), hasLength(1));
    });

    test('concurrency in either form is allowed', () {
      expect(
        concurrencyOffenders('good.yml', 'concurrency: play-release\n'),
        isEmpty,
      );
      expect(
        concurrencyOffenders(
          'good.yml',
          'concurrency:\n  group: ci\n  cancel-in-progress: true\n',
        ),
        isEmpty,
      );
    });

    test('printing a secret is refused, in each spelling', () {
      for (final bad in const [
        r'        run: echo ${{ secrets.HS_KEY_PASS }}',
        r'        run: printf "%s" "${{ secrets.PLAY_SERVICE_ACCOUNT_JSON }}"',
        r'        run: cat <<< "${{ secrets.HS_KEYSTORE_B64 }}"',
        r'        run: foo && echo "${{ secrets.X }}"',
      ]) {
        expect(
          secretEchoOffenders('bad.yml', '$bad\n'),
          hasLength(1),
          reason: 'secret-echo: accepted `$bad`',
        );
      }
    });

    test('using a secret without printing it is allowed', () {
      for (final good in const [
        r'          HS_KEY_PASS: ${{ secrets.HS_KEY_PASS }}',
        r'        run: base64 -d <<< "${{ secrets.HS_KEYSTORE_B64 }}" > "$RUNNER_TEMP/k"',
        r'        run: echo "the keystore decoded"',
      ]) {
        expect(
          secretEchoOffenders('good.yml', '$good\n'),
          isEmpty,
          reason: 'secret-echo-negative: refused `$good`',
        );
      }
    });

    test('a set flag cluster containing x is refused', () {
      for (final bad in const [
        'set -x',
        'set -euxo pipefail',
        'foo; set -ex',
      ]) {
        expect(
          shellTraceOffenders('bad.yml', '        run: $bad\n'),
          hasLength(1),
          reason: 'trace: accepted `$bad`',
        );
      }
      for (final good in const ['set -euo pipefail', 'set -e', 'settle -x']) {
        expect(
          shellTraceOffenders('good.yml', '        run: $good\n'),
          isEmpty,
          reason: 'trace-negative: refused `$good`',
        );
      }
    });

    test('a dependabot file missing an ecosystem is refused', () {
      const onlyActions =
          'version: 2\nupdates:\n  - package-ecosystem: github-actions\n';
      expect(dependabotOffenders(onlyActions).join(), contains('pub'));
      expect(dependabotOffenders(null).join(), contains('missing'));
    });

    test('a pin below the pubspec minimum is refused', () {
      expect(
        flutterPinOffenders(
          '{"flutter": "3.46.0"}',
          'environment:\n  sdk: ^3.13.4\n  flutter: ">=3.47.0"\n',
        ).join(),
        contains('below the minimum'),
      );
      expect(
        flutterPinOffenders(
          '{"flutter": "3.47.5"}',
          'environment:\n  sdk: ^3.13.4\n  flutter: ">=3.47.0"\n',
        ),
        isEmpty,
      );
      expect(
        flutterPinOffenders(
          '{"flutter": "3.47.5"}',
          'environment:\n  sdk: ^3.13.4\n',
        ).join(),
        contains('no `flutter:'),
      );
    });
  });
}
