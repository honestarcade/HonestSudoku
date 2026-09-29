import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:honest_sudoku/links.dart';
import 'package:honest_sudoku/ui/link_opener.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.flutter.io/url_launcher');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  for (final (what, answer) in <(String, Object Function())>[
    ('says no', () => false),
    ('throws', () => throw PlatformException(code: 'ACTIVITY_NOT_FOUND')),
  ]) {
    test('when the launcher $what, the opener logs it and does nothing '
        'else', () async {
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return answer();
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      final lines = <String>[];
      await UrlLauncherLinkOpener(log: lines.add)
          .open(AppLinks.source, LinkMode.external);
      expect(
        [for (final c in calls) (c.method, (c.arguments as Map)['url'])],
        [('launch', sourceUrl)],
        reason: 'a failed open is asked of the launcher once, and not retried',
      );
      expect(lines, [
        startsWith('could not open $sourceUrl'),
      ], reason: 'a failed open is logged once');
    });
  }

  test('a link opens outside the app', () async {
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return true;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    final lines = <String>[];
    await UrlLauncherLinkOpener(log: lines.add)
        .open(AppLinks.site, LinkMode.external);
    final args = calls.single.arguments as Map;
    expect(
      [args['url'], args['useWebView'], args['useSafariVC']],
      [siteUrl, false, false],
    );
    expect(lines, isEmpty);
  });
}
