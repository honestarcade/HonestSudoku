// Drives test_driver/store_app.dart through the eight Play screenshots (#57)
// and writes them to build/store-screenshots/. A plain program, not a test
// suite: the host runs it under `flutter drive`, and any failure exits
// non-zero.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_driver/flutter_driver.dart';

Future<void> main() async {
  final driver = await FlutterDriver.connect();
  const wait = Duration(seconds: 60);
  final out = Directory('build/store-screenshots')..createSync(recursive: true);

  Future<void> tap(String key) async {
    final f = find.byValueKey(key);
    await driver.scrollIntoView(f, timeout: wait);
    await driver.tap(f, timeout: wait);
    await driver.waitUntilNoTransientCallbacks(timeout: wait);
  }

  Future<void> shot(String name) async {
    await driver.waitUntilNoTransientCallbacks(timeout: wait);
    await Future<void>.delayed(const Duration(milliseconds: 600));
    File('${out.path}/$name.png').writeAsBytesSync(await driver.screenshot());
    stdout.writeln('  took $name');
  }

  Future<Map<String, Object?>> state() async =>
      jsonDecode(await driver.requestData('state')) as Map<String, Object?>;

  /// The screen's ‹, by its header's key prefix.
  Future<void> back(String screen) => tap('$screen-back');

  void expect(bool ok, String what) {
    if (!ok) throw StateError('store capture: $what');
  }

  try {
    // The splash hands over to the menu.
    await driver.waitFor(find.byValueKey('menu-new-card'), timeout: wait);

    // 02: setup, as a first-time player sees it.
    await tap('menu-new-card');
    await shot('02-setup');

    // 03: a 9×9 Medium game, three entries in, a hint showing.
    await tap('setup-start');
    await driver.waitFor(find.byValueKey('board-frame'), timeout: wait);
    final s = await state();
    final values = (s['values']! as List).cast<int>();
    final solution = (s['solution']! as List).cast<int>();
    for (final row in [0, 4, 8]) {
      final i = List.generate(
        9,
        (c) => row * 9 + c,
      ).firstWhere((j) => values[j] == 0);
      await tap('cell-$i');
      await tap('pad-${solution[i]}');
    }
    await tap('tool-hint');
    expect((await state())['notice'] == true, 'no hint notice on 9×9');
    await shot('03-board-9x9');

    // 07: settings, Navy felt selected; then Paper.
    await tap('pause-button');
    await tap('btn-settings');
    await shot('07-settings');
    await tap('settings-theme-paper');
    await back('settings');

    // 05: the same game on Paper, a hint showing.
    await tap('btn-resume');
    if ((await state())['notice'] != true) await tap('tool-hint');
    expect((await state())['notice'] == true, 'no hint notice on Paper');
    await shot('05-paper-hint');

    // Back to Navy felt, from the menu's settings.
    await tap('pause-button');
    await tap('btn-main-menu');
    await tap('menu-settings');
    await tap('settings-theme-navy');
    await back('settings');

    // 04: a pristine 16×16 Hard board.
    await tap('menu-new-card');
    await tap('setup-size-16×16');
    await tap('setup-diff-hard');
    await tap('setup-start');
    await driver.waitFor(find.byValueKey('board-frame'), timeout: wait);
    expect((await state())['shape'] == '16×16', 'the board is not 16×16');
    await shot('04-board-16x16');

    // 06: statistics, 08: how to play, 01: the menu with Continue.
    await tap('pause-button');
    await tap('btn-main-menu');
    await tap('menu-stats');
    await shot('06-stats');
    await back('stats');
    await tap('menu-howto');
    await shot('08-howto');
    await back('howto');
    await driver.waitFor(find.byValueKey('menu-continue'), timeout: wait);
    await shot('01-menu');
  } finally {
    await driver.close();
  }
}
