/// The one place a guard starts a process.
///
/// Two ways in. [LeakScan.run] is for a process that is handed a secret, or
/// could reach one: its environment is built from nothing, every value it is
/// handed under a secret-shaped name is searched for afterwards on every
/// channel the process could have written to, and a hit fails the test.
/// [runSealed] is for a process that needs no secret at all: it inherits
/// nothing, refuses a secret-shaped name, and refuses to put a live secret on
/// a command line. [makeExecutable] and [findOnPath] cover the two chores
/// that used to be done with a shell.
///
/// `leak_scan_test.dart` holds the rule that nothing under `test/` starts a
/// process anywhere else, and one canary per channel so that a channel this
/// file stops reading is noticed. Design: the spike comment on #222.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'repo_files.dart';

/// What [LeakScan.run] hands back. [wrote] maps every path under the scan's
/// roots and scratch that the harness did not write (or whose bytes changed
/// since it did) to its latin1-decoded bytes; a directory's key ends in `/`
/// and its value is empty.
typedef LeakRun = ({
  int code,
  String out,
  String err,
  Map<String, String> wrote,
});

/// A call whose PURPOSE is to put one secret on one channel.
///
/// [value] names the variable whose value may appear, [channel] is the
/// channel key it may appear on (`stdout`, `stderr`, `argv`, `log`, `file`,
/// `name`, `workspace`), and [file] is the one test file allowed to ask for
/// it. Every other value, and this value on every other channel, is still
/// searched.
typedef LeakAllowance = ({
  String file,
  String value,
  String channel,
  String reason,
});

/// Every allowance, by the id a call passes in `allow:`.
///
/// `leak_scan_test.dart` holds this map and the call sites to each other
/// exactly, so an allowance cannot be granted in silence or outlive its call.
const leakAllowances = <String, LeakAllowance>{
  'credentials-dot-source': (
    file: 'test/guards/secrets_scripts_test.dart',
    value: 'HS_KEYSTORE_PASS',
    channel: 'stdout',
    reason:
        'dot-sources the credentials file to prove nothing in it executes; '
        'the password printed back unchanged is the assertion',
  ),
  'credentials-parse': (
    file: 'test/guards/secrets_scripts_test.dart',
    value: 'HS_KEYSTORE_PASS',
    channel: 'stdout',
    reason:
        "parses the credentials file with set_ci_secrets.sh's own "
        'read_credential; the password printed back unchanged is the assertion',
  ),
};

/// Environment variable names whose VALUES are secrets: anything ending in
/// one of these, so `HS_KEYSTORE_PASS` and `HS_STUB_PASS` need no listing.
///
/// Deliberately NOT here: ALIAS. The upload key's alias is public by design —
/// android/signing/README.md publishes it beside the certificate
/// fingerprint, and keytool takes it on the command line.
const _secretSuffixes = [
  'PASS',
  'PASSWORD',
  'SECRET',
  'TOKEN',
  'KEY',
  'B64',
  'JSON',
];

bool _looksSecret(String name) {
  final upper = name.toUpperCase();
  return _secretSuffixes.any(upper.endsWith);
}

/// The variables the signing credentials file exists to carry. A value
/// handed under one of these names is at home in that file; anything else
/// found there — a service-account key appended to it, say — is a leak.
const _credentialHomed = {
  'HS_KEYSTORE_PASS',
  'HS_KEY_PASS',
  'HS_KEY_ALIAS',
  'HS_KEYSTORE_PATH',
};

/// Where `tools/make_upload_key.sh` writes the signing credentials, and
/// `tools/set_ci_secrets.sh` reads them, under [home].
String credentialsFile(String home) =>
    '$home/HonestArcadeApps/secrets/sudoku-signing-credentials.txt';

typedef _Channel = ({String key, String where, String text, String path});

/// Scans what a started process could have written for the secrets it was
/// handed. One instance per test file; sentinels, homes and harness-written
/// files are per test, cleared by a tear-down the first of them registers.
class LeakScan {
  LeakScan({
    required this.roots,
    this.argvLogs = const {},
    required this.scratch,
  }) {
    _instances.add(this);
  }

