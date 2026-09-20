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

/// A `run:` block must never print a secret.
///
/// GitHub masks a secret's exact value in the log, but masking is a safety
/// net, not a policy: it fails on a transformed value (base64, a substring,
/// a value embedded in JSON) and it cannot mask what a shell expands before
/// the runner sees it. The rule is therefore "do not print it", not "rely on
/// the mask".
///
/// Three shapes are caught: a printing command and a `secrets.` expression on
/// one line; a line continued with `\` onto a line holding one; and a heredoc
/// opened by a printing command whose body holds one. The heredoc case is here
/// because `cat <<EOF` with the secret on the next line passed the first
/// version of this rule, and `cat` was already one of its three commands
/// (#131).
///
/// **Not covered**, deliberately: a secret reached through an intermediate
/// variable or a step `env:` mapping (`env: {P: ${{ secrets.X }}}` then
/// `echo "$P"`). Following that needs dataflow, not a line scan. The
/// convention this repository relies on instead is that secrets are passed as
/// step-level `env:` and never echoed at all; `shellTraceOffenders` is the
/// backstop, since tracing is how an env-indirected secret usually escapes.
List<WorkflowOffender> secretEchoOffenders(String path, String text) {
  final offenders = <WorkflowOffender>[];
  final rawLines = text.split('\n');
  const printer = r'(^|[;&|(]|\s)(echo|printf|cat|tee)\s';
  final secret = RegExp(r'secrets\.[A-Za-z_]');

  void flag(int lineNumber, String why) {
    offenders.add(
      WorkflowOffender(
        path,
        lineNumber,
        'a shell command prints a `secrets.` expression ($why); the log mask '
        'is a net, not a policy, and it does not survive transformation',
      ),
    );
  }

  // A heredoc body opened by a printing command, tracked to its delimiter.
  String? heredocDelimiter;
  var heredocOpenedAt = 0;
  // A printing command whose line ended in a backslash continuation.
  var continuingPrinter = false;
  var continuationOpenedAt = 0;

  for (var i = 0; i < rawLines.length; i++) {
    final raw = rawLines[i];

    if (heredocDelimiter != null) {
      if (raw.trim() == heredocDelimiter) {
        heredocDelimiter = null;
      } else if (secret.hasMatch(raw)) {
        flag(heredocOpenedAt, 'inside a heredoc it opens');
        heredocDelimiter = null;
      }
      continue;
    }

    if (continuingPrinter) {
      if (secret.hasMatch(raw)) {
        flag(continuationOpenedAt, 'on a continued line');
        continuingPrinter = false;
        continue;
      }
      continuingPrinter = raw.trimRight().endsWith(r'\');
      continue;
    }

    if (raw.trimLeft().startsWith('#')) continue;
    final line = _stripComment(raw);
    final printsHere = RegExp(printer).hasMatch(line);

    if (printsHere && secret.hasMatch(line)) {
      flag(i + 1, 'on one line');
      continue;
    }
    if (!printsHere) continue;

    final opener = RegExp(r'<<-?\s*([\x27"]?)([A-Za-z_][A-Za-z0-9_]*)\1')
        .firstMatch(line);
    if (opener != null) {
      heredocDelimiter = opener.group(2);
      heredocOpenedAt = i + 1;
      continue;
    }
    if (line.trimRight().endsWith(r'\')) {
      continuingPrinter = true;
      continuationOpenedAt = i + 1;
    }
  }
  return offenders;
}

/// Shell tracing must be off everywhere, because it prints every expanded
/// command — and in a job holding secrets, that means printing them.
///
/// Three spellings are caught: a flag cluster containing `x` (`set -x`,
/// `set -euxo pipefail`), the long form (`set -o xtrace`, and `set -o verbose`
/// which prints the unexpanded line but still leaks a heredoc body), and a
/// `shell:` value that runs the interpreter with `-x` (`shell: bash -x`). The
/// last two were added after both passed the first version of this rule
/// (#131): `set -o xtrace` captured `o` as its flag cluster, and
/// `shell: bash -x` contains no `set` at all.
List<WorkflowOffender> shellTraceOffenders(String path, String text) {
  final offenders = <WorkflowOffender>[];
  final lines = text.split('\n');
  for (var i = 0; i < lines.length; i++) {
    if (lines[i].trimLeft().startsWith('#')) continue;
    final line = _stripComment(lines[i]);

    final longForm = RegExp(r'(^|[;&|]|\s)set\s+-o\s+(xtrace|verbose)\b')
        .firstMatch(line);
    if (longForm != null) {
      offenders.add(
        WorkflowOffender(
          path,
          i + 1,
          '`set -o ${longForm.group(2)}` traces every expanded command, which '
          'in a job holding secrets means printing them',
        ),
      );
      continue;
    }

    final cluster = RegExp(r'(^|[;&|]|\s)set\s+-([A-Za-z]+)').firstMatch(line);
    if (cluster != null && cluster.group(2)!.contains('x')) {
      offenders.add(
        WorkflowOffender(
          path,
          i + 1,
          '`set -${cluster.group(2)}` traces every expanded command, which in '
          'a job holding secrets means printing them',
        ),
      );
      continue;
    }

    // `shell: bash -x` turns tracing on for the whole step without a `set`.
    final shellValue = RegExp(r'^\s*(?:-\s+)?shell:\s*[\x27"]?([^\x27"#]+)')
        .firstMatch(line);
    if (shellValue != null) {
      final words = shellValue.group(1)!.trim().split(RegExp(r'\s+'));
      for (final word in words.skip(1)) {
        if (RegExp(r'^-[A-Za-z]*x[A-Za-z]*$').hasMatch(word) || word == '-o') {
          offenders.add(
            WorkflowOffender(
              path,
              i + 1,
              '`shell: ${shellValue.group(1)!.trim()}` runs the interpreter '
              'with tracing on, which prints every expanded command',
            ),
          );
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
