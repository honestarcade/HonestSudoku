// What the non-board screens say to a screen reader (#56).

import 'dart:ui';

import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:honest_sudoku/ui/routes.dart';

import '../helpers.dart';

/// Every node under the root, with its data.
List<SemanticsData> _nodes(WidgetTester tester) {
  final out = <SemanticsData>[];
  void visit(SemanticsNode n) {
    out.add(n.getSemanticsData());
    n.visitChildren((c) {
      visit(c);
      return true;
    });
  }

  visit(
    tester.binding.renderViews.first.owner!.semanticsOwner!.rootSemanticsNode!,
  );
  return out;
}

/// The labels of the selected nodes whose label matches one of [among].
List<String> _selected(WidgetTester tester, Set<String> among) => [
  for (final d in _nodes(tester))
    if (d.flagsCollection.isSelected == Tristate.isTrue &&
        among.any(d.label.startsWith))
      d.label,
];

void main() {
  late SemanticsHandle handle;
  setUp(() => handle = SemanticsBinding.instance.ensureSemantics());
  tearDown(() => handle.dispose());

  testWidgets('setup: one selected option per group, headings, Back', (
    tester,
  ) async {
    await pumpApp(tester, initialRoute: Routes.setup, height: 3000);
    expect(_selected(tester, {'4 by 4', '6 by 6', '9 by 9', '16 by 16'}), [
      '9 by 9, Classic',
    ]);
    expect(
      _selected(tester, {'Easy.', 'Medium.', 'Hard.', 'Expert.', 'Evil.'}),
      hasLength(1),
    );
    expect(_selected(tester, {'Zen', '3', '5', 'No limit'}), ['3']);
    expect(_selected(tester, {'Immediately', 'At the end'}), ['Immediately']);
    final back = _nodes(tester).where((d) => d.label == 'Back').single;
    expect(back.flagsCollection.isButton, isTrue);
    final headers = [
      for (final d in _nodes(tester))
        if (d.flagsCollection.isHeader) d.label,
    ];
    expect(
      headers,
      containsAll([
        'New puzzle',
        'Grid size',
        'Difficulty',
        'Mistakes allowed',
      ]),
    );
  });

  testWidgets('stats: the chosen tab is the one selected; cards are one node '
      'each, saying none yet', (tester) async {
    await pumpApp(tester, initialRoute: Routes.stats, height: 3000);
    expect(_selected(tester, {'Easy', 'Medium', 'Hard', 'Expert', 'Evil'}), [
      'Medium',
    ]);
    expect(
      _nodes(tester).map((d) => d.label),
      contains('Solved, none yet, none started'),
    );
  });

  testWidgets('settings: the theme card reads its name, selected, and none of '
      'its preview digits', (tester) async {
    await pumpApp(tester, initialRoute: Routes.settings, height: 3000);
    expect(_selected(tester, {'Navy felt', 'Paper'}), ['Navy felt']);
    expect(
      _nodes(tester).map((d) => d.label).where((l) => l.contains('\n5\n')),
      isEmpty,
    );
  });

  testWidgets('menu: the glyph grid exposes nothing; the card reads its title '
      'and line', (tester) async {
    await pumpApp(tester);
    final labels = _nodes(tester).map((d) => d.label).toList();
    expect(
      labels,
      contains(
        'New puzzle, 4 by 4, 6 by 6, 9 by 9 or 16 by 16, Easy through Evil',
      ),
    );
    expect(labels.where((l) => RegExp(r'^\d(\n|$)').hasMatch(l)), isEmpty);
    expect(
      _nodes(tester)
          .where((d) => d.label == 'Honest Sudoku')
          .single
          .flagsCollection
          .isHeader,
      isTrue,
    );
  });

  testWidgets('about: link rows say they open in the browser', (tester) async {
    await pumpApp(tester, initialRoute: Routes.aboutApp, height: 3000);
    final links = [
      for (final d in _nodes(tester))
        if (d.flagsCollection.isLink) d.label,
    ];
    expect(links, isNotEmpty);
    expect(links, everyElement(endsWith(', opens in browser')));
  });
}
