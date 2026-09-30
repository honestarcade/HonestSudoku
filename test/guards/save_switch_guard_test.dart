@Tags(['guard'])
library;

// `HS_DISABLE_SAVE` exists so tools/e2e.sh --no-save can prove the device
// suite's persistence step reads the disk (#66). A switch that turns saving
// off must never reach a player, so it is read once, in the composition
// root, behind kDebugMode, with a default of false. A source test, because
// no test here can build a release binary and ask it.

import 'package:flutter_test/flutter_test.dart';
import 'package:honest_sudoku/ui/app.dart';

import 'repo_files.dart';

const _root = 'lib/ui/app.dart';

final _mention = RegExp('HS_DISABLE_SAVE');
final _gated = RegExp(
  r'const bool kSaveDisabled\s*=\s*kDebugMode\s*&&\s*'
  r"bool\.fromEnvironment\(\s*'HS_DISABLE_SAVE'",
);
final _read = RegExp(
  r"\b(?:bool|String|int)\.fromEnvironment\(\s*'HS_DISABLE_SAVE'([^)]*)\)",
);

List<String> _mentions() => [
  for (final path in filesUnder('lib'))
    if (path.endsWith('.dart'))
      for (final _ in _mention.allMatches(stripDartComments(readFile(path))))
        path,
];

void main() {
  test('save-switch: the define is read once, in the composition root', () {
    expect(
      _mentions(),
      [_root],
      reason:
          'save-switch: HS_DISABLE_SAVE is read at ${_mentions()}; the one '
          'read belongs in $_root, behind kDebugMode',
    );
  });

  test('save-switch: the read is gated on kDebugMode', () {
    expect(
      _gated.hasMatch(stripDartComments(readFile(_root))),
      isTrue,
      reason:
          'save-switch: kSaveDisabled in $_root is not '
          '`kDebugMode && bool.fromEnvironment(...)`, so a profile or release '
          'build could be told to stop saving',
    );
  });

  test('save-switch: the define defaults to false', () {
    final args = [
      for (final m in _read.allMatches(stripDartComments(readFile(_root))))
        m[1]!.trim(),
    ];
    expect(
      args.where((a) => a.isNotEmpty && !RegExp(r'^,\s*$').hasMatch(a)),
      isEmpty,
      reason:
          'save-switch: HS_DISABLE_SAVE is read with $args; it must take '
          "bool.fromEnvironment's default, false",
    );
    expect(
      kSaveDisabled,
      isFalse,
      reason: 'save-switch: kSaveDisabled is true in a build given no define',
    );
  });
}