  /// Directories whose every file is read after each [run]: its name, and its
  /// bytes unless they still match what the harness wrote.
  final List<String> Function() roots;

  /// Files a stub appends its argv to, by the name a failure reports.
  final Map<String, String Function()> argvLogs;

  /// Scratch space handed to every [run] as `TMPDIR`, with `RUNNER_TEMP`
  /// under it, and scanned like a root.
  final String Function() scratch;

  static final _instances = <LeakScan>[];

  /// Each live sentinel, with every name it was handed under.
  final _sentinels = <String, Set<String>>{};

  /// Paths where the values of the named variables are allowed to live.
  final _homes = <String, Set<String>>{};

  /// What the harness wrote at each path, as the scan will read it back.
  final _harness = <String, String>{};

  bool _clearRegistered = false;

  /// Whether [value] is currently searched for.
  bool isLive(String value) => _sentinels.containsKey(value.trim());

  void _perTest() {
    if (_clearRegistered) return;
    _clearRegistered = true;
    addTearDown(_clear);
  }

  void _clear() {
    _sentinels.clear();
    _homes.clear();
    _harness.clear();
    _clearRegistered = false;
  }

  /// Searches for each value from now until the end of the test, whatever its
  /// name.
  void declare(Map<String, String> secrets) => secrets.forEach(_add);

  /// Allows the values of [names] to be found at [path], and nowhere else by
  /// virtue of this.
  void home(String path, Iterable<String> names) {
    _perTest();
    (_homes[path] ??= {}).addAll(names);
  }

  /// Records that the harness put [content] at [path], so the file is not
  /// read as the process's output while its bytes are unchanged.
  void harnessWrote(String path, String content) {
    _perTest();
    _harness[path] = latin1.decode(utf8.encode(content));
  }

  /// Writes an executable the harness owns: written, recorded, `chmod +x`.
  void writeExecutable(String path, String body) {
    File(path)
      ..createSync(recursive: true)
      ..writeAsStringSync(body);
    harnessWrote(path, body);
    makeExecutable(path);
  }

  /// Adds [value] to the scan, failing when it is too short to search for.
  ///
  /// Eight, to match [_leakForms]: below eight only the verbatim form is
  /// searched, so a shorter fixture piped through `base64` would walk past
  /// the scan while it looked covered. A value inherited from the parent is
  /// not a fixture this file can lengthen, so it is skipped instead.
  void _add(String name, String value, {bool floor = true}) {
    final v = value.trim();
    if (v.isEmpty) return;
    if (v.length < 8) {
      if (!floor) return;
      fail(
        'leak-fixture: the value of `$name` is ${v.length} character(s); the '
        'transformed forms are searched from eight. Give the fixture a longer '
        'distinctive value — a short one silently disables most of the leak '
        'scan for this test',
      );
    }
    _perTest();
    (_sentinels[v] ??= {}).add(name);
  }

  /// The secret-shaped exports of the credentials file at [path], if any.
  ///
  /// Four spellings: double-quoted, single-quoted, unquoted, and any of those
  /// followed by a trailing comment.
  void _deriveCredentials(String path) {
    final creds = File(path);
    if (!creds.existsSync()) return;
    for (final m in RegExp(
      r'''^\s*export\s+(\w+)=(?:"([^"]*)"|'([^']*)'|([^\s#]+))''',
      multiLine: true,
    ).allMatches(creds.readAsStringSync())) {
      // By NAME, like the environment: the file also carries
      // HS_KEYSTORE_PATH, a path the scripts print in error messages on
      // purpose.
      if (!_looksSecret(m.group(1)!)) continue;
      _add(m.group(1)!, m.group(2) ?? m.group(3) ?? m.group(4) ?? '');
    }
  }

