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

/// The `(line number, text)` of every line inside a `run:` body.
///
/// A `run:` block scalar owns every following line indented deeper than the
/// key; a single-line `run:` owns itself. This is the unit both rules below
/// work on, because the question they ask — "does an untrusted value reach the
/// shell as text?" — is a property of the script, not of any one command in it.
List<MapEntry<int, String>> runBodyLines(String text) {
  final out = <MapEntry<int, String>>[];
  final lines = text.split('\n');
  var inRun = false;
  var keyIndent = 0;
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    final block = RegExp(r'^(\s*)-?\s*run:\s*([|>].*)?$').firstMatch(line);
    if (block != null && (block.group(2) ?? '').isNotEmpty) {
      inRun = true;
      keyIndent = block.group(1)!.length;
      continue;
    }
    if (inRun) {
      final indent = line.length - line.trimLeft().length;
      if (line.trim().isEmpty) continue;
      if (indent <= keyIndent) {
        inRun = false;
      } else {
        out.add(MapEntry(i + 1, line));
        continue;
      }
    }
    final inline = RegExp(r'^\s*-?\s*run:\s*(\S.*)$').firstMatch(line);
    if (inline != null) out.add(MapEntry(i + 1, inline.group(1)!));
  }
  return out;
}

/// A secret must never appear in a `run:` body at all.
///
/// The rule used to be "do not *print* a secret", which meant enumerating the
/// ways a shell can print one. That is unwinnable: three rounds of fixes
/// (#131, #141) closed the spellings each report happened to name and left
/// `set -v`, `secrets['NAME']`, `cat<<EOF`, `cat <<'E-OF'` and
/// `bash -x script.sh` open — every one of them ordinary. It also began
/// refusing `cat <<EOF > key.properties`, which prints nothing.
///
/// So the question changed. A secret interpolated into a `run:` body is
/// substituted by GitHub as **text, before the shell sees it**, which is what
/// makes every one of those spellings work. Requiring secrets to arrive as
/// step-level `env:` removes the text from the script entirely, and then no
/// spelling of echo, heredoc or trace flag can leak it. It is also GitHub's
/// own guidance, and what every workflow in this repository already does.
///
/// **Scope:** this catches the value reaching the script. What a script then
/// does with `$HS_KEY_PASS` is not visible to a line scan — `shellTraceOffenders`
/// is the backstop there, since tracing is how an env-held secret escapes.
List<WorkflowOffender> secretsInRunOffenders(String path, String text) {
  final offenders = <WorkflowOffender>[];
  // `secrets.NAME`, `secrets['NAME']`, `secrets["NAME"]`, `toJSON(secrets)`.
  final secret = RegExp(
    r'secrets\s*(\.\s*[A-Za-z_]|\[)|toJSON\(\s*secrets\s*\)',
  );
  for (final entry in runBodyLines(text)) {
    if (entry.value.trimLeft().startsWith('#')) continue;
    if (secret.hasMatch(entry.value)) {
      offenders.add(
        WorkflowOffender(
          path,
          entry.key,
          'a `secrets.` expression is interpolated into a `run:` body. GitHub '
          'substitutes it as text before the shell runs, so the log mask is '
          'the only thing between it and the output. Pass it as step-level '
          '`env:` and reference the variable instead',
        ),
      );
    }
  }
  return offenders;
}

/// Neither may a value a person controls — a tag name, a dispatch input.
///
/// Same mechanism, different payload: `${{ github.ref_name }}` inside a `run:`
/// body is pasted in as text, so a tag named `v1.0.0$(id)` executes. A
/// dispatch input does the same, and can forge a line into a run summary that
/// says a release was promoted when it was refused (#142).
///
/// `steps.*.outputs.*` is allowed: it comes from an earlier step in the same
/// workflow, and where it originates outside (`ci_version.sh`) that script
/// validates it strictly.
List<WorkflowOffender> untrustedInRunOffenders(String path, String text) {
  final offenders = <WorkflowOffender>[];
  final untrusted = RegExp(r'\$\{\{\s*(github|inputs|env)\s*\.');
  for (final entry in runBodyLines(text)) {
    if (entry.value.trimLeft().startsWith('#')) continue;
    final match = untrusted.firstMatch(entry.value);
    if (match != null) {
      offenders.add(
        WorkflowOffender(
          path,
          entry.key,
          '`${match.group(1)}.` is interpolated into a `run:` body; a tag name '
          'or dispatch input containing `\$(...)` would execute. Pass it as '
          'step-level `env:` and quote the variable',
        ),
      );
    }
  }
  return offenders;
}

