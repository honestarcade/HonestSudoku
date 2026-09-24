import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:honest_sudoku/ui/widgets/toggle.dart';

Future<void> _pumpToggle(WidgetTester tester, bool value, bool reduced) =>
    tester.pumpWidget(
      MediaQuery(
        data: MediaQueryData(disableAnimations: reduced),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: Toggle(value: value, onChanged: (_) {}),
          ),
        ),
      ),
    );

double _knob(WidgetTester tester) =>
    tester.getTopLeft(find.byType(Container).last).dx -
    tester.getTopLeft(find.byType(Toggle)).dx;

void main() {
  testWidgets('the knob slides with animations on', (tester) async {
    await _pumpToggle(tester, false, false);
    expect(_knob(tester), 3);
    await _pumpToggle(tester, true, false);
    await tester.pump(const Duration(milliseconds: 40));
    expect(_knob(tester), inExclusiveRange(3, 23));
    await tester.pumpAndSettle();
    expect(_knob(tester), 23);
  });

  testWidgets('the knob lands in one frame with animations removed', (
    tester,
  ) async {
    await _pumpToggle(tester, false, true);
    await _pumpToggle(tester, true, true);
    expect(_knob(tester), 23);
    expect(tester.hasRunningAnimations, isFalse);
  });
}
