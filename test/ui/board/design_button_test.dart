import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:honest_sudoku/ui/widgets/design_button.dart';

import '../harness.dart';

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
    double opacity() => tester.widget<Opacity>(find.byType(Opacity)).opacity;
    expect(opacity(), 1);
    final gesture = await tester.startGesture(
      tester.getCenter(find.text('Press')),
    );
    await tester.pump();
    expect(opacity(), .85);
    await gesture.up();
    await tester.pump();
    expect(opacity(), 1);
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