/// Shell tracing must be off everywhere, because it prints every expanded
/// command — and in a job holding secrets, that means printing them.
///
/// Every `set` on a line is examined, not just the first: `firstMatch` meant
/// `set -euo pipefail; set -x` was read as `set -euo` and passed (#141). The
/// spellings covered are a flag cluster containing `x` or `v`, the long forms
/// `-o xtrace` / `-o verbose` quoted or not and wherever they sit in the
/// option list, a `shell:` value carrying a trace flag, invoking an
/// interpreter with one, and `SHELLOPTS`.
List<WorkflowOffender> shellTraceOffenders(String path, String text) {
  final offenders = <WorkflowOffender>[];
  final lines = text.split('\n');

  void flag(int lineNumber, String what) {
    offenders.add(
      WorkflowOffender(
        path,
        lineNumber,
        '$what traces every expanded command, which in a job holding secrets '
        'means printing them',
      ),
    );
  }

  for (var i = 0; i < lines.length; i++) {
    if (lines[i].trimLeft().startsWith('#')) continue;
    final line = _stripComment(lines[i]);
    var flagged = false;

    // Every `set` on the line, and every `-o <option>` within each.
    for (final set in RegExp(
      r'(^|[;&|(]|\s)set\s+((-o\s+["\x27]?[a-z]+["\x27]?|-[A-Za-z]+|\s)+)',
    ).allMatches(line)) {
      final args = set.group(2)!;
      for (final long in RegExp(
        r'-o\s+["\x27]?(xtrace|verbose)["\x27]?',
      ).allMatches(args)) {
        flag(i + 1, '`set -o ${long.group(1)}`');
        flagged = true;
      }
      if (flagged) break;
      for (final cluster in RegExp(r'-([A-Za-z]+)').allMatches(args)) {
        final flags = cluster.group(1)!;
        if (flags == 'o') continue;
        if (flags.contains('x') || flags.contains('v')) {
          flag(i + 1, '`set -$flags`');
          flagged = true;
          break;
        }
      }
      if (flagged) break;
    }
    if (flagged) continue;

    // `shell: bash -x`, list item or not.
    final shellValue = RegExp(r'^\s*(?:-\s+)?shell:\s*[\x27"]?([^\x27"#]+)')
        .firstMatch(line);
    if (shellValue != null) {
      final words = shellValue.group(1)!.trim().split(RegExp(r'\s+'));
      for (final word in words.skip(1)) {
        if (RegExp(r'^-[A-Za-z]*[xv][A-Za-z]*$').hasMatch(word) ||
            word == '--verbose' ||
            word == '--xtrace') {
          flag(i + 1, '`shell: ${shellValue.group(1)!.trim()}`');
          flagged = true;
          break;
        }
      }
    }
    if (flagged) continue;

    // Invoking an interpreter with a trace flag, e.g. `bash -x tools/gate.sh`.
    if (RegExp(r'(^|[;&|(]|\s)(ba|z|k|da|)sh\s+-[A-Za-z]*[xv][A-Za-z]*(\s|$)')
        .hasMatch(line)) {
      flag(i + 1, 'invoking a shell with a trace flag');
      flagged = true;
    }
    if (flagged) continue;

    // SHELLOPTS turns tracing on for every child shell.
    if (RegExp(r'SHELLOPTS\s*[:=].*\b(xtrace|verbose)\b').hasMatch(line)) {
      flag(i + 1, '`SHELLOPTS` carrying a trace option');
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
