@Tags(['guard'])
library;

// Every screen change is the one fade (#50). A Material or Cupertino page
// route slides, ignores "Remove animations" and would bypass the fade; this
// holds lib/ to none. motion_test.dart asserts every route the app builds
// is the fade; this catches one built anywhere else.

import 'package:flutter_test/flutter_test.dart';

import 'repo_files.dart';

final _sliding = RegExp(
  r'\b(MaterialPageRoute|MaterialPage|CupertinoPageRoute|CupertinoPage)\b',
);

/// `path:line: name` for each sliding route in [source], comments ignored.
List<String> slidingRoutes(String path, String source) {
  final lines = stripDartComments(source).split('\n');
  return [
    for (var i = 0; i < lines.length; i++)
      for (final m in _sliding.allMatches(lines[i])) '$path:${i + 1}: ${m[1]}',
  ];
}

void main() {
  test(
    'the rule: page routes that slide are refused, comments are not code',
    () {
      expect(
        slidingRoutes(
          'a.dart',
          'final r = MaterialPageRoute<void>(builder: (_) => w);',
        ),
        ['a.dart:1: MaterialPageRoute'],
      );
      expect(slidingRoutes('a.dart', 'x;\nCupertinoPageRoute(y);'), [
        'a.dart:2: CupertinoPageRoute',
      ]);
      expect(
        slidingRoutes('a.dart', '// MaterialPageRoute is refused'),
        isEmpty,
      );
      expect(slidingRoutes('a.dart', 'FadeRouteTransition(page: p)'), isEmpty);
    },
  );

  test('motion-routes: no page route in lib/ slides', () {
    final offenders = [
      for (final path in filesUnder('lib'))
        if (path.endsWith('.dart')) ...slidingRoutes(path, readFile(path)),
    ];
    expect(
      offenders,
      isEmpty,
      reason:
          'motion-routes: ${offenders.length} sliding route(s); every '
          'screen change is FadeRouteTransition:\n  ${offenders.join('\n  ')}',
    );
  });
}
