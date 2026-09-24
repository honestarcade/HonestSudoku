@Tags(['guard'])
library;

// The engine stays plain Dart: no Flutter, no dart:ui or dart:io, no
// third-party package, no relative import out of lib/engine/, no dart:math
// `Random` (its PRNG is seeded), and no clock or timer outside the off-thread
// wrapper (generation depends on the seed alone). Each rule is first shown to fire
// on an inline fixture, then run over every file under lib/engine/, tracked
// or not.

import 'package:flutter_test/flutter_test.dart';

import 'engine_rules.dart';
import 'repo_files.dart';

void main() {
  group('the imports rule', () {
    const path = 'lib/engine/tmp.dart';

    test('refuses Flutter, dart:ui, dart:io and third-party packages', () {
      const source = '''
import 'package:flutter/material.dart';
import 'dart:ui';
import "dart:io";
export 'package:collection/collection.dart';
import 'package:honest_sudoku/engine/grid.dart';
''';
      expect(engineImportOffenders(path, source), hasLength(5));
    });

    test('allows core libraries, package:meta and relative engine files', () {
      const source = '''
import 'dart:math';
import 'dart:typed_data';
import 'dart:isolate';
import 'package:meta/meta.dart';
import 'grid.dart';
import 'techniques/../units.dart';
part 'tmp_part.dart';
''';
      expect(engineImportOffenders(path, source), isEmpty);
    });

    test('refuses a relative import that leaves lib/engine/', () {
      expect(engineImportOffenders(path, "import '../ui/app.dart';"), [
        '$path: ../ui/app.dart (leaves lib/engine/)',
      ]);
      expect(
        engineImportOffenders(
          'lib/engine/techniques/x.dart',
          "import '../../main.dart';",
        ),
        hasLength(1),
      );
    });

    test('checks every branch of a conditional import', () {
      const source = '''
import 'grid.dart'
    if (dart.library.io) 'package:flutter/foundation.dart';
''';
      expect(engineImportOffenders(path, source), [
        '$path: package:flutter/foundation.dart',
      ]);
    });

    test('ignores directives inside comments', () {
      const source = '''
// import 'package:flutter/material.dart';
/* import 'dart:io'; */
''';
      expect(engineImportOffenders(path, source), isEmpty);
    });
  });

  group('the Random rule', () {
    test('fires on a Random reference and not on one in a comment', () {
      expect(
        engineRandomOffenders('x.dart', 'final r = Random(4);\n// Random'),
        ['x.dart:1: final r = Random(4);'],
      );
      expect(engineRandomOffenders('x.dart', '/// uses no Random'), isEmpty);
      expect(engineRandomOffenders('x.dart', 'final randomish = 1;'), isEmpty);
    });
  });

  group('the clock rule', () {
    test('fires on each clock and timer form, outside the wrapper only', () {
      for (final form in engineClockForms) {
        expect(
          engineClockOffenders('lib/engine/x.dart', 'final a = $form'),
          hasLength(1),
          reason: form,
        );
        expect(
          engineClockOffenders(engineClockAllowed, 'final a = $form'),
          isEmpty,
        );
      }
      expect(
        engineClockOffenders('lib/engine/x.dart', '// DateTime.now()'),
        isEmpty,
      );
    });

    test('the wrapper may use the clock but still never Random', () {
      expect(
        engineRandomOffenders(engineClockAllowed, 'final r = Random();'),
        hasLength(1),
      );
    });
  });

  group('lib/engine/', () {
    final files = filesUnder('lib/engine')
        .where((p) => p.endsWith('.dart'))
        .toList();

    test('holds engine files to check', () {
      expect(
        files,
        contains('lib/engine/engine.dart'),
        reason:
            'engine-imports: lib/engine/ has no engine.dart, so the scans '
            'below would pass by reading nothing',
      );
    });

    test('imports nothing outside the allowlist', () {
      final offenders = [
        for (final f in files) ...engineImportOffenders(f, readFile(f)),
      ];
      expect(
        offenders,
        isEmpty,
        reason: describeOffenders('engine-imports', offenders),
      );
    });

    test('never references dart:math Random', () {
      final offenders = [
        for (final f in files) ...engineRandomOffenders(f, readFile(f)),
      ];
      expect(
        offenders,
        isEmpty,
        reason: describeOffenders('engine-random', offenders),
      );
    });

    test('uses no clock or timer outside the off-thread wrapper', () {
      final offenders = [
        for (final f in files) ...engineClockOffenders(f, readFile(f)),
      ];
      expect(
        offenders,
        isEmpty,
        reason: describeOffenders('engine-clock', offenders),
      );
    });
  });
}
