// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:honest_sudoku/main.dart';

void main() {
  testWidgets('Counter increments smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const MyApp());

    // Verify that our counter starts at 0.
    expect(find.text('0'), findsOneWidget);
    expect(find.text('1'), findsNothing);

    // Tap the '+' icon and trigger a frame.
    await tester.tap(find.byIcon(Icons.add));
    await tester.pump();

    // Verify that our counter has incremented.
    expect(find.text('0'), findsNothing);
    expect(find.text('1'), findsOneWidget);
  });

  // CI SMOKE TEST — deliberately failing, and deliberately NOT a compile
  // error, so the Invariant guards step passes and the Quality gate step is
  // the one that goes red. The first attempt at this demonstration used a
  // type error, which killed the guards step and left Quality gate skipped,
  // proving something narrower than the criterion claims (#137).
  //
  // This file is the only one carrying no `guard` tag, so
  // `flutter test --tags guard` does not see this at all.
  testWidgets('CI SMOKE: fails at runtime, removed next commit', (
    WidgetTester tester,
  ) async {
    expect(
      2 + 2,
      5,
      reason: 'deliberate: a gate.sh failure must block a merge',
    );
  });
}
