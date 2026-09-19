@Tags(['guard'])
library;

// Guard for #15 and project invariants 1 and 3.
//
// Three rules: no blocklisted package reaches the lockfile, every third-party
// dependency says why it is there, and no source file under lib/ references a
// web font service or a socket.
//
// Each rule is exercised twice — against the repository's real files, and
// against inline fixtures that must fail. The fixtures are the point: a rule
// only ever run against a clean repository has never been shown to fire.
//
// What this does NOT cover: a package that makes network calls under an
// innocent name. #14 catches that at the other end — with no INTERNET
// permission, the socket call fails at the OS. The two guards are one policy.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'dependency_policy.dart' as policy;
import 'dependency_rules.dart';
import 'repo_files.dart';

void main() {
  group('the policy itself', () {
    test('refuses by exact name, case-insensitively', () {
      expect(policy.matches('http'), 'http');
      expect(policy.matches('HTTP'), 'http');
      expect(policy.matches('sentry_flutter'), 'sentry_flutter');
    });

    test('refuses by shape', () {
      expect(policy.matches('some_ads'), '*_ads');
      expect(policy.matches('ads_helper'), '*ads_*');
      expect(policy.matches('my_analytics_thing'), '*analytics*');
      expect(policy.matches('firebase_anything'), 'firebase_*');
    });

    test('allows what it should', () {
      // url_launcher is deliberately not blocked: opening a link in the system
      // browser needs no permission. path_provider is the other plugin this
      // project has approved.
      for (final allowed in [
        'url_launcher',
        'path_provider',
        'meta',
        'collection',
        'flutter',
      ]) {
        expect(
          policy.matches(allowed),
          isNull,
          reason: '$allowed must be allowed',
        );
      }
    });

    test('exempting from justification never exempts from the blocklist', () {
      // A name on both lists must still be refused. Nothing is today; this
      // asserts the relationship rather than the current data.
      for (final exempt in policy.exemptFromJustification) {
        if (policy.blockedNames.contains(exempt)) {
          fail('$exempt is both exempt and blocked — the blocklist must win');
        }
      }
    });
  });

  group('lockfile rule', () {
    test('the real lockfile contains no blocklisted package', () {
      final offenders = lockOffenders(
        readFile('pubspec.lock'),
        readFile('pubspec.yaml'),
      );
      expect(
        offenders,
        isEmpty,
        reason: describeOffenders(
          'blocklist',
          offenders.map((o) => o.toString()).toList(),
        ),
      );
    });

    test('a missing lockfile is a hard failure, not a skip', () {
      expect(() => readFile('pubspec.lock.does-not-exist'), throwsStateError);
    });

    test('fires on a direct blocklisted package', () {
      const lock = '''
packages:
  http:
    dependency: "direct main"
    source: hosted
    version: "1.2.0"
sdks:
  dart: ">=3.0.0"
''';
      const pubspec = '''
dependencies:
  http: ^1.2.0  # why: test fixture
''';
      final offenders = lockOffenders(lock, pubspec);
      expect(offenders, hasLength(1));
      expect(offenders.single.what, contains('http'));
      expect(offenders.single.what, contains('direct'));
    });

    test('fires on a transitive blocklisted package, and labels it so', () {
      const lock = '''
packages:
  some_wrapper:
    dependency: "direct main"
    version: "1.0.0"
  firebase_analytics:
    dependency: transitive
    version: "10.0.0"
sdks:
  dart: ">=3.0.0"
''';
      const pubspec = '''
dependencies:
  some_wrapper: ^1.0.0  # why: test fixture
''';
      final offenders = lockOffenders(lock, pubspec);
      expect(offenders, hasLength(1));
      expect(offenders.single.what, contains('transitive'));
    });

    test('stops at sdks: and does not scan past it', () {
      const lock = '''
packages:
  collection:
    dependency: transitive
    version: "1.0.0"
sdks:
  http: ">=1.0.0"
''';
      // `http` appears only under sdks:, where it is a version constraint and
      // not a package. Scanning past the boundary would report it.
      expect(lockOffenders(lock, 'dependencies:\n'), isEmpty);
    });
  });

  group('justification rule', () {
    test('every real dependency is justified or exempt', () {
      final offenders = unjustifiedDependencies(readFile('pubspec.yaml'));
      expect(
        offenders,
        isEmpty,
        reason: describeOffenders(
          'justification',
          offenders.map((o) => o.toString()).toList(),
        ),
      );
    });

    test('fires on an unjustified dependency', () {
      const pubspec = '''
dependencies:
  flutter:
    sdk: flutter
  path_provider: ^2.1.0
''';
      final offenders = unjustifiedDependencies(pubspec);
      expect(offenders, hasLength(1));
      expect(offenders.single.what, 'path_provider');
    });

    test('accepts a justified dependency, including a multi-line one', () {
      const pubspec = '''
dependencies:
  path_provider: ^2.1.0  # why: the store needs a documents directory
  something:  # why: justified on the key line, as required
    hosted: https://example.com
''';
      expect(unjustifiedDependencies(pubspec), isEmpty);
    });

    test('an empty `# why:` does not count as a justification', () {
      const pubspec = '''
dependencies:
  path_provider: ^2.1.0  # why:
''';
      expect(unjustifiedDependencies(pubspec), hasLength(1));
    });

    test('refuses a dependency_overrides section outright', () {
      const pubspec = '''
dependencies:
  flutter:
    sdk: flutter
dependency_overrides:
  collection: 1.0.0
''';
      final offenders = unjustifiedDependencies(pubspec);
      expect(offenders.map((o) => o.what), contains('dependency_overrides'));
    });

    test('exempt packages need no justification', () {
      const pubspec = '''
dependencies:
  flutter:
    sdk: flutter
dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: ^6.0.0
''';
      expect(unjustifiedDependencies(pubspec), isEmpty);
    });
  });

  group('source rule', () {
    test('no file under lib/ references a font service or a socket', () {
      // Walks the filesystem, not `git ls-files`: an uncommitted file under
      // lib/ is still a file this rule must see. (The identity guard walks git
      // instead, because android/ holds build residue this one never does.)
      final offenders = <String>[];
      final libDir = Directory('${repoRoot.path}/lib');
      for (final entity in libDir.listSync(recursive: true)) {
        if (entity is! File) continue;
        final path = entity.path
            .substring(repoRoot.path.length + 1)
            .replaceAll(r'\\', '/');
        if (!isScannedSourceFile(path)) continue;
        offenders.addAll(
          sourceOffenders(path, readFile(path)).map((o) => o.toString()),
        );
      }
      expect(
        offenders,
        isEmpty,
        reason: describeOffenders('source', offenders),
      );
    });

    test('fires on a web font service', () {
      final offenders = sourceOffenders(
        'lib/tmp.dart',
        "const url = 'https://fonts.googleapis.com/css2?family=Outfit';",
      );
      expect(offenders.map((o) => o.what), contains('fonts.googleapis.com'));
    });

    test('fires on dart:io networking', () {
      final offenders = sourceOffenders(
        'lib/tmp.dart',
        'final client = HttpClient();',
      );
      expect(offenders.map((o) => o.what), contains('HttpClient'));
    });

    test('fires on a URL outside lib/links.dart', () {
      final offenders = sourceOffenders(
        'lib/ui/about.dart',
        "const u = 'https://honestarcade.app';",
      );
      expect(offenders.map((o) => o.what), contains('https://'));
    });

    test('allows URLs inside lib/links.dart', () {
      final offenders = sourceOffenders(
        'lib/links.dart',
        "const u = 'https://honestarcade.app';",
      );
      expect(offenders, isEmpty);
    });

    test('http:// is refused even in lib/links.dart', () {
      final offenders = sourceOffenders(
        'lib/links.dart',
        "const u = 'http://example.com';",
      );
      expect(offenders.map((o) => o.what), contains('http://'));
    });

    test('scans comments too', () {
      final offenders = sourceOffenders(
        'lib/tmp.dart',
        '// TODO: use HttpClient here one day',
      );
      expect(offenders.map((o) => o.what), contains('HttpClient'));
    });

    test('generated files and l10n are skipped', () {
      expect(isScannedSourceFile('lib/thing.g.dart'), isFalse);
      expect(isScannedSourceFile('lib/thing.freezed.dart'), isFalse);
      expect(isScannedSourceFile('lib/l10n/app_en.dart'), isFalse);
      expect(isScannedSourceFile('lib/main.dart'), isTrue);
      expect(isScannedSourceFile('test/whatever.dart'), isFalse);
    });

    test('a word that merely contains an identifier is not an offender', () {
      // `WebSocketish` and `mySocketName` must not fire: the identifiers are
      // matched at word boundaries. Without this the rule would be unusable.
      expect(sourceOffenders('lib/tmp.dart', 'class WebSocketish {}'), isEmpty);
      expect(
        sourceOffenders('lib/tmp.dart', 'final mySocketName = 1;'),
        isEmpty,
      );
    });
  });

  group('lib/links.dart', () {
    test('exists and holds nothing but comments and const strings', () {
      final text = readFile('lib/links.dart');
      final offenders = <String>[];
      final lines = text.split('\n');
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i].trim();
        if (line.isEmpty) continue;
        if (line.startsWith('//')) continue;
        if (line == 'library;') continue;
        if (RegExp(r"^const String [a-zA-Z][A-Za-z0-9_]* = '[^']*';$")
            .hasMatch(line)) {
          continue;
        }
        offenders.add('lib/links.dart:${i + 1}: $line');
      }
      expect(
        offenders,
        isEmpty,
        reason: describeOffenders('links-grammar', offenders),
      );
    });

    test('holds the three About-screen URLs', () {
      final text = readFile('lib/links.dart');
      for (final url in const [
        'https://honestarcade.app',
        'https://honestarcade.app/contribute',
        'https://github.com/honestarcade/HonestSudoku',
      ]) {
        expect(text, contains(url));
      }
    });
  });

  test('the guard files themselves are tracked', () {
    // A guard that is not committed protects nothing.
    for (final path in const [
      'test/guards/dependency_policy.dart',
      'test/guards/dependency_rules.dart',
      'lib/links.dart',
    ]) {
      expect(
        File('${repoRoot.path}/$path').existsSync(),
        isTrue,
        reason: 'missing $path',
      );
    }
  });
}