  /// Starts [executable] with an environment built from nothing, then fails
  /// the test if any secret it was handed reached any channel.
  ///
  /// Sentinels come from [environment] entries whose name looks secret, from
  /// [secrets] whatever their names, from [inherit]ed or
  /// [inheritAllExcept]-inherited parent values whose name looks secret and
  /// whose value is eight characters or more, and from the credentials file
  /// under the `HOME` in [environment]. [why] leads the failure reason.
  /// [allow] names entries of [leakAllowances].
  LeakRun run(
    String executable,
    List<String> args, {
    required Map<String, String> environment,
    Set<String> inherit = const {},
    Set<String>? inheritAllExcept,
    Map<String, String> secrets = const {},
    String? workingDirectory,
    required String why,
    List<String> allow = const [],
  }) {
    for (final id in allow) {
      if (!leakAllowances.containsKey(id)) {
        fail(
          'leak-allowance: `$id` is not in leakAllowances, so $why would let '
          'a secret through on no recorded reason',
        );
      }
    }
    final parent = Platform.environment;
    final inherited = <String, String>{
      if (inheritAllExcept != null)
        for (final e in parent.entries)
          if (!inheritAllExcept.contains(e.key)) e.key: e.value,
      for (final name in inherit)
        if (parent[name] != null) name: parent[name]!,
    };
    final scratchDir = scratch();
    Directory('$scratchDir/runner').createSync(recursive: true);
    final env = <String, String>{
      // Scratch space inside the scanned tree. Not for a child that takes
      // the parent's whole environment: that child keeps the parent's.
      if (inheritAllExcept == null) ...{
        'TMPDIR': scratchDir,
        'RUNNER_TEMP': '$scratchDir/runner',
      },
      ...inherited,
      ...environment,
    };

    inherited.forEach((name, value) {
      if (_looksSecret(name)) _add(name, value, floor: false);
    });
    environment.forEach((name, value) {
      if (_looksSecret(name)) _add(name, value);
    });
    secrets.forEach(_add);
    final home = environment['HOME'];
    final credentials = home == null ? null : credentialsFile(home);
    if (credentials != null) {
      this.home(credentials, _credentialHomed);
      _deriveCredentials(credentials);
    }

    // Before the process exists: a secret on a command line is readable from
    // the process table for as long as the process runs.
    _assertNoLeak(why, allow, [
      (
        key: 'argv',
        where: 'its own command line',
        text: [executable, ...args].join(' '),
        path: '',
      ),
    ]);

    final r = Process.runSync(
      executable,
      args,
      workingDirectory: workingDirectory,
      includeParentEnvironment: false,
      environment: env,
      stdoutEncoding: const Utf8Codec(allowMalformed: true),
      stderrEncoding: const Utf8Codec(allowMalformed: true),
    );
    final out = r.stdout.toString();
    final err = r.stderr.toString();

    // Again: the credentials file may have been written BY this run.
    if (credentials != null) _deriveCredentials(credentials);

    String display(String path) =>
        home == null ? path : path.replaceFirst(home, r'$HOME');
    final channels = <_Channel>[
      (key: 'stdout', where: 'stdout', text: out, path: ''),
      (key: 'stderr', where: 'stderr', text: err, path: ''),
    ];
    for (final log in argvLogs.entries) {
      final f = File(log.value());
      if (!f.existsSync()) continue;
      channels.add((
        key: 'log',
        where: '${log.key} (recorded argv)',
        text: latin1.decode(f.readAsBytesSync(), allowInvalid: true),
        path: f.path,
      ));
    }
    final wrote = <String, String>{};
    final seen = <String>{};
    for (final root in [...roots(), scratchDir]) {
      final dir = Directory(root);
      if (!dir.existsSync()) continue;
      for (final entity in dir.listSync(recursive: true, followLinks: false)) {
        if (!seen.add(entity.path)) continue;
        // THE NAME as well as the bytes: upload-artifact publishes the paths
        // it sweeps, and a directory's name is listed too.
        final relative = entity.path.substring(root.length + 1);
        channels.add((
          key: 'name',
          where: 'the name of ${display(entity.path)}',
          text: relative,
          path: entity.path,
        ));
        if (entity is Directory) wrote['${entity.path}/'] = '';
        if (entity is! File) continue;
        // latin1 over the bytes: a strict decode throws on the first byte
        // that is not UTF-8, and skipping the file then hides a secret
        // beside it.
        final text = latin1.decode(
          entity.readAsBytesSync(),
          allowInvalid: true,
        );
        if (_harness[entity.path] == text) continue;
        wrote[entity.path] = text;
        channels.add((
          key: 'file',
          where: 'file ${display(entity.path)}',
          text: text,
          path: entity.path,
        ));
      }
    }
    final cwd = workingDirectory ?? Directory.current.path;
    if (_samePath(cwd, repoRoot.path)) _collectWorkspace(channels);

    _assertNoLeak(why, allow, channels);
    return (code: r.exitCode, out: out, err: err, wrote: wrote);
  }

