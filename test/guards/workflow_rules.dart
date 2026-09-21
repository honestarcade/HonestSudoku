// The workflow-pin rules, as pure functions over strings.
//
// Pure for the reason every other rule file here is: a rule proven only
// against the repository's own correct workflows has been shown to pass, never
// to fire. Each rule below has inline fixtures in the guard that exercise both
// directions.
//
// A YAML parse, not a line scan — and this header said the opposite for as
// long as it was untrue (#218). #154 reversed the original reasoning and the
// reversal won: a line scan cannot assert STRUCTURE, and every bypass it
// missed — a flow mapping, a quoted scalar, a value on the next line — was a
// real hole rather than a theoretical one. Every rule below reaches the
// document through `Workflow.parse`, and a guard asserts that it is the only
// entry point they use.
//
// The false positive the old text apologised for — a `uses:` inside a
// `run: |` block — does not exist here: a parser sees it as a string.
library;

import 'workflow_yaml.dart';

/// One refusal, as `path:line: message`.
class WorkflowOffender {
  const WorkflowOffender(this.path, this.line, this.message);
  final String path;
  final int line;
  final String message;

  @override
  String toString() => '$path:$line: $message';
}

/// The refs that mean "whatever is newest", which is an unpinned third party
/// inside the merge gate.
const floatingRefs = ['latest', 'main', 'master'];

String _stripComment(String line) {
  // A `#` inside quotes is not a comment. Workflows here do not use one, but
  // the rule should not depend on that.
  var inSingle = false;
  var inDouble = false;
  for (var i = 0; i < line.length; i++) {
    final c = line[i];
    if (c == "'" && !inDouble) inSingle = !inSingle;
    if (c == '"' && !inSingle) inDouble = !inDouble;
    if (c == '#' && !inSingle && !inDouble) return line.substring(0, i);
  }
  return line;
}

/// Every `uses:` in [text] must name an explicit, non-floating ref.
///
/// Exempt: a local action (`./.github/...`) and a container (`docker://`),
/// neither of which takes an `@ref`.
List<WorkflowOffender> unpinnedUses(String path, String text) {
  final offenders = <WorkflowOffender>[];
  final wf = Workflow.parse(path, text);
  if (wf.problem != null) {
    return [WorkflowOffender(path, 1, wf.problem!)];
  }
  for (final entry in wf.allUses) {
    final value = entry.uses.trim();
    if (value.isEmpty) continue;
    if (value.startsWith('./') || value.startsWith('docker://')) continue;

    final at = value.indexOf('@');
    if (at == -1 || at == value.length - 1) {
      offenders.add(
        WorkflowOffender(
          path,
          entry.line,
          '`uses: $value` in ${entry.where} has no @ref — an unpinned action '
          'is a third party that can change inside the merge gate',
        ),
      );
      continue;
    }
    final ref = value.substring(at + 1);
    if (floatingRefs.contains(ref)) {
      offenders.add(
        WorkflowOffender(
          path,
          entry.line,
          '`uses: $value` in ${entry.where} is pinned to the moving ref '
          '`$ref`; pin a release tag and let Dependabot carry it forward',
        ),
      );
    }
  }
  return offenders;
}

/// A workflow must declare a top-level `permissions:` block, and must never
/// grant `write-all` at any level.
List<WorkflowOffender> permissionOffenders(String path, String text) {
  final offenders = <WorkflowOffender>[];
  final wf = Workflow.parse(path, text);
  if (wf.problem != null) {
    return [WorkflowOffender(path, 1, wf.problem!)];
  }

  void check(String? scalar, int line, String where) {
    if (scalar == null) return;
    // Case-insensitive, like the rest of this file. `WRITE-ALL` returned
    // zero offenders (#188).
    if (scalar.trim().toLowerCase() == 'write-all') {
      offenders.add(
        WorkflowOffender(
          path,
          line,
          '`permissions: write-all` $where grants every scope; name the '
          'ones needed',
        ),
      );
    }
  }

  check(wf.permissionsScalar, 1, 'at the top level');
  for (final job in wf.jobs) {
    check(job.permissionsScalar, job.line, 'on job `${job.name}`');
  }

  if (!wf.hasPermissions) {
    offenders.add(
      WorkflowOffender(
        path,
        1,
        'no top-level `permissions:` block — without one the workflow inherits '
        'the repository default, which is broader than any job here needs',
      ),
    );
  }
  return offenders;
}

