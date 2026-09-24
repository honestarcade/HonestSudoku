@Tags(['guard'])
library;

// The store is the one part of lib/ that touches the file system, so it is
// the one part allowed dart:io — and only the store. It may import the model
// and engine barrels and core libraries; path_provider only in
// store_directory.dart, which hands every other caller a Directory.

import 'package:flutter_test/flutter_test.dart';

import 'engine_rules.dart';
import 'repo_files.dart';

const _libraries = {
  'dart:core',
  'dart:collection',
  'dart:async',
  'dart:convert',
  'dart:developer',
  'dart:io',
};

const _directoryFile = 'lib/store/store_directory.dart';

List<String> _offenders(String path, String source) => importOffenders(
  path,
  source,
  folder: 'store',
  libraries: _libraries,
  packages: [
    'package:meta/',
    'package:honest_sudoku/engine/engine.dart',
    'package:honest_sudoku/game/game.dart',
    if (path == _directoryFile) 'package:path_provider/',
  ],
);

void main() {
  test('the rule: path_provider only in store_directory.dart; no Flutter', () {
    const pp = "import 'package:path_provider/path_provider.dart';";
    expect(_offenders(_directoryFile, pp), isEmpty);
    expect(_offenders('lib/store/app_store.dart', pp), hasLength(1));
    expect(
      _offenders(
        'lib/store/x.dart',
        "import 'package:flutter/widgets.dart';\nimport '../ui/app.dart';",
      ),
      hasLength(2),
    );
    expect(
      _offenders(
        'lib/store/x.dart',
        "import 'dart:io';\nimport 'codecs.dart';",
      ),
      isEmpty,
    );
  });

  test('lib/store/ imports nothing outside the allowlist', () {
    final files = filesUnder('lib/store').where((p) => p.endsWith('.dart'));
    expect(
      files,
      contains('lib/store/app_store.dart'),
      reason:
          'store-imports: lib/store/ has no app_store.dart, so the scan '
          'would pass by reading nothing',
    );
    final offenders = [for (final f in files) ..._offenders(f, readFile(f))];
    expect(
      offenders,
      isEmpty,
      reason: describeOffenders('store-imports', offenders),
    );
  });
}
