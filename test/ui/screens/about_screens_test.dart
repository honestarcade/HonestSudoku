import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:honest_sudoku/links.dart';
import 'package:honest_sudoku/ui/link_opener.dart';
import 'package:honest_sudoku/ui/routes.dart';
import 'package:honest_sudoku/ui/screens/about_studio_screen.dart';
import 'package:honest_sudoku/ui/screens/menu_screen.dart';

import '../copy_fixture.dart';
import '../helpers.dart';

Finder text(String s) => find.text(s, skipOffstage: false);

void main() {
  testWidgets('How to play: every rule and gesture, verbatim', (tester) async {
    await pumpApp(tester, initialRoute: Routes.howto);
    for (final (tag, body) in designRules) {
      expect(text(tag), findsOneWidget, reason: tag);
      expect(text(body), findsOneWidget, reason: tag);
    }
    for (final (k, v) in designGestures) {
      expect(text(k), findsOneWidget, reason: k);
      expect(text(v), findsOneWidget, reason: k);
    }
  });

  testWidgets('About the App: features, chips, version; links open the right '
      'places', (tester) async {
    final app = await pumpApp(tester, initialRoute: Routes.aboutApp);
    for (final (k, v) in designFeatures) {
      expect(text(k), findsOneWidget, reason: k);
      expect(text(v), findsOneWidget, reason: k);
    }
    for (final chip in [
      'NO ADS',
      'NO TRACKING',
      'NO ACCOUNTS',
      'NO PURCHASES',
      'NO PERMISSIONS',
      'OPEN SOURCE',
      'WORKS OFFLINE',
    ]) {
      expect(text(chip), findsOneWidget, reason: chip);
    }
    expect(text('v1.2.3 · OFFLINE'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const ValueKey('about-link-site')));
    await tester.tap(find.byKey(const ValueKey('about-link-site')));
    await tester.tap(find.byKey(const ValueKey('about-link-source')));
    expect(app.links.opened, [
      (Uri.parse(siteUrl), LinkMode.external),
      (Uri.parse(sourceUrl), LinkMode.external),
    ]);
  });

  testWidgets('About Honest Arcade: paragraphs, promises, chips; links; a '
      'non-link tap opens nothing', (tester) async {
    final app = await pumpApp(tester, initialRoute: Routes.aboutStudio);
    expect(
      text(
        'Honest Arcade makes simple games and useful apps with no ads, no '
        'tracking, and no hidden agenda. Everything we build is open source, '
        "so you can see exactly what you're getting.",
      ),
      findsOneWidget,
    );
    expect(
      text('Just good software that respects your time, privacy, and device.'),
      findsOneWidget,
    );
    for (final (k, v) in designPromises) {
      expect(text(k), findsOneWidget, reason: k);
      expect(text(v), findsOneWidget, reason: k);
    }
    for (final chip in ['NO ADS', 'NO TRACKING', 'OPEN SOURCE']) {
      expect(text(chip), findsOneWidget, reason: chip);
    }
    await tester.tap(text(designPromises.first.$1));
    expect(app.links.opened, isEmpty);
    await tester.tap(find.byKey(const ValueKey('studio-support')));
    await tester.ensureVisible(find.byKey(const ValueKey('studio-link-site')));
    await tester.tap(find.byKey(const ValueKey('studio-link-site')));
    await tester.tap(find.byKey(const ValueKey('studio-link-source')));
    expect(app.links.opened, [
      (Uri.parse(contributeUrl), LinkMode.external),
      (Uri.parse(siteUrl), LinkMode.external),
      (Uri.parse(sourceUrl), LinkMode.external),
    ]);
  });

  testWidgets('About the App → promises → ‹ lands on the menu, as the '
      'design goBack does', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.byKey(const ValueKey('menu-about-app')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('about-promises')));
    await tester.tap(find.byKey(const ValueKey('about-promises')));
    await tester.pumpAndSettle();
    expect(find.byType(AboutStudioScreen), findsOneWidget);
    await tester.ensureVisible(find.byKey(const ValueKey('studio-back')));
    await tester.tap(find.byKey(const ValueKey('studio-back')));
    await tester.pumpAndSettle();
    expect(find.byType(MenuScreen), findsOneWidget);
  });

  test('the About screens take their URLs from links.dart only', () {
    for (final path in [
      'lib/ui/screens/about_app_screen.dart',
      'lib/ui/screens/about_studio_screen.dart',
      'lib/ui/link_opener.dart',
    ]) {
      final source = File(path).readAsStringSync();
      expect(source, isNot(contains('https://')), reason: path);
    }
    expect(
      File('lib/ui/link_opener.dart').readAsStringSync(),
      contains("import '../links.dart';"),
    );
  });
}
