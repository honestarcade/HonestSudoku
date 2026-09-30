// Holds docs/test-plan.md to the app it tests (#60): a section for every
// route, a mode table in the app's own vocabulary, every human-only subject,
// the run log and the bug report. It reads headings, table cells and field
// labels, never prose; whether the prose is any good is the owner's pass
// (#64).
//
// Each rule returns offender strings, empty when the plan holds, so the
// complements at the bottom can feed it a broken copy.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:honest_sudoku/engine/engine.dart';
import 'package:honest_sudoku/game/game.dart';
import 'package:honest_sudoku/ui/theme/board_theme.dart';

const _planPath = 'docs/test-plan.md';

/// Each route name in lib/ui/routes.dart and its section heading, in the
/// order the plan walks them (the menu's). A renamed screen fails here
/// rather than drifting.
const routeHeadings = {
  '/loading': 'Loading',
  '/menu': 'Main menu',
  '/setup': 'New puzzle',
  '/board': 'Board',
  '/stats': 'Statistics',
  '/howto': 'How to play',
  '/settings': 'Settings',
  '/about-app': 'About the App',
  '/about-studio': 'About Honest Arcade',
};

/// The subjects only a person on a phone can check.
const humanOnly = [
  'Sound',
  'Haptics',
  'Launcher icon and cold-start splash',
  'TalkBack',
  'Largest system font',
  'Remove animations',
  'Greyscale',
];

/// The owner's amendments to the design that the plan checks as the app
/// behaves.
const amendments = [320, 321, 322, 323];

/// Stated instead of a citation where no test covers a section.
const noCounterpart = 'No automated counterpart.';

/// A heading and the lines under it, up to the next heading.
typedef Section = ({int level, String title, List<String> lines});

/// The plan's `##` and `###` sections, in order; headings inside fenced
/// blocks are not headings.
List<Section> sectionsOf(String plan) {
  final out = <Section>[];
  var fenced = false;
  for (final line in plan.split('\n')) {
    if (line.startsWith('```')) fenced = !fenced;
    final m = RegExp(r'^(#{2,3}) (.+?)\s*$').firstMatch(line);
    if (!fenced && m != null) {
      out.add((level: m.group(1)!.length, title: m.group(2)!, lines: []));
    } else if (out.isNotEmpty) {
      out.last.lines.add(line);
    }
  }
  return out;
}

Section? _section(String plan, String title) {
  for (final s in sectionsOf(plan)) {
    if (s.title == title) return s;
  }
  return null;
}

/// Every route string declared in routes.dart's source.
List<String> declaredRoutes(String routesSource) => [
  for (final m in RegExp(
    r"static const \w+ = '(/[^']*)';",
  ).allMatches(routesSource))
    m.group(1)!,
];

/// A route without a heading, a heading missing from the plan, a `##` that
/// is no screen, or screens out of menu order.
List<String> screenOffenders(String plan, String routesSource) {
  final offenders = <String>[];
  for (final route in declaredRoutes(routesSource)) {
    if (!routeHeadings.containsKey(route)) {
      offenders.add('$route: no heading in routeHeadings');
    }
  }
  final screens = [
    for (final s in sectionsOf(plan))
      if (s.level == 2) s.title,
  ];
  for (final heading in routeHeadings.values) {
    if (!screens.contains(heading)) offenders.add('no "## $heading" section');
  }
  for (final s in screens) {
    if (!routeHeadings.containsValue(s)) {
      offenders.add('"## $s" is not a screen; other sections are ###');
    }
  }
  final expected = [
    for (final h in routeHeadings.values)
      if (screens.contains(h)) h,
  ];
  if (offenders.isEmpty && screens.join('|') != expected.join('|')) {
    offenders.add('screens out of menu order: $screens');
  }
  return offenders;
}

/// The mode table's rows as column → cell.
List<Map<String, String>> modeRows(String plan) {
  final lines = _section(plan, 'Modes')?.lines ?? const <String>[];
  final table = [
    for (final l in lines)
      if (l.trimLeft().startsWith('|'))
        l
            .trim()
            .substring(1, l.trim().length - 1)
            .split('|')
            .map((c) => c.trim())
            .toList(),
  ];
  if (table.length < 2) return const [];
  final header = table.first;
  return [
    for (final row in table.skip(2))
      {
        for (var i = 0; i < header.length; i++)
          header[i]: row.elementAtOrNull(i) ?? '',
      },
  ];
}

