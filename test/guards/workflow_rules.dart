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
List<WorkflowOffender> secretEchoOffenders(String path, String text) {
  final offenders = <WorkflowOffender>[];
  final lines = text.split('\n');
  for (var i = 0; i < lines.length; i++) {
    final line = _stripComment(lines[i]);
    if (lines[i].trimLeft().startsWith('#')) continue;
    if (!RegExp(r'secrets\.[A-Za-z_]').hasMatch(line)) continue;
    if (RegExp(r'(^|[;&|]|\s)(echo|printf|cat)\s').hasMatch(line)) {
      offenders.add(
        WorkflowOffender(
          path,
          i + 1,
          'a shell command prints a `secrets.` expression; the log mask is a '
          'net, not a policy, and it does not survive transformation',
        ),
      );
    }
  }
  return offenders;
}

/// `set -x` traces every expanded command, including expanded secrets.
///
/// Matched as a flag cluster, so `set -euxo pipefail` is caught as well as the
/// obvious `set -x`.
List<WorkflowOffender> shellTraceOffenders(String path, String text) {
  final offenders = <WorkflowOffender>[];
  final lines = text.split('\n');
  for (var i = 0; i < lines.length; i++) {
    if (lines[i].trimLeft().startsWith('#')) continue;
    final match = RegExp(r'(^|[;&|]|\s)set\s+-([A-Za-z]+)')
        .firstMatch(_stripComment(lines[i]));
    if (match == null) continue;
    if (match.group(2)!.contains('x')) {
      offenders.add(
        WorkflowOffender(
          path,
          i + 1,
          '`set -${match.group(2)}` traces every expanded command, which in a '
          'job holding secrets means printing them',
        ),
      );
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
