import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:honest_sudoku/ui/widgets/design_button.dart';

import '../harness.dart';

/// The press dip's current opacity.
double _opacity(WidgetTester tester) => tester
    .widget<FadeTransition>(
      find.descendant(
        of: find.byType(AnimatedOpacity),
        matching: find.byType(FadeTransition),
      ),
    )
    .opacity
    .value;

void main() {
  testWidgets('taps call back; a null callback ignores taps', (tester) async {
    var taps = 0;
    await pumpFramed(
      tester,
      DesignButton.variant(
        DesignButtonVariant.primary,
        onPressed: () => taps++,
        scale: 1,
        height: 48,
        child: const Text('Resume'),
      ),
    );
    await tester.tap(find.text('Resume'));
    expect(taps, 1);
    await pumpFramed(
      tester,
      DesignButton.variant(
        DesignButtonVariant.primary,
        onPressed: null,
        scale: 1,
        child: const Text('Inert'),
      ),
    );
    await tester.tap(find.text('Inert'));
    expect(taps, 1);
  });

  testWidgets('it dips while pressed and recovers', (tester) async {
    await pumpFramed(
      tester,
      DesignButton.variant(
        DesignButtonVariant.secondary,
        onPressed: () {},
        scale: 1,
        child: const Text('Press'),
      ),
    );
    expect(_opacity(tester), 1);
    final gesture = await tester.startGesture(
      tester.getCenter(find.text('Press')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));
    expect(
      _opacity(tester),
      inExclusiveRange(.85, 1),
      reason: 'the dip eases in over kPressDip',
    );
    await tester.pumpAndSettle();
    expect(_opacity(tester), closeTo(.85, 1e-9));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(_opacity(tester), 1);
  });

  testWidgets('with animations removed the dip still happens, at once', (
    tester,
  ) async {
    await pumpFramed(
      tester,
      MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: DesignButton.variant(
          DesignButtonVariant.secondary,
          onPressed: () {},
          scale: 1,
          child: const Text('Press'),
        ),
      ),
    );
    final gesture = await tester.startGesture(
      tester.getCenter(find.text('Press')),
    );
    await tester.pump();
    await tester.pump();
    expect(_opacity(tester), closeTo(.85, 1e-9));
    expect(tester.hasRunningAnimations, isFalse);
    await gesture.up();
    await tester.pump();
  });

  test('five variants', () {
    expect(DesignButtonVariant.values.map((v) => v.name), [
      'primary',
      'secondary',
      'soft',
      'ghost',
      'outline',
    ]);
  });
}