/// Missing vocabulary in the mode table, and rows the app does not offer.
List<String> modeOffenders(String plan) {
  final rows = modeRows(plan);
  if (rows.isEmpty) return ['no mode table under "### Modes"'];
  final offenders = <String>[];
  const columns = [
    'Size',
    'Difficulty',
    'Strikes',
    'Announce',
    'Theme',
    'Note mode',
    'Auto candidates',
    'Done',
    'Build',
    'Device',
  ];
  for (final c in columns) {
    if (!rows.first.containsKey(c)) offenders.add('no "$c" column');
  }
  if (offenders.isNotEmpty) return offenders;
  void covers(String column, Iterable<String> wanted, {bool fold = false}) {
    final seen = {
      for (final r in rows) fold ? r[column]!.toLowerCase() : r[column]!,
    };
    for (final w in wanted) {
      if (!seen.contains(fold ? w.toLowerCase() : w)) {
        offenders.add('$column: no row with $w');
      }
    }
  }

  covers('Size', GridShape.all.map((s) => s.label));
  covers('Difficulty', Difficulty.values.map((d) => d.label));
  covers('Strikes', StrikeMode.values.map((m) => m.label));
  covers('Announce', AnnounceMode.values.map((m) => m.label));
  covers('Theme', BoardTheme.all.map((t) => t.key), fold: true);
  covers('Note mode', ['on', 'off']);
  covers('Auto candidates', ['on', 'off']);
  for (final r in rows) {
    final name = '${r['Size']} ${r['Difficulty']}';
    final shape = GridShape.all.where((s) => s.label == r['Size']).firstOrNull;
    final band = Difficulty.values
        .where((d) => d.label == r['Difficulty'])
        .firstOrNull;
    if (shape == null || band == null) {
      offenders.add('$name: not a size and difficulty the app knows');
    } else if (!supportedDifficulties(shape).contains(band)) {
      offenders.add('$name: a row, but the app does not offer it');
    }
    if (!RegExp(r'^- \[[ x]\]$').hasMatch(r['Done']!)) {
      offenders.add('$name: the Done cell is not a tick box');
    }
  }
  return offenders;
}

/// The pairs "### Not offered" lists, against the engine's own table.
List<String> notOfferedOffenders(String plan) {
  final section = _section(plan, 'Not offered');
  if (section == null) return ['no "### Not offered" section'];
  final listed = {
    for (final l in section.lines)
      if (l.startsWith('- ')) l.substring(2).trim(),
  };
  final unsupported = {
    for (final s in GridShape.all)
      for (final d in Difficulty.values)
        if (!supportedDifficulties(s).contains(d)) '${s.label} ${d.label}',
  };
  return [
    for (final p in unsupported.difference(listed))
      'Not offered: $p is missing, and the app greys it',
    for (final p in listed.difference(unsupported))
      'Not offered: $p is listed, and the app offers it',
  ];
}

const _cannotProve = '**What the suites cannot prove:**';
const _instead = '**Instead:**';

/// A human-only subject without its section or its two parts.
List<String> humanOnlyOffenders(String plan) => [
  for (final subject in humanOnly)
    ...switch (_section(plan, subject)) {
      null => ['no "### $subject" section'],
      final s => [
        if (!s.lines.any((l) => l.startsWith(_cannotProve)))
          '$subject: no "$_cannotProve" line',
        if (!s.lines.any((l) => l == _instead)) '$subject: no "$_instead" line',
        if (!s.lines.any((l) => l.startsWith('- [ ] ')))
          '$subject: no step to tick',
      ],
    },
];

/// A test's source with adjacent string literals joined and `\'` unescaped,
/// so a name split across lines reads as one.
String _joined(String source) => source
    .replaceAll(RegExp(r"'\s*\n\s*'"), '')
    .replaceAll(
      RegExp(
        r"'\s*\n\s*"
        '"',
      ),
      '',
    )
    .replaceAll(
      RegExp(
        '"'
        r"\s*\n\s*'",
      ),
      '',
    )
    .replaceAll(r"\'", "'");

