import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:honest_sudoku/ui/a11y/labels.dart';

import 'honest_tap_target_guideline.dart';

Future<void> _pump(WidgetTester tester, Widget child) async {
  tester.view.physicalSize = const Size(400, 400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: Center(child: child),
    ),
  );
}

Widget _button(double side, {String? label, SemanticsTag? tag}) {
  Widget b = Semantics(
    container: true,
    label: label,
    onTap: () {},
    child: SizedBox.square(dimension: side),
  );
  if (tag != null) {
    b = Semantics(
      container: true,
      explicitChildNodes: true,
      tagForChildren: tag,
      child: b,
    );
  }
  return b;
}

void main() {
  testWidgets('a 40-dp button fails; a 48-dp one passes', (tester) async {
    final handle = tester.ensureSemantics();
    await _pump(tester, _button(40, label: 'Go'));
    expect((await honestTapTargetGuideline.evaluate(tester)).passed, isFalse);
    await _pump(tester, _button(48, label: 'Go'));
    expect((await honestTapTargetGuideline.evaluate(tester)).passed, isTrue);
    handle.dispose();
  });

  testWidgets('an unlabelled tappable fails the labelled guideline', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await _pump(tester, _button(48));
    expect((await labeledTapTargetGuideline.evaluate(tester)).passed, isFalse);
    handle.dispose();
  });

  testWidgets('a tagged 22-dp grid cell passes the project guideline only', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await _pump(
      tester,
      _button(22, label: 'Row 1, column 1, empty', tag: kGridCellTag),
    );
    expect((await honestTapTargetGuideline.evaluate(tester)).passed, isTrue);
    expect(
      (await androidTapTargetGuideline.evaluate(tester)).passed,
      isFalse,
      reason: 'the exemption is the project\'s, not Android\'s',
    );
    await _pump(
      tester,
      _button(22, label: 'x', tag: const SemanticsTag('something-else')),
    );
    expect(
      (await honestTapTargetGuideline.evaluate(tester)).passed,
      isFalse,
      reason: 'only the grid-cell tag is exempt',
    );
    handle.dispose();
  });
}