  void _assertNoLeak(String why, List<String> allow, List<_Channel> channels) {
    for (final MapEntry(key: secret, value: names) in _sentinels.entries) {
      for (final form in _leakForms(secret)) {
        if (form.form.length < 4) continue;
        for (final channel in channels) {
          if (!channel.text.contains(form.form)) continue;
          // Its own home, by path identity, and only for the values of the
          // variables that home is for.
          if (channel.key == 'file' &&
              (_homes[channel.path]?.any(names.contains) ?? false)) {
            continue;
          }
          if (allow.any((id) {
            final a = leakAllowances[id]!;
            return a.channel == channel.key && names.contains(a.value);
          })) {
            continue;
          }
          fail(
            'leak: $why — a secret reached ${channel.where}'
            '${form.how == 'verbatim' ? '' : ' (as ${form.how})'}'
            ' (`${(names.toList()..sort()).join('`, `')}`)',
          );
        }
      }
    }
  }
}

bool _samePath(String a, String b) {
  String canonical(String p) {
    try {
      return Directory(p).resolveSymbolicLinksSync();
    } on FileSystemException {
      return p;
    }
  }

  return canonical(a) == canonical(b);
}

/// Top-level files in the repository root that git does not hold unmodified.
///
/// The root is a scripted process's working directory, and on CI it is
/// $GITHUB_WORKSPACE, which upload-artifact and actions/cache sweep. Only the
/// top level, and only untracked or modified files: committed text would
/// match on prose, and `build/` is large. Computed per scan, because a file a
/// run overwrote is modified only after the run.
void _collectWorkspace(List<_Channel> channels) {
  final unmodified = _unmodifiedAtRoot();
  for (final entity in repoRoot.listSync()) {
    if (entity is! File) continue;
    final name = entity.path.substring(repoRoot.path.length + 1);
    if (unmodified.contains(name)) continue;
    channels.add((
      key: 'workspace',
      where: 'file \$GITHUB_WORKSPACE/$name',
      text: latin1.decode(entity.readAsBytesSync(), allowInvalid: true),
      path: entity.path,
    ));
  }
}

Set<String> _unmodifiedAtRoot() {
  Set<String> topLevel(ProcessResult r) => {
    for (final line in r.stdout.toString().split('\n'))
      if (!line.contains('/') && line.isNotEmpty) line,
  };
  final tracked = runSealed('git', [
    'ls-files',
  ], workingDirectory: repoRoot.path);
  final modified = runSealed('git', [
    'ls-files',
    '--modified',
  ], workingDirectory: repoRoot.path);
  return topLevel(tracked)..removeAll(topLevel(modified));
}

/// Every form of [secret] a script could emit instead of the literal.
///
/// Not complete — no fixed set can be. These are the forms reachable with a
/// single shell builtin or a command the scripts under test already use.
Iterable<({String form, String how})> _leakForms(String secret) sync* {
  yield (form: secret, how: 'verbatim');
  // Transformed forms only from eight characters: a short value lowercased
  // is a handful of ordinary letters, and matches prose.
  if (secret.length < 8) return;
  yield (form: base64.encode(utf8.encode(secret)), how: 'base64');
  yield (form: secret.split('').reversed.join(), how: 'reversed');
  yield (
    form: utf8
        .encode(secret)
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join(),
    how: 'hex',
  );
  yield (form: secret.toLowerCase(), how: 'lowercased');
  yield (form: secret.toUpperCase(), how: 'uppercased');
  yield (form: _rot13(secret), how: 'rot13');
  yield (form: Uri.encodeComponent(secret), how: 'URL-encoded');
  // A slice is evidence only when the slice itself is distinctive: the tail
  // of `S3CRET-store-password` is the English word `password`.
  bool distinctive(String f) => RegExp(r'[^A-Za-z]').hasMatch(f);
  final head = secret.substring(0, 8);
  final tail = secret.substring(secret.length - 8);
  if (distinctive(head)) yield (form: head, how: 'its first 8 characters');
  if (distinctive(tail)) yield (form: tail, how: 'its last 8 characters');
}