/// A screen or human-only section that neither cites a test that exists
/// nor says it has none.
List<String> counterpartOffenders(
  String plan,
  String? Function(String path) read,
) {
  final offenders = <String>[];
  final cited = [...routeHeadings.values, 'Modes', ...humanOnly];
  for (final title in cited) {
    final s = _section(plan, title);
    if (s == null) continue;
    final cites = [
      for (final l in s.lines)
        if (l.startsWith('- Automated: ')) l,
    ];
    final none = s.lines.any((l) => l.trim() == noCounterpart);
    if (cites.isEmpty && !none) {
      offenders.add('$title: no "- Automated:" line and no "$noCounterpart"');
    }
    for (final c in cites) {
      final m = RegExp(r'^- Automated: `([^`]+)` — "(.+)"$').firstMatch(c);
      if (m == null) {
        offenders.add('$title: "$c" is not `path` — "test name"');
        continue;
      }
      final source = read(m.group(1)!);
      if (source == null) {
        offenders.add('$title: ${m.group(1)} does not exist');
      } else if (!_joined(source).contains(m.group(2)!)) {
        offenders.add('$title: ${m.group(1)} has no test "${m.group(2)}"');
      }
    }
  }
  return offenders;
}

/// Field labels a filled run-log block and a bug report must carry.
const runLogFields = [
  'Date:',
  'Build version:',
  'Build code:',
  'Device (model, Android version):',
  'Ran by:',
  'Sections completed:',
  'Issues filed:',
];

/// See [runLogFields].
const bugFields = [
  'Build version:',
  'Build code:',
  'Device (model, Android version):',
  'Steps:',
  'What happened:',
  'What was expected:',
  'Blocks play or misleads the player:',
];

/// The run log, its pass template and the bug report, with their fields.
List<String> recordOffenders(String plan) {
  final offenders = <String>[];
  if (_section(plan, 'Run log') == null) offenders.add('no "### Run log"');
  final passes = [
    for (final s in sectionsOf(plan))
      if (s.level == 3 && s.title.startsWith('Pass — ')) s,
  ];
  if (passes.isEmpty) offenders.add('no "### Pass — <date>" block');
  for (final p in passes) {
    for (final f in runLogFields) {
      if (!p.lines.any((l) => l.startsWith('- $f'))) {
        offenders.add('${p.title}: no "- $f" field');
      }
    }
  }
  final bug = _section(plan, 'Reporting a bug');
  if (bug == null) return [...offenders, 'no "### Reporting a bug"'];
  for (final f in bugFields) {
    if (!bug.lines.any((l) => l.startsWith(f))) {
      offenders.add('Reporting a bug: no "$f" field');
    }
  }
  return offenders;
}

/// Each amendment is checked by a step that cites a ledger heading which
/// exists and whose entry names the amendment.
List<String> amendmentOffenders(String plan, String ledger) {
  final entries = <String, String>{};
  String? heading;
  for (final line in ledger.split('\n')) {
    if (line.startsWith('## ')) {
      heading = line
          .substring(3)
          .replaceFirst(RegExp(r' — reconciled by .*$'), '')
          .trim();
      entries[heading] = entries[heading] ?? '';
    } else if (heading != null) {
      entries[heading] = '${entries[heading]}$line\n';
    }
  }
  final offenders = <String>[];
  for (final n in amendments) {
    final steps = [
      for (final l in plan.split('\n'))
        if (l.startsWith('- [ ] ') && l.contains('#$n')) l,
    ];
    if (steps.isEmpty) {
      offenders.add('#$n: no step checks it');
      continue;
    }
    for (final step in steps) {
      final m = RegExp(r'`\.n8/decisions\.md` "([^"]+)"').firstMatch(step);
      if (m == null) {
        offenders.add('#$n: a step cites no `.n8/decisions.md` "<heading>"');
      } else if (!entries.entries.any(
        (e) => e.key == m.group(1) && e.value.contains('#$n'),
      )) {
        offenders.add('#$n: no ledger entry "${m.group(1)}" names #$n');
      }
    }
  }
  return offenders;
}

String _read(String path) => File(path).readAsStringSync();

String? _readOrNull(String path) {
  final f = File(path);
  return f.existsSync() ? f.readAsStringSync() : null;
}

