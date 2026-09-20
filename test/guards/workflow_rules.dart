// The workflow-pin rules, as pure functions over strings.
//
// Pure for the reason every other rule file here is: a rule proven only
// against the repository's own correct workflows has been shown to pass, never
// to fire. Each rule below has inline fixtures in the guard that exercise both
// directions.
//
// A line scan, not a YAML parse. The properties being checked — is there a ref
// after the `@`, is there a `permissions:` block at column 0 — are visible in
// the text, and a parser would add a dependency to check four things. The
// trade-off is stated where it bites: a `uses:` inside a `run: |` block is an
// accepted false positive, so workflows are written not to contain one.
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

String _unquote(String value) {
  final v = value.trim();
  if (v.length >= 2) {
    final first = v[0];
    final last = v[v.length - 1];
    if ((first == "'" && last == "'") || (first == '"' && last == '"')) {
      return v.substring(1, v.length - 1);
    }
  }
  return v;
}

/// Every `uses:` in [text] must name an explicit, non-floating ref.
///
/// Exempt: a local action (`./.github/...`) and a container (`docker://`),
/// neither of which takes an `@ref`.
List<WorkflowOffender> unpinnedUses(String path, String text) {
  final offenders = <WorkflowOffender>[];
  final lines = text.split('\n');
  for (var i = 0; i < lines.length; i++) {
    final raw = lines[i];
    if (raw.trimLeft().startsWith('#')) continue;
    final match = RegExp(r'^\s*-?\s*uses:\s*(.+)$')
        .firstMatch(_stripComment(raw));
    if (match == null) continue;
    final value = _unquote(match.group(1)!);
    if (value.isEmpty) continue;
    if (value.startsWith('./') || value.startsWith('docker://')) continue;

    final at = value.indexOf('@');
    if (at == -1 || at == value.length - 1) {
      offenders.add(
        WorkflowOffender(
          path,
          i + 1,
          '`uses: $value` has no @ref — an unpinned action is a third party '
          'that can change inside the merge gate',
        ),
      );
      continue;
    }
    final ref = value.substring(at + 1);
    if (floatingRefs.contains(ref)) {
      offenders.add(
        WorkflowOffender(
          path,
          i + 1,
          '`uses: $value` is pinned to the moving ref `$ref`; pin a release '
          'tag and let Dependabot carry it forward',
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
  final lines = text.split('\n');
  var hasTopLevel = false;
  for (var i = 0; i < lines.length; i++) {
    final line = _stripComment(lines[i]);
    if (lines[i].trimLeft().startsWith('#')) continue;
    if (RegExp(r'^permissions:').hasMatch(line)) hasTopLevel = true;
    if (RegExp(r'permissions:\s*write-all\s*$').hasMatch(line)) {
      offenders.add(
        WorkflowOffender(
          path,
          i + 1,
          '`permissions: write-all` grants every scope; name the ones needed',
        ),
      );
    }
  }
  if (!hasTopLevel) {
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
  final hasIt = text
      .split('\n')
      .where((l) => !l.trimLeft().startsWith('#'))
      .any((l) => RegExp(r'^concurrency:').hasMatch(_stripComment(l)));
  return hasIt
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
Iterable<({String expression, RunScript script})> _runExpressions(
  String text,
) sync* {
  for (final script in Workflow.parse('', text).runScripts) {
    for (final m in RegExp(
      r'\$\{\{(.*?)\}\}',
      dotAll: true,
    ).allMatches(script.body)) {
      yield (expression: m.group(1)!, script: script);
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
  for (final (expression: expression, script: script) in _runExpressions(
    text,
  )) {
    if (secret.hasMatch(expression)) {
      offenders.add(
        WorkflowOffender(
          path,
          script.line,
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
  for (final (expression: expression, script: script) in _runExpressions(
    text,
  )) {
    final match = untrusted.firstMatch(expression);
    if (match != null) {
      offenders.add(
        WorkflowOffender(
          path,
          script.line,
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
    for (final raw in lines) {
      if (raw.trimLeft().startsWith('#')) continue;
      final line = _stripComment(raw);
      var flagged = false;

      for (final set in RegExp(
        r'''(^|[;&|(]|\s|["'])set\s+((-o\s+["']?[a-z]+["']?|[-+][A-Za-z]+|\s)+)''',
      ).allMatches(line)) {
        final args = set.group(2)!;
        for (final long in RegExp(
          r'''-o\s+["']?(xtrace|verbose)["']?''',
        ).allMatches(args)) {
          flag(script.line, '`set -o ${long.group(1)}`');
          flagged = true;
        }
        if (flagged) break;
        for (final cluster in RegExp(r'[-+]([A-Za-z]+)').allMatches(args)) {
          final flags = cluster.group(1)!;
          if (flags == 'o') continue;
          if (flags.contains('x') || flags.contains('v')) {
            flag(script.line, '`set ${cluster.group(0)}`');
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
        flag(script.line, 'invoking a shell with a trace flag');
        continue;
      }

      if (RegExp(r'SHELLOPTS\s*[:=].*\b(xtrace|verbose)\b').hasMatch(line)) {
        flag(script.line, '`SHELLOPTS` carrying a trace option');
      }
    }
  }

  // `shell: bash -x` turns tracing on for a whole step without a `set`, and is
  // read structurally so a quoted or flow-style value is seen.
  for (final job in workflow.jobs) {
    for (final step in job.steps) {
      final shell = step.shell;
      if (shell == null) continue;
      final words = shell.trim().split(RegExp(r'\s+'));
      for (final word in words.skip(1)) {
        if (RegExp(r'^-[A-Za-z]*[xv][A-Za-z]*$').hasMatch(word) ||
            word == '--verbose' ||
            word == '--xtrace') {
          flag(step.line, '`shell: ${shell.trim()}`');
          break;
        }
      }
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