/// A workflow must declare a top-level `concurrency:`, in either form.
List<WorkflowOffender> concurrencyOffenders(String path, String text) {
  final wf = Workflow.parse(path, text);
  if (wf.problem != null) {
    return [WorkflowOffender(path, 1, wf.problem!)];
  }
  return wf.hasConcurrency
      ? const []
      : [
          WorkflowOffender(
            path,
            1,
            'no top-level `concurrency:` — two runs of the same ref can '
            'otherwise race, and a release workflow must not',
          ),
        ];
}

/// Every `${{ … }}` expression inside a `run:` script.
///
/// Both rules below ask the same question — does an untrusted value reach the
/// shell as text? — so both work on expressions rather than on lines. A `run:`
/// body is obtained by parsing (see workflow_yaml.dart), which is what makes
/// a flow mapping, a quoted key, an anchor, an alias and a multi-line quoted
/// scalar visible; the line scan this replaced missed all five (#154, #156).
Iterable<({String expression, RunScript script, int line})> _runExpressions(
  String text,
) sync* {
  for (final script in Workflow.parse('', text).runScripts) {
    for (final m in RegExp(
      r'\$\{\{(.*?)\}\}',
      dotAll: true,
    ).allMatches(script.body)) {
      // The offending line within the body, not the line the `run:` value
      // starts on. The contract is `path:line: message`, and pointing at
      // the top of a 60-line script makes the reader hunt (#180).
      final before = script.body.substring(0, m.start);
      yield (
        expression: m.group(1)!,
        script: script,
        line: script.bodyLine + '\n'.allMatches(before).length,
      );
    }
  }
}

List<WorkflowOffender> _parseProblem(String path, String text) {
  final problem = Workflow.parse(path, text).problem;
  return problem == null
      ? const []
      : [
          WorkflowOffender(
            path,
            1,
            'could not be read as a workflow ($problem) — a guard that cannot '
            'parse its subject must fail, not pass quietly',
          ),
        ];
}

/// A secret must never appear in a `run:` script at all.
///
/// Not "must not be printed": that meant enumerating the ways a shell can
/// print, and three rounds of fixes each closed the spellings one report named
/// (#131, #141). GitHub substitutes the expression as text before the shell
/// runs, so requiring step-level `env:` removes it from the script entirely and
/// no spelling of echo, heredoc or trace flag can reach it.
///
/// Matched case-insensitively and including the index and function forms:
/// expression contexts and functions are case-insensitive in Actions, and
/// `join(secrets.*, ',')` dumps every secret the job can see (#157).
///
/// **Not covered**: a secret reached through an intermediate variable or a job
/// level `env:` mapping. Following that needs dataflow. `shellTraceOffenders`
/// is the backstop, since tracing is how an env-held secret escapes.
List<WorkflowOffender> secretsInRunOffenders(String path, String text) {
  final offenders = _parseProblem(path, text).toList();
  final secret = RegExp(
    r'\bsecrets\s*(\.\s*[A-Za-z_*]|\[)|\bto_?json\s*\(\s*secrets\s*\)',
    caseSensitive: false,
  );
  for (final (expression: expression, script: script, line: line)
      in _runExpressions(text)) {
    if (secret.hasMatch(expression)) {
      offenders.add(
        WorkflowOffender(
          path,
          line,
          'a secret reaches a `run:` script as text (`\${{$expression}}` in job '
          '`${script.jobName}`). GitHub substitutes it before the shell runs, '
          'so the log mask is the only thing between it and the output. Pass it '
          'as step-level `env:` and reference the variable',
        ),
      );
    }
  }
  return offenders;
}

/// Neither may a value a person controls — a tag name, a dispatch input.
///
/// Same mechanism, different payload: a tag named `v1.0.0$(id)` is a legal git
/// ref, and `release.yml` interpolated `github.ref_name` into an `if: always()`
/// summary step, so it ran even on a tag `ci_version.sh` had refused (#142).
///
/// `steps.*.outputs.*` is allowed: it comes from an earlier step of the same
/// workflow, and where it originates outside, `ci_version.sh` validates it.
List<WorkflowOffender> untrustedInRunOffenders(String path, String text) {
  final offenders = _parseProblem(path, text).toList();
  // Anywhere inside the expression, not only at its start: `format('{0}',
  // github.ref_name)` is the idiomatic way to build a string, and was missed
  // by an anchored pattern (#157).
  final untrusted = RegExp(
    r'\b(github|inputs|needs|matrix|env)\s*[.\[]'
    r'|\bto_?json\s*\(\s*(github|inputs|needs|matrix|env)\s*\)',
    caseSensitive: false,
  );
  for (final (expression: expression, script: script, line: line)
      in _runExpressions(text)) {
    final match = untrusted.firstMatch(expression);
    if (match != null) {
      offenders.add(
        WorkflowOffender(
          path,
          line,
          '`${match.group(1)}` reaches a `run:` script as text '
          '(`\${{$expression}}` in job `${script.jobName}`); a tag name or '
          'dispatch input containing `\$(...)` would execute. Pass it as '
          'step-level `env:` and quote the variable',
        ),
      );
    }
  }
  return offenders;
}

