import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:honest_sudoku/feedback/haptics.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(
    () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
  );

  test(
    'light and medium are the platform\'s light and medium impacts',
    () async {
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        calls.add(call);
        return null;
      });
      final h = FlutterHaptics(log: (_) {});
      await h.light();
      await h.medium();
      expect(calls.map((c) => (c.method, c.arguments)), [
        ('HapticFeedback.vibrate', 'HapticFeedbackType.lightImpact'),
        ('HapticFeedback.vibrate', 'HapticFeedbackType.mediumImpact'),
      ]);
    },
  );

  test('a platform that refuses is logged once and never throws', () async {
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      throw PlatformException(code: 'no-vibrator');
    });
    final logged = <String>[];
    final h = FlutterHaptics(log: logged.add);
    await h.light();
    await h.medium();
    expect(logged, hasLength(1));
  });
}