String _rot13(String s) => String.fromCharCodes(
  s.codeUnits.map((c) {
    if (c >= 0x41 && c <= 0x5A) return (c - 0x41 + 13) % 26 + 0x41;
    if (c >= 0x61 && c <= 0x7A) return (c - 0x61 + 13) % 26 + 0x61;
    return c;
  }),
);

/// What a sealed call must not carry: every live sentinel of every scan, and
/// every secret-shaped value of eight characters or more in this process's
/// own environment — on CI, that is the token the guard job is given.
Iterable<({String name, String value})> _watched() sync* {
  for (final scan in LeakScan._instances) {
    for (final e in scan._sentinels.entries) {
      yield (name: e.value.join(', '), value: e.key);
    }
  }
  for (final e in Platform.environment.entries) {
    final v = e.value.trim();
    if (_looksSecret(e.key) && v.length >= 8) yield (name: e.key, value: v);
  }
}

/// Starts a process that needs no secret, with nothing inherited.
///
/// The child gets `PATH` and `HOME` from this process, which name where
/// things are and hold no secret, plus [environment]. Fails `leak-sealed:`
/// when [environment] carries a secret-shaped name, when the command line
/// carries a watched value, or when one comes back on stdout or stderr.
ProcessResult runSealed(
  String executable,
  List<String> args, {
  String? workingDirectory,
  Map<String, String> environment = const {},
}) {
  final named = environment.keys.where(_looksSecret).toList();
  if (named.isNotEmpty) {
    fail(
      'leak-sealed: $executable is handed `${named.join('`, `')}`, which is '
      'named like a secret. A call that handles a secret goes through '
      'LeakScan.run, where it is searched for',
    );
  }
  final watched = _watched().toList();
  final argv = [executable, ...args].join(' ');
  for (final w in watched) {
    if (argv.contains(w.value)) {
      fail(
        'leak-sealed: the value of `${w.name}` is on the command line of '
        '$executable',
      );
    }
  }
  final r = Process.runSync(
    executable,
    args,
    workingDirectory: workingDirectory,
    includeParentEnvironment: false,
    environment: {
      for (final name in const ['PATH', 'HOME'])
        if (Platform.environment[name] != null)
          name: Platform.environment[name]!,
      ...environment,
    },
    stdoutEncoding: const Utf8Codec(allowMalformed: true),
    stderrEncoding: const Utf8Codec(allowMalformed: true),
  );
  for (final w in watched) {
    for (final (where, text) in [('stdout', r.stdout), ('stderr', r.stderr)]) {
      if (text.toString().contains(w.value)) {
        fail(
          'leak-sealed: the value of `${w.name}` reached $where of '
          '$executable',
        );
      }
    }
  }
  return r;
}

/// `chmod +x` [path], sealed.
void makeExecutable(String path) {
  final r = Process.runSync(
    '/bin/chmod',
    ['+x', path],
    includeParentEnvironment: false,
    environment: const {},
  );
  if (r.exitCode != 0) fail('chmod +x $path failed: ${r.stderr}');
}

/// The first executable called [name] on `PATH`, as `command -v` would find
/// it, or null.
String? findOnPath(String name) {
  for (final dir in (Platform.environment['PATH'] ?? '').split(':')) {
    if (dir.isEmpty) continue;
    final candidate = File('$dir/$name');
    if (!candidate.existsSync()) continue;
    // Any execute bit.
    if (candidate.statSync().mode & 0x49 != 0) return candidate.path;
  }
  return null;
}