/// Shell tracing must be off everywhere: it prints every expanded command, and
/// in a job holding secrets that means printing them.
///
/// Every `set` on a line is examined, not just the first (`set -euo pipefail;
/// set -x` read as `set -euo` and passed, #141). A quote or a path before the
/// command no longer blocks the match, and `+` flag groups are read, both of
/// which hid ordinary spellings (#154).
List<WorkflowOffender> shellTraceOffenders(String path, String text) {
  final offenders = _parseProblem(path, text).toList();
  final workflow = Workflow.parse(path, text);

  void flag(int line, String what) {
    offenders.add(
      WorkflowOffender(
        path,
        line,
        '$what traces every expanded command, which in a job holding secrets '
        'means printing them',
      ),
    );
  }

  for (final script in workflow.runScripts) {
    final lines = script.body.split('\n');
    for (var i = 0; i < lines.length; i++) {
      final raw = lines[i];
      if (raw.trimLeft().startsWith('#')) continue;
      final line = _stripComment(raw);
      // The contract is `path:line: message`, and every offender reported
      // the line where the `run:` VALUE starts — so a trace on line 40 of a
      // 60-line script pointed at line 12, and the reader hunted (#180).
      final lineNo = script.bodyLine + i;
      var flagged = false;

      for (final set in RegExp(
        r'''(^|[;&|(]|\s|["'])set\s+((-o\s+["']?[a-z]+["']?|[-+][A-Za-z]+|\s)+)''',
      ).allMatches(line)) {
        final args = set.group(2)!;
        for (final long in RegExp(
          r'''-o\s+["']?(xtrace|verbose)["']?''',
        ).allMatches(args)) {
          flag(lineNo, '`set -o ${long.group(1)}`');
          flagged = true;
        }
        if (flagged) break;
        for (final cluster in RegExp(r'[-+]([A-Za-z]+)').allMatches(args)) {
          final flags = cluster.group(1)!;
          if (flags == 'o') continue;
          if (flags.contains('x') || flags.contains('v')) {
            flag(lineNo, '`set ${cluster.group(0)}`');
            flagged = true;
            break;
          }
        }
        if (flagged) break;
      }
      if (flagged) continue;

      // An interpreter invoked with a trace flag, by name or by path, short
      // form or long.
      if (RegExp(
        r'''(^|[;&|(]|\s|["'])(/\S*/)?(ba|z|k|da|)sh\s+((-[A-Za-z]*[xv][A-Za-z]*|--verbose|--xtrace|-o\s+(xtrace|verbose))(\s|$))''',
      ).hasMatch(line)) {
        flag(lineNo, 'invoking a shell with a trace flag');
        continue;
      }

      if (RegExp(r'SHELLOPTS\s*[:=].*\b(xtrace|verbose)\b').hasMatch(line)) {
        flag(lineNo, '`SHELLOPTS` carrying a trace option');
      }
    }
  }

  // A `shell:` value carrying a trace flag turns tracing on without a `set`.
  // Checked at all three levels: the workflow's `defaults`, each job's, and
  // each step's. Only the step level was checked, so changing the
  // workflow-level `shell: bash` to `bash -x` traced every step in the job
  // holding all five secrets with the suite green (#168).
  void checkShell(String? shell, int line, String where) {
    if (shell == null) return;
    final words = shell.trim().split(RegExp(r'\s+')).skip(1).toList();
    for (var i = 0; i < words.length; i++) {
      final word = words[i];
      if (RegExp(r'^-[A-Za-z]*[xv][A-Za-z]*$').hasMatch(word) ||
          word == '--verbose' ||
          word == '--xtrace') {
        flag(line, '`$where: ${shell.trim()}`');
        return;
      }
      // The LONG form, `-o xtrace`, which is two words. checkShell matched
      // only the clustered flags, so `shell: bash -o xtrace` was green at
      // workflow, job and step level — while this same function already
      // handled `set -o xtrace` and `sh -o xtrace` inside a `run:` body. The
      // long form was simply not carried across (#168, #189).
      if (word == '-o' && i + 1 < words.length) {
        final opt = words[i + 1].replaceAll(RegExp(r'''["']'''), '');
        if (opt == 'xtrace' || opt == 'verbose') {
          flag(line, '`$where: ${shell.trim()}`');
          return;
        }
      }
    }
  }

  /// `SHELLOPTS`/`BASHOPTS` set in an `env:` block.
  ///
  /// bash reads `SHELLOPTS` from the environment at startup and enables every
  /// option named in it, so `env: SHELLOPTS: xtrace` traces every step of the
  /// job — and the release job holds all five secrets. #168's Fix line called
  /// for this scan and it was never written; `env:` was not in the model at
  /// all (#189).
  void checkEnv(Map<String, String> env, int line, String where) {
    for (final entry in env.entries) {
      final name = entry.key.toUpperCase();
      if (name != 'SHELLOPTS' && name != 'BASHOPTS') continue;
      final value = entry.value.toLowerCase();
      if (value.contains('xtrace') || value.contains('verbose')) {
        flag(line, '`$where: ${entry.key}: ${entry.value}`');
      }
    }
  }

  checkShell(workflow.defaultShell, 1, 'defaults.run.shell');
  checkEnv(workflow.env, 1, 'env');
  for (final job in workflow.jobs) {
    // job.line, not 1: the offender pointed at the top of the file for a
    // job-level shell, contradicting the `path:line:` contract this file
    // makes a point of (#189).
    checkShell(
      job.defaultShell,
      job.line,
      'defaults.run.shell in job `${job.name}`',
    );
    checkEnv(job.env, job.line, 'env in job `${job.name}`');
    for (final step in job.steps) {
      checkEnv(step.env, step.line, 'env on step ${step.id ?? step.index}');
      final shell = step.shell;
      if (shell == null) continue;
      checkShell(shell, step.line, 'shell');
    }
  }
  return offenders;
}

