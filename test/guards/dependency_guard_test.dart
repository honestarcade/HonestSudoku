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
      expect(policy.matches('ads_helper'), 'ads_*');
      expect(policy.matches('flutter_ads_helper'), '*_ads_*');
      expect(policy.matches('my_analytics_thing'), '*analytics*');
      expect(policy.matches('firebase_anything'), 'firebase_*');
    });

    test('the ads shapes mean advertising, not the letters a-d-s', () {
      // The glob was `*ads_*` and `*ads`, which matched any name containing
      // those three letters. Anchoring each end to an underscore, or to the
      // start of the name, is the difference between a shape and a spelling
      // (#97).
      for (final innocent in ['gamepads', 'gamepads_android', 'threads']) {
        expect(
          policy.matches(innocent),
          isNull,
          reason: 'ads-shape: $innocent has nothing to do with advertising',
        );
      }
      for (final real in [
        'google_mobile_ads',
        'ads_helper',
        'flutter_ads_helper',
        'admob_flutter',
        'yandex_mobileads',
      ]) {
        expect(
          policy.matches(real),
          isNotNull,
          reason: 'ads-shape: $real must still be refused',
        );
      }
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

    // #94. Verification probed the blocklist and found fifteen ads, analytics
    // and network packages walking through it, including `webview_flutter`,
    // which embeds a whole browser. The originals matched #15's acceptance
    // criteria exactly, so this list is what was specified rather than what
    // was needed.
    //
    // The allow list below matters at least as much. A broad glob like
    // `*webview*` or `googleapis*` is how a blocklist starts refusing ordinary
    // packages, and a guard that cries wolf gets deleted. Both halves are
    // asserted, always together.
    test('the named ads, analytics and network packages are refused', () {
      const mustBlock = [
        'webview_flutter',
        'flutter_inappwebview',
        'googleapis',
        'googleapis_auth',
        'supabase_flutter',
        'socket_io_client',
        'graphql_flutter',
        'http2',
        'cronet_http',
        'facebook_app_events',
        'admob_flutter',
        'adjust_sdk',
        'yandex_mobileads',
        'retrofit',
        'chopper',
        'flutter_branch_sdk',
        'appmetrica_plugin',
        'sentry_dio',
        // The ones that were already covered, kept so a future edit that
        // narrows a glob cannot quietly drop them.
        'firebase_analytics',
        'google_mobile_ads',
        'http',
        'dio',
        'sentry_flutter',
      ];
      final open = mustBlock.where((n) => policy.matches(n) == null).toList();
      expect(
        open,
        isEmpty,
        reason: describeOffenders(
          'blocklist-coverage',
          open.map((n) => '$n is not blocked — invariant 1').toList(),
        ),
      );
    });

    test('the known-ordinary list is exercised, name by name', () {
      // #97's whole lesson: the allow-list had seventeen names and not one
      // ended in `ads`, so the glob's complement was never asserted. The
      // same omission applied to *tracking* and *attribution*, which had no
      // complement at all. Every name below was found by running the
      // patterns over the complete pub.dev list and then read (#113).
      final refused = <String>[];
      for (final name in policy.knownOrdinary) {
        final reason = policy.matches(name);
        if (reason != null) refused.add('$name refused by "$reason"');
      }
      expect(
        refused,
        isEmpty,
        reason: describeOffenders('known-ordinary', refused),
      );
    });

    test('the allowlist softens a glob and never a named block', () {
      // It is consulted after blockedNames, so it cannot be used to
      // un-block something deliberately named.
      expect(
        policy.matches('eye_tracking'),
        isNull,
        reason: 'a glob false positive must be allowed through',
      );
      expect(
        policy.matches('firebase_analytics'),
        isNotNull,
        reason: 'a real tracker must still be refused',
      );
      expect(
        policy.matches('affise_attribution_lib'),
        isNotNull,
        reason:
            'the affise_attribution_* family is 15 of the 29 *attribution* '
            'matches and is exactly what that glob exists to stop',
      );
      expect(
        policy.matches('kochava_measurement_google_tracking'),
        isNotNull,
        reason: 'an attribution SDK ending in _tracking must be refused',
      );
      expect(
        policy.matches('app_tracking_transparency'),
        isNull,
        reason:
            "iOS's consent PROMPT is the opposite of a tracker, and the "
            'glob refused it',
      );
    });

    test('the blocklist does not refuse ordinary packages', () {
      const mustAllow = [
        'path_provider',
        'shared_preferences',
        'shared_preferences_android',
        'collection',
        'intl',
        'meta',
        'vector_math',
        'characters',
        'material_color_utilities',
        'async',
        'clock',
        'fake_async',
        'flutter_lints',
        // Plausible future additions this app may actually want.
        'audioplayers',
        'just_audio',
        'flutter_svg',
        'share_plus',
        // The case that mattered and was missing: this list had seventeen
        // names and not one ended in `ads`, so the `*ads` glob's complement
        // was never asserted and it refused a real package from the Flame
        // team, its three platform packages, and two more besides (#97).
        'gamepads',
        'gamepads_android',
        'gamepads_darwin',
        'gamepads_linux',
        'downloads_path_provider',
        'threads',
        'flame',
      ];
      final refused = <String>[];
      for (final name in mustAllow) {
        final reason = policy.matches(name);
        if (reason != null) refused.add('$name refused by "$reason"');
      }
      expect(
        refused,
        isEmpty,
        reason: describeOffenders('blocklist-overshoot', refused),
      );
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

    // The rest of this group is #83. The assertion above never called a rule
    // and tested a filename that will never exist, and the probe it stood in
    // for is unreachable anyway: `flutter test` runs an implicit `pub get`,
    // which regenerates a deleted `pubspec.lock` before a test loads. So
    // deleting the file and watching the suite pass proves nothing about the
    // guard.
    //
    // The reachable hole is one layer down. `lockOffenders` scans the
    // `packages:` section, so a lockfile with no such section — empty,
    // truncated, half-written — yields no packages and therefore no offenders,
    // and reads exactly like a clean one. That is the blocklist failing open.

    test('a blocklisted direct dependency is labelled direct', () {
      // With the pubspec collapsed by lone-CR endings the direct set was
      // empty, so a DIRECT blocklisted package was reported as
      // `http (transitive)` — the mislabel #79 and #96 both reported, and
      // the one that makes the finding read as someone else's problem
      // (#112).
      const pubspec =
          'name: honest_sudoku\n'
          'environment:\n'
          '  sdk: ^3.0.0\n'
          'dependencies:\n'
          '  flutter:\n'
          '    sdk: flutter\n'
          '  http: ^1.0.0\n';
      const lock =
          'packages:\n'
          '  http:\n'
          '    dependency: "direct main"\n'
          '    version: "1.0.0"\n'
          'sdks:\n';
      for (final entry in {
        'LF': pubspec,
        'CRLF': pubspec.replaceAll('\n', '\r\n'),
        'lone CR': pubspec.replaceAll('\n', '\r'),
      }.entries) {
        final offenders = lockOffenders(lock, entry.value);
        expect(offenders.map((o) => o.what), [
          'http (direct)',
        ], reason: '${entry.key}: a direct dependency must read as direct');
      }
    });

    test('the real pubspec passes its own preconditions', () {
      final offenders = pubspecPreconditions(readFile('pubspec.yaml'));
      expect(
        offenders,
        isEmpty,
        reason: describeOffenders(
          'pubspec-scannable',
          offenders.map((o) => o.toString()).toList(),
        ),
      );
    });

    test('a pubspec the rules cannot read is an offender, not silence', () {
      // #96 was filed because a CRLF pubspec silenced every dependency rule.
      // Its fix normalised by DELETING carriage returns, so a file with lone
      // `\r` endings collapsed into one line and the guard went silent
      // again — with path_provider in the lockfile and 190 tests green
      // (#112). normaliseText now translates; this is the backstop.
      for (final entry in {
        'empty': '',
        'whitespace only': '   \n  \n',
        'not a pubspec':
            'hello: world\nand: more\nlines: here\n'
            'to: pass\nthe: length check\n',
      }.entries) {
        expect(
          pubspecPreconditions(entry.value),
          isNotEmpty,
          reason: 'pubspec-scannable: "${entry.key}" scanned as clean',
        );
      }
    });

    test('lone-CR line endings no longer collapse the file', () {
      // The complement of the above: with translation, the rules read a
      // lone-CR pubspec exactly as they read the real one.
      final real = readFile('pubspec.yaml');
      expect(
        pubspecPreconditions(real.replaceAll('\n', '\r')),
        isEmpty,
        reason:
            'with translation a lone-CR pubspec is readable; if this fires '
            'again the normalisation has regressed to deleting',
      );
      expect(
        normaliseText(real.replaceAll('\n', '\r')),
        normaliseText(real),
        reason:
            'a lone-CR pubspec must normalise to the same text as the real '
            'one, or every rule below scans a different document',
      );
    });

    test('the real lockfile passes its own preconditions', () {
      final offenders = lockfilePreconditions(readFile('pubspec.lock'));
      expect(
        offenders,
        isEmpty,
        reason: describeOffenders(
          'lockfile-scannable',
          offenders.map((o) => o.toString()).toList(),
        ),
      );
    });

    test('an empty lockfile is refused rather than read as clean', () {
      expect(
        lockOffenders('', readFile('pubspec.yaml')),
        isEmpty,
        reason: 'the hole itself: the blocklist finds nothing in nothing',
      );
      expect(
        lockfilePreconditions('').map((o) => o.what),
        contains('empty'),
        reason:
            'lockfile-empty: which is why the precondition, not the '
            'blocklist, is what catches it',
      );
    });

    test('a lockfile with no packages: section is refused', () {
      const headerless = '''
sdks:
  dart: ">=3.0.0"
''';
      expect(lockOffenders(headerless, readFile('pubspec.yaml')), isEmpty);
      expect(
        lockfilePreconditions(headerless).single.what,
        contains('packages:'),
      );
    });

    test('a truncated lockfile is refused', () {
      const truncated = '''
packages:
  async:
    dependency: transitive
    version: "2.11.0"
sdks:
  dart: ">=3.0.0"
''';
      expect(
        lockfilePreconditions(truncated).single.what,
        contains('1 locked packages'),
        reason: 'lockfile-truncated: one package is not a resolved Flutter app',
      );
    });

    test('the precondition counts packages, not lines', () {
      final names = lockedPackageNames(readFile('pubspec.lock'));
      expect(
        names,
        contains('flutter_lints'),
        reason:
            'lockfile-names: a dev dependency that is really in the lockfile',
      );
      expect(
        names,
        isNot(contains('dart')),
        reason:
            'lockfile-names: `dart` is an entry under sdks:, past the end of '
            'the section the blocklist scans — counting it would let a '
            'lockfile that stops at sdks: look populated',
      );
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

    test('a four-space pubspec still labels a direct dependency direct', () {
      const lock = '''
packages:
  http:
    dependency: "direct main"
    version: "1.2.0"
sdks:
  dart: ">=3.0.0"
''';
      const pubspec = '''
dependencies:
    http: ^1.2.0  # why: fixture
''';
      final offenders = lockOffenders(lock, pubspec);
      expect(offenders, hasLength(1));
      expect(
        offenders.single.what,
        contains('direct'),
        reason:
            'indentation must not turn a direct dependency into a '
            'transitive one — the label is what tells you whose fault it is',
      );
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

    // The three bypasses #79 found. Each was a legal pubspec that flutter
    // pub get accepts, and each made the rule silently see nothing. They are
    // fixtures rather than one-off checks because the rule's earlier fixtures
    // only ever fed it canonically formatted input, which is precisely why the
    // holes were invisible.
    test(
      'a trailing comment on the section header does not disable the rule',
      () {
        const pubspec = '''
dependencies: # app deps
  flutter:
    sdk: flutter
  path_provider: ^2.1.0
''';
        final offenders = unjustifiedDependencies(pubspec);
        expect(
          offenders,
          hasLength(1),
          reason: 'a commented section header must not hide its dependencies',
        );
        expect(offenders.single.what, 'path_provider');
      },
    );

    test('a commented dependency_overrides header is still refused', () {
      const pubspec = '''
dependencies:
  flutter:
    sdk: flutter
dependency_overrides:  # sneaky
  collection: 1.0.0
''';
      expect(
        unjustifiedDependencies(pubspec).map((o) => o.what),
        contains('dependency_overrides'),
      );
    });

    // #86. Three passes at this rule each closed the spellings they were
    // shown, and each time another legal one turned up. These fixtures are
    // the five that were still open, plus the controls that stop the fix
    // overshooting — because the rule now refuses shapes it cannot read, and
    // a rule that refuses too much gets switched off just as fast.

    // #96. The fail-closed strategy #86 claimed was general was applied to
    // section headers and to LF text only. Two shapes still read as empty.

    test('CRLF line endings do not silence the rule', () {
      // Dart's `.` excludes \r and its non-multiline `$` anchors before it, so
      // under CRLF every top-level line failed to parse and the whole rule
      // went quiet — no justification check, no overrides refusal, and a
      // direct dependency relabelled transitive. A Windows clone with
      // core.autocrlf produces this by accident.
      const lf =
          'name: x\n'
          'dependencies:\n'
          '  flutter:\n'
          '    sdk: flutter\n'
          '  path_provider: ^2.1.0\n'
          'dependency_overrides:\n'
          '  collection: 1.0.0\n';
      final crlf = lf.replaceAll('\n', '\r\n');

      final lfNames = unjustifiedDependencies(lf).map((o) => o.what).toSet();
      final crlfNames = unjustifiedDependencies(crlf)
          .map((o) => o.what)
          .toSet();
      expect(
        crlfNames,
        lfNames,
        reason:
            'crlf: the same pubspec with Windows line endings must produce '
            'the same offenders. It produced none (#96).',
      );
      expect(crlfNames, contains('path_provider'));
      expect(crlfNames, contains('dependency_overrides'));
    });

    test('a byte-order mark does not silence the rule', () {
      const withBom = '﻿name: x\ndependencies:\n  path_provider: ^2.1.0\n';
      expect(
        unjustifiedDependencies(withBom).map((o) => o.what),
        contains('path_provider'),
      );
    });

    test('the direct/transitive label survives CRLF', () {
      // The mislabel is the tell that the section walk went blind, and it is
      // the same symptom #79 reported. Asserted separately because the
      // offender list alone would not show it.
      const lock =
          'packages:\n'
          '  http:\n'
          '    dependency: "direct main"\n'
          '    version: "1.2.0"\n'
          'sdks:\n'
          '  dart: ">=3.0.0"\n';
      const pubspec = 'dependencies:\n  http: ^1.2.0  # why: fixture\n';
      final offenders = lockOffenders(
        lock.replaceAll('\n', '\r\n'),
        pubspec.replaceAll('\n', '\r\n'),
      );
      expect(offenders, hasLength(1));
      expect(
        offenders.single.what,
        contains('direct'),
        reason:
            'crlf-label: under CRLF the direct dependency was reported as '
            'transitive, because _directDependencyNames came back empty',
      );
    });

    test('a YAML explicit key inside a section is refused', () {
      // The fail-closed refusal guarded the section header and never looked
      // inside; _sectionEntries silently skipped what it could not parse.
      const pubspec =
          'name: x\n'
          'dependencies:\n'
          '  flutter:\n'
          '    sdk: flutter\n'
          '  ? path_provider\n'
          '  : ^2.1.0\n';
      final offenders = unreadableSectionEntries(pubspec);
      expect(
        offenders,
        isNotEmpty,
        reason:
            'explicit-key: `flutter pub get` installs this and the guard saw '
            'nothing (#96)',
      );
      expect(offenders.first.why, contains('unreadable shape'));
      expect(
        unjustifiedDependencies(pubspec).map((o) => o.what),
        contains('? path_provider'),
      );
    });

    test('legal entry shapes are not refused', () {
      // The controls. Refusing a multi-line dependency or an asset list would
      // undo #79's fix in the name of #96's, and a guard that refuses ordinary
      // pubspecs gets deleted.
      for (final pubspec in const [
        // A git dependency with its justification on the key line.
        'name: x\n'
            'dependencies:\n'
            '  pkg: # why: needed\n'
            '    git:\n'
            '      url: https://e.com/r.git\n'
            '      ref: main\n',
        // An asset list, which lives under flutter: and not under a
        // dependency section.
        'name: x\n'
            'dependencies:\n'
            '  path_provider: ^2.1.0  # why: ok\n'
            'flutter:\n'
            '  assets:\n'
            '    - assets/a.png\n',
        // Four-space indentation, from #79.
        'name: x\ndependencies:\n    path_provider: ^2.1.0  # why: ok\n',
      ]) {
        expect(
          unreadableSectionEntries(pubspec),
          isEmpty,
          reason: 'entries-negative: refused a legal shape:\n$pubspec',
        );
        expect(
          unjustifiedDependencies(pubspec),
          isEmpty,
          reason: 'entries-negative: offended on a clean pubspec:\n$pubspec',
        );
      }
    });

    test('the real pubspec and lockfile survive normalisation', () {
      expect(unreadableSectionEntries(readFile('pubspec.yaml')), isEmpty);
      expect(
        unjustifiedDependencies(
          readFile('pubspec.yaml').replaceAll('\n', '\r\n'),
        ),
        isEmpty,
        reason: 'the repository pubspec must be clean under either line ending',
      );
    });

    test('the repository pins line endings', () {
      // Belt and braces: the rules normalise, and git normalises the working
      // tree so the file a contributor edits is the file CI reads.
      expect(
        pathExists('.gitattributes'),
        isTrue,
        reason:
            'gitattributes: absent, so a Windows clone can still produce '
            'CRLF sources (#96)',
      );
      expect(readFile('.gitattributes'), contains('text=auto eol=lf'));
    });

    test('a quoted section header does not hide the section', () {
      const pubspec =
          '"dependencies":\n'
          '  flutter:\n'
          '    sdk: flutter\n'
          '  path_provider: ^2.1.0\n';
      expect(
        unjustifiedDependencies(pubspec).map((o) => o.what),
        contains('path_provider'),
        reason:
            'quoted-header: `"dependencies":` is legal YAML that `flutter pub '
            'get --enforce-lockfile` accepts, and it hid the whole block (#86)',
      );
    });

    for (final quote in ['"', "'"]) {
      final kind = quote == '"' ? 'double' : 'single';
      test('a $kind-quoted entry key is seen', () {
        final pubspec =
            'dependencies:\n'
            '  flutter:\n'
            '    sdk: flutter\n'
            '  ${quote}path_provider$quote: ^2.1.0\n';
        expect(
          unjustifiedDependencies(pubspec).map((o) => o.what),
          contains('path_provider'),
        );
      });
    }

    // The three below are not "spellings the rule now knows". They are shapes
    // it deliberately refuses, which is the difference that makes this the
    // last fix of its kind rather than the fourth.
    final unreadable = {
      'a flow mapping': 'dependencies: {path_provider: ^2.1.0}\n',
      'an anchor': 'dependencies: &deps\n  path_provider: ^2.1.0\n',
      'an alias':
          'extra: &deps\n  path_provider: ^2.1.0\ndependencies: *deps\n',
    };
    for (final entry in unreadable.entries) {
      test('${entry.key} on a dependency section is refused', () {
        final offenders = unreadableDependencySections(entry.value);
        expect(
          offenders,
          hasLength(1),
          reason:
              'unreadable-${entry.key}: a section this rule cannot parse must '
              'be refused, not read as empty (#86)',
        );
        expect(offenders.single.why, contains('unreadable shape'));
        // And the refusal reaches the rule invariant 3 actually depends on.
        expect(
          unjustifiedDependencies(entry.value).map((o) => o.what),
          contains(startsWith('dependencies:')),
        );
      });
    }

    test('a plain block opener is not refused', () {
      // The control that stops the refusal overshooting. A commented header
      // and an ordinary block must both stay readable, or #79's fix is undone
      // by #86's.
      for (final pubspec in const [
        'dependencies:\n  path_provider: ^2.1.0  # why: fixture\n',
        'dependencies: # app deps\n  path_provider: ^2.1.0  # why: fixture\n',
        'dependencies:\n  flutter:\n    sdk: flutter\n',
      ]) {
        expect(
          unreadableDependencySections(pubspec),
          isEmpty,
          reason: 'not-overshooting: refused a readable section:\n$pubspec',
        );
        expect(
          unjustifiedDependencies(pubspec),
          isEmpty,
          reason: 'not-overshooting: offended on a clean section:\n$pubspec',
        );
      }
    });

    test('a non-dependency key with a value on the line is ignored', () {
      // `version: 1.0.0+1` and `publish_to: 'none'` are top-level keys with
      // inline values. Refusing those would fail every pubspec ever written.
      expect(
        unreadableDependencySections(
          "name: honest_sudoku\nversion: 1.0.0+1\npublish_to: 'none'\n",
        ),
        isEmpty,
      );
    });

    test('the real pubspec is readable', () {
      expect(
        unreadableDependencySections(readFile('pubspec.yaml')),
        isEmpty,
        reason: "the repository's own pubspec must not trip the new refusal",
      );
    });

    test('dependency_overrides entries need justification too', () {
      const pubspec = '''
dependencies:
  flutter:
    sdk: flutter
dependency_overrides:
  collection: 1.0.0
''';
      // Two offenders: the section itself, and the unjustified entry inside it.
      // An override can swap any package for another, so it is the last place
      // an unexplained entry should be allowed.
      final offenders = unjustifiedDependencies(pubspec);
      expect(offenders.map((o) => o.what), contains('dependency_overrides'));
      expect(offenders.map((o) => o.what), contains('collection'));
    });

    test('indentation other than two spaces does not escape the rule', () {
      const pubspec = '''
dependencies:
    flutter:
        sdk: flutter
    path_provider: ^2.1.0
''';
      final offenders = unjustifiedDependencies(pubspec);
      expect(
        offenders,
        hasLength(1),
        reason: 'four-space keys are valid YAML and must still be seen',
      );
      expect(offenders.single.what, 'path_provider');
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

    // #90. The list was matched with `\bSocket\b`, which correctly spared
    // `mySocketName` and equally spared `SecureSocket` — the canonical way to
    // open a TLS connection in Dart, and the name a developer reaches for
    // first. The boundary is now on the START of the match only, so an
    // identifier may end in a listed word but not begin before one.
    //
    // Both directions matter. A rule that starts matching `mySocketName` gets
    // switched off as fast as one that misses `SecureSocket`, so the true
    // negatives below are load-bearing, not decoration.
    for (final entry in const {
      'SecureSocket.connect(h, 443);': 'SecureSocket',
      'RawSecureSocket.connect(h, 443);': 'RawSecureSocket',
      'ServerSocket.bind(a, 80);': 'ServerSocket',
      'HttpServer.bind(a, 80);': 'HttpServer',
      "InternetAddress('1.1.1.1');": 'InternetAddress',
      'Socket.connect(h, 80);': 'Socket',
      'io.HttpClient();': 'HttpClient',
      // Missed by the suffix rule: `_Socket` fell between the lookbehind and
      // the uppercase-prefix branch (#98).
      '_Socket x;': 'Socket',
      '_HttpClient y;': 'HttpClient',
      'SecureServerSocket.bind(a, 1);': 'SecureServerSocket',
    }.entries) {
      test('the source rule catches ${entry.value}', () {
        final offenders = sourceOffenders('lib/x.dart', entry.key);
        expect(
          offenders.map((o) => o.what),
          contains(entry.value),
          reason:
              'dartio-${entry.value}: `${entry.key}` opens a network '
              'connection and must not scan clean (#90)',
        );
      });
    }

    for (final innocent in const [
      'final mySocketName = 1;',
      'class WebSocketish {}',
      'const socket = 2;',
      'var internetAddressBook = 3;',
      "const label = 'Rocket';",
      // What a test file is full of. The suffix rule flagged all four, and a
      // guard that fails on the test doubles for the thing it guards against
      // is one a contributor learns to route around (#98).
      'class MockSocket {}',
      'class FakeHttpClient {}',
      'class TestWebSocket {}',
      'class MySecurityContext {}',
      'class BluetoothSocket {}',
    ]) {
      test('the source rule leaves `$innocent` alone', () {
        expect(
          sourceOffenders('lib/x.dart', innocent),
          isEmpty,
          reason:
              'dartio-negative: the suffix rule started matching an innocent '
              'identifier, which is how a guard gets switched off',
        );
      });
    }

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

  test('the newly listed dart:io connectors are refused', () {
    // #98 listed thirteen names. These open connections and were not on
    // the list (#118).
    for (final name in const [
      'RawSynchronousSocket',
      'RawSecureServerSocket',
      'WebSocketTransformer',
      'HttpOverrides',
      'IOOverrides',
      'NetworkInterface',
      'ConnectionTask',
    ]) {
      expect(
        sourceOffenders('lib/x.dart', 'final x = $name.something();\n'),
        isNotEmpty,
        reason: 'dart-io: $name is not refused',
      );
    }
  });

  test("importing dart:io in lib/ is refused outright", () {
    // The class list is a floor: no name list catches
    // Process.run('curl', [url]). Banning the import is one line and
    // catches every one of them, at the cost of refusing legitimate file
    // IO — which this app does not do (#118).
    expect(
      sourceOffenders('lib/main.dart', "import 'dart:io';\n"),
      isNotEmpty,
      reason: 'dart-io-import: the import is not refused',
    );
    expect(
      sourceOffenders('lib/main.dart', 'import "dart:io";\n'),
      isNotEmpty,
      reason: 'dart-io-import: the double-quoted spelling passes',
    );
    // The complement, twice over: the ban is scoped to lib/, and a
    // mention that is not an import is not an import.
    expect(
      sourceOffenders('test/guards/x.dart', "import 'dart:io';\n"),
      isEmpty,
      reason:
          'dart-io-import: the guards read files for a living and must '
          'not be refused',
    );
    expect(
      sourceOffenders('lib/x.dart', "// we deliberately avoid dart:io\n"),
      isEmpty,
      reason: 'dart-io-import: a comment is not an import',
    );
  });

  test('the real lib/ imports no dart:io', () {
    // The rule is worth nothing if the tree already breaches it.
    final offenders = <String>[];
    for (final f
        in Directory('${repoRoot.path}/lib')
            .listSync(recursive: true)
            .whereType<File>()
            .where((f) => f.path.endsWith('.dart'))) {
      final rel = f.path.replaceFirst('${repoRoot.path}/', '');
      offenders.addAll(
        sourceOffenders(rel, f.readAsStringSync()).map((o) => o.toString()),
      );
    }
    expect(offenders, isEmpty, reason: describeOffenders('lib', offenders));
  });

  test('an underscore-joined name is not the dart:io class', () {
    // The boundary allowed a leading underscore anywhere, so `Test_Socket`
    // and `A_HttpClient` were flagged — the same overshoot as the
    // `MockSocket` bug it was written to fix (#98, #118).
    for (final ok in const [
      'final x = Test_Socket();',
      'final x = A_HttpClient();',
      'class My_WebSocket {}',
    ]) {
      expect(
        sourceOffenders('lib/x.dart', '$ok\n'),
        isEmpty,
        reason: 'dart-io-boundary: refused `$ok`',
      );
    }
    // The complement: a genuinely private dart:io class still is one.
    expect(
      sourceOffenders('lib/x.dart', 'final x = _Socket();\n'),
      isNotEmpty,
      reason: 'dart-io-boundary: `_Socket` must still be caught',
    );
  });
}