void main() {
  final plan = _read(_planPath);
  final routes = _read('lib/ui/routes.dart');

  test('every route in lib/ui/routes.dart has its section, in menu order', () {
    expect(
      declaredRoutes(routes),
      isNotEmpty,
      reason: 'routes.dart declares its routes as static const strings',
    );
    expect(screenOffenders(plan, routes), isEmpty);
  });

  test(
    'the mode table covers every size, difficulty, strike and announce '
    'mode, theme, note mode and auto candidates, on pairs the app offers',
    () {
      expect(modeOffenders(plan), isEmpty);
    },
  );

  test('Not offered lists exactly the pairs the engine does not support', () {
    expect(notOfferedOffenders(plan), isEmpty);
  });

  test('every human-only subject says what the suites cannot prove and '
      'what to do instead', () {
    expect(humanOnlyOffenders(plan), isEmpty);
  });

  test('every screen, the mode table and each human-only subject cites a '
      'test that exists, or says it has none', () {
    expect(counterpartOffenders(plan, _readOrNull), isEmpty);
  });

  test('the run log and the bug report carry their fields', () {
    expect(recordOffenders(plan), isEmpty);
  });

  test("the owner's amendments are checked, each citing its ledger entry", () {
    expect(amendmentOffenders(plan, _read('.n8/decisions.md')), isEmpty);
  });

  test('the Pages site does not publish the plan', () {
    expect(
      RegExp(
        r'^exclude:\s*\n(\s+- .*\n)*\s+- test-plan\.md\s*$',
        multiLine: true,
      ).hasMatch(_read('docs/_config.yml')),
      isTrue,
      reason: 'docs/_config.yml excludes test-plan.md from the site',
    );
  });

  test('the device-testing memory links to the run log', () {
    final memory = _read('.n8/memory/device-testing.md');
    expect(
      memory,
      contains('(../../docs/test-plan.md)'),
      reason: '.n8/memory/device-testing.md links to docs/test-plan.md',
    );
    expect(
      memory,
      isNot(contains('- Ran by:')),
      reason: 'the memory file links to the run log and does not copy it',
    );
  });

  group('complements', () {
    String without(String text, String heading) {
      final lines = text.split('\n');
      final start = lines.indexOf(heading);
      var end = start + 1;
      while (end < lines.length && !lines[end].startsWith('#')) {
        end++;
      }
      return [...lines.take(start), ...lines.skip(end)].join('\n');
    }

    test('a copy with the Statistics section removed fails, naming it', () {
      final dir = Directory.systemTemp.createTempSync('test_plan_');
      addTearDown(() => dir.deleteSync(recursive: true));
      final copy = File('${dir.path}/test-plan.md')
        ..writeAsStringSync(without(plan, '## Statistics'));
      expect(screenOffenders(copy.readAsStringSync(), routes), [
        'no "## Statistics" section',
      ]);
    });

    test('a route routes.dart gains without a heading fails, naming it', () {
      final more = routes.replaceFirst(
        "static const menu = '/menu';",
        "static const menu = '/menu';\n  static const help = '/help';",
      );
      expect(screenOffenders(plan, more), [
        '/help: no heading in routeHeadings',
      ]);
    });

    test('a table with no Paper row fails, naming it', () {
      final navyOnly = plan.replaceAll('| Paper |', '| Navy |');
      expect(modeOffenders(navyOnly), ['Theme: no row with paper']);
    });

    test('a row the app does not offer fails, naming it', () {
      final bad = plan.replaceFirst('| 4×4 | Easy |', '| 4×4 | Evil |');
      expect(modeOffenders(bad), [
        '4×4 Evil: a row, but the app does not offer it',
      ]);
    });

    test('a Not offered list missing a pair fails, naming it', () {
      final short = plan.replaceFirst('- 6×6 Evil\n', '');
      expect(notOfferedOffenders(short), [
        'Not offered: 6×6 Evil is missing, and the app greys it',
      ]);
    });

    test('a citation of a test that does not exist fails, naming it', () {
      final bad = plan.replaceFirst(
        '"Reset then Cancel keeps the numbers; Reset then Reset wipes them"',
        '"Reset wipes nothing"',
      );
      expect(counterpartOffenders(bad, _readOrNull), [
        'Statistics: test/ui/screens/stats_screen_test.dart has no test '
            '"Reset wipes nothing"',
      ]);
    });

    test(
      'an amendment cited to a ledger entry that does not name it fails',
      () {
        final bad = plan.replaceAll(
          '#323, `.n8/decisions.md` "Ad-hoc — 2026-09-29"',
          '#323, `.n8/decisions.md` "/n8-init — 2026-09-18"',
        );
        expect(amendmentOffenders(bad, _read('.n8/decisions.md')), [
          '#323: no ledger entry "/n8-init — 2026-09-18" names #323',
          '#323: no ledger entry "/n8-init — 2026-09-18" names #323',
        ]);
      },
    );
  });
}