/// Dependabot must watch both ecosystems this repository has.
///
/// The github-actions one is what justifies pinning at a major tag rather than
/// a SHA: without it the pin is a promise nobody keeps.
List<String> dependabotOffenders(String? text) {
  if (text == null) {
    return const [
      '.github/dependabot.yml: missing — a major-tag pin is only justified if '
          'something carries majors forward',
    ];
  }
  final offenders = <String>[];
  for (final ecosystem in const ['github-actions', 'pub']) {
    if (!RegExp('''package-ecosystem:\\s*["']?$ecosystem["']?''')
        .hasMatch(text)) {
      offenders.add('.github/dependabot.yml: no `$ecosystem` ecosystem');
    }
  }
  return offenders;
}

/// The `.fvmrc` pin CI reads must satisfy the range `pubspec.yaml` declares.
///
/// They are two files that must agree, which is the shape that has drifted
/// repeatedly in this project, so it is asserted rather than assumed.
List<String> flutterPinOffenders(String fvmrc, String pubspec) {
  final pin = RegExp('''["']flutter["']\\s*:\\s*["']([^"']+)["']''')
      .firstMatch(fvmrc)
      ?.group(1);
  if (pin == null) {
    return const ['.fvmrc: no `flutter` version'];
  }
  final range = RegExp(
    r'''^\s+flutter:\s*["']?>=([0-9]+)\.([0-9]+)\.([0-9]+)''',
    multiLine: true,
  ).firstMatch(pubspec);
  if (range == null) {
    return const [
      'pubspec.yaml: no `flutter: ">=x.y.z"` under `environment:` — without it '
          'nothing states the minimum the code needs',
    ];
  }
  final parts = pin.split('.');
  if (parts.length != 3 || parts.any((p) => int.tryParse(p) == null)) {
    return ['.fvmrc: `$pin` is not a three-part version'];
  }
  final pinned = [for (final p in parts) int.parse(p)];
  final minimum = [for (var g = 1; g <= 3; g++) int.parse(range.group(g)!)];
  for (var i = 0; i < 3; i++) {
    if (pinned[i] > minimum[i]) return const [];
    if (pinned[i] < minimum[i]) {
      return [
        '.fvmrc pins Flutter $pin, below the minimum '
            '${minimum.join('.')} that pubspec.yaml requires',
      ];
    }
  }
  return const [];
}
