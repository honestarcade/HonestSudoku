// Shared harness for UI tests: a MaterialApp at the design frame's size.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Pumps [child] inside a MaterialApp on a [width]×[height] logical screen
/// at device pixel ratio 1.
Future<void> pumpFramed(
  WidgetTester tester,
  Widget child, {
  double width = 390,
  double height = 844,
}) async {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: Align(alignment: Alignment.topLeft, child: child),
      ),
    ),
  );
}

/// The colour of the DecoratedBox keyed [key].
Color? boxColor(WidgetTester tester, String key) {
  final box = tester.widget<DecoratedBox>(find.byKey(ValueKey(key)));
  return (box.decoration as BoxDecoration).color;
}
