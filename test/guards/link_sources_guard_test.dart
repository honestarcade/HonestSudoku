@Tags(['guard'])
library;

// The screens that show links take them from lib/links.dart, parsed once in
// the opener's AppLinks, and hand them to the opener (#44). The dependency
// guard keeps URL text inside links.dart; this keeps the screens from
// reaching a browser, or a Uri, any other way.

import 'package:flutter_test/flutter_test.dart';

import 'engine_rules.dart';
import 'repo_files.dart';

/// The How to play and About screens.
const linkScreens = [
  'lib/ui/screens/howto_screen.dart',
  'lib/ui/screens/about_app_screen.dart',
  'lib/ui/screens/about_studio_screen.dart',
];

final _builtUri = RegExp(r'\bUri\s*(?:\.\s*\w+\s*)?\(');

/// `path: why` for each way [source] reaches a link other than through
/// links.dart: an import of url_launcher, or a Uri it builds itself.
List<String> linkSourceOffenders(String path, String source) {
  final lines = stripDartComments(source).split('\n');
  return [
    for (final uri in directiveUris(source))
      if (uri.contains('url_launcher')) '$path: imports $uri',
    for (var i = 0; i < lines.length; i++)
      if (_builtUri.hasMatch(lines[i])) '$path:${i + 1}: builds a Uri',
  ];
}

void main() {
  test('the rule: url_launcher and a Uri built in place are refused; the '
      "opener's links are not", () {
    expect(
      linkSourceOffenders(
        'a.dart',
        "import 'package:url_launcher/url_launcher.dart';\n"
            "final u = Uri.parse('x');\n"
            "final v = Uri(scheme: 'y');",
      ),
      [
        'a.dart: imports package:url_launcher/url_launcher.dart',
        'a.dart:2: builds a Uri',
        'a.dart:3: builds a Uri',
      ],
    );
    expect(
      linkSourceOffenders(
        'a.dart',
        "import '../link_opener.dart';\n"
            '// Uri.parse is refused here\n'
            'final Uri u = AppLinks.site;',
      ),
      isEmpty,
    );
  });

  test('link-sources: the How to play and About screens reach links only '
      'through links.dart', () {
    final offenders = [
      for (final path in linkScreens)
        ...linkSourceOffenders(path, readFile(path)),
    ];
    expect(
      offenders,
      isEmpty,
      reason:
          'link-sources: ${offenders.length} way(s) round links.dart; a '
          'screen opens AppLinks through the LinkOpener:\n  '
          '${offenders.join('\n  ')}',
    );
  });

  test('link-sources: the opener imports links.dart', () {
    final uris = directiveUris(readFile('lib/ui/link_opener.dart'));
    expect(
      uris.where(
        (u) => u == '../links.dart' || u == 'package:honest_sudoku/links.dart',
      ),
      hasLength(1),
      reason:
          'link-sources: link_opener.dart has no import of links.dart, so '
          'AppLinks is parsed from somewhere else (imports: $uris)',
    );
  });
}
