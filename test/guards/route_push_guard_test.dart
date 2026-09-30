@Tags(['guard'])
library;

// The board is pushed once and returned to, and going to the menu clears the
// stack; lib/ui/routes.dart's helpers are what make both true (#46). A screen
// that pushes /board or /menu itself goes round them, and one that spells a
// route name by hand can do it where no search for `Routes.` will look.

import 'package:flutter_test/flutter_test.dart';

import 'repo_files.dart';

/// The one file allowed to name and push /board and /menu.
const routesFile = 'lib/ui/routes.dart';

final _push = RegExp(
  r'\b(?:push|popAndPush|restorablePush)\w*\s*(?:<[^>]*>)?\s*\(',
);
final _guarded = RegExp(
  r'''\bRoutes\.(?:board|menu)\b|(['"])/(?:board|menu)\1''',
);
final _spelled = RegExp(r'''(['"])/(?:board|menu)\1''');

int _line(String source, int offset) =>
    '\n'.allMatches(source.substring(0, offset)).length + 1;

/// The argument text of the call whose `(` is at [open], to its matching `)`.
String _arguments(String source, int open) {
  var depth = 0;
  for (var i = open; i < source.length; i++) {
    if (source[i] == '(') depth++;
    if (source[i] == ')' && --depth == 0) return source.substring(open, i + 1);
  }
  return source.substring(open);
}

/// `path:line: what` for each push in [source] whose arguments name /board or
/// /menu, whether as `Routes.board` or as a string.
List<String> guardedPushes(String path, String source) {
  final code = stripDartComments(source);
  return [
    for (final m in _push.allMatches(code))
      for (final name in _guarded.allMatches(_arguments(code, m.end - 1)))
        '$path:${_line(code, m.start)}: pushes ${name[0]}',
  ];
}

/// `path:line: what` for each `'/board'` or `'/menu'` string in [source].
List<String> spelledRouteNames(String path, String source) {
  final code = stripDartComments(source);
  return [
    for (final m in _spelled.allMatches(code))
      '$path:${_line(code, m.start)}: spells ${m[0]}',
  ];
}

List<String> _libFiles() => [
  for (final path in filesUnder('lib'))
    if (path.endsWith('.dart') && path != routesFile) path,
];

void main() {
  test('the rule: pushes naming /board or /menu are refused however they are '
      'written; the helpers and other routes are not', () {
    const bad = '''
Navigator.of(context).pushNamed('/board');
Navigator.pushNamed(context, Routes.menu);
nav.pushNamedAndRemoveUntil(
  Routes.board,
  (route) => false,
);
nav.pushReplacementNamed<void, void>("/menu");
''';
    expect(guardedPushes('a.dart', bad), [
      "a.dart:1: pushes '/board'",
      'a.dart:2: pushes Routes.menu',
      'a.dart:3: pushes Routes.board',
      'a.dart:7: pushes "/menu"',
    ]);
    const good = '''
Routes.toMenu(context);
Routes.toBoardPaused(context);
nav.pushNamed(Routes.settings);
// nav.pushNamed('/board');
final route = switch (name) { Routes.board => board, _ => other };
''';
    expect(guardedPushes('a.dart', good), isEmpty);
  });

  test('the rule: /board and /menu spelled as strings are refused', () {
    expect(spelledRouteNames('a.dart', "const r = '/board';\nf(\"/menu\");"), [
      "a.dart:1: spells '/board'",
      'a.dart:2: spells "/menu"',
    ]);
    expect(
      spelledRouteNames('a.dart', "// '/board'\nconst k = '/board-frame';"),
      isEmpty,
    );
  });

  test('route-push: nothing outside routes.dart pushes /board or /menu', () {
    final offenders = [
      for (final path in _libFiles()) ...guardedPushes(path, readFile(path)),
    ];
    expect(
      offenders,
      isEmpty,
      reason:
          'route-push: ${offenders.length} direct push(es); go through '
          'Routes.toBoardAfterGeneration, toBoardPaused or toMenu:\n  '
          '${offenders.join('\n  ')}',
    );
  });

  test('route-names: nothing outside routes.dart spells /board or /menu', () {
    final offenders = [
      for (final path in _libFiles())
        ...spelledRouteNames(path, readFile(path)),
    ];
    expect(
      offenders,
      isEmpty,
      reason:
          'route-names: ${offenders.length} route name(s) spelled by hand; '
          'use Routes.board and Routes.menu:\n  ${offenders.join('\n  ')}',
    );
    expect(
      spelledRouteNames(routesFile, readFile(routesFile)),
      hasLength(2),
      reason: 'route-names: routes.dart no longer declares /board and /menu',
    );
  });
}
