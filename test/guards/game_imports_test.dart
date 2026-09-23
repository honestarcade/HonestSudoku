@Tags(['guard'])
library;

// The game model stays plain Dart, like the engine: core Dart and the engine's
// barrel only. No Flutter, no dart:io, no dart:math — seeds come from outside
// the model — and no relative import out of lib/game/. The board screen's
// controller needs Flutter, which is why it lives in lib/ui/, not here.

import 'package:flutter_test/flutter_test.dart';

import 'engine_rules.dart';
import 'repo_files.dart';

const _libraries = {'dart:core', 'dart:collection', 'dart:async'};
const _packages = ['package:meta/', 'package:honest_sudoku/engine/engine.dart'];

List<String> _offenders(String path, String source) => importOffenders(
  path,
  source,
  folder: 'game',
  libraries: _libraries,
  packages: _packages,
);

void main() {
  test('the rule refuses Flutter, dart:math and engine internals, and allows '
      'the engine barrel', () {
    const bad = '''
import 'package:flutter/foundation.dart';
import 'dart:math';
import 'package:honest_sudoku/engine/solver.dart';
import '../ui/board.dart';
''';
    expect(_offenders('lib/game/x.dart', bad), hasLength(4));
    const good = '''
import 'dart:async';
import 'package:honest_sudoku/engine/engine.dart';
import 'notice.dart';
''';
    expect(_offenders('lib/game/x.dart', good), isEmpty);
  });

  test('lib/game/ imports nothing outside the allowlist', () {
    final files = filesUnder('lib/game').where((p) => p.endsWith('.dart'));
    expect(
      files,
      contains('lib/game/game_state.dart'),
      reason:
          'game-imports: lib/game/ has no game_state.dart, so the scan '
          'would pass by reading nothing',
    );
    final offenders = [for (final f in files) ..._offenders(f, readFile(f))];
    expect(
      offenders,
      isEmpty,
      reason: describeOffenders('game-imports', offenders),
    );
  });
}
