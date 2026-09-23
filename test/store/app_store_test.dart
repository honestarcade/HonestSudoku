import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:honest_sudoku/game/game.dart';
import 'package:honest_sudoku/store/app_store.dart';
import 'package:honest_sudoku/store/codecs.dart';

import '../game/fixtures.dart';

void main() {
  late Directory dir;
  late List<String> logs;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('hs-store-');
    logs = [];
  });
  tearDown(() => dir.deleteSync(recursive: true));

  AppStore store() => AppStore(
    dir,
    clock: () => DateTime.fromMillisecondsSinceEpoch(1234),
    log: logs.add,
  );

  File file(String name) => File('${dir.path}/$name');

  test('a missing document reads absent', () async {
    expect(await store().readSettings(), isA<Absent<AppSettings>>());
    expect(await store().readGame(), isA<Absent<SavedGame>>());
    expect(await store().readStats(), isA<Absent<StatsBook>>());
  });

  test('a write then a read returns the value, for every document', () async {
    final s = store();
    const settings = AppSettings(themeKey: 'paper', sfx: false);
    await s.writeSettings(settings);
    expect((await s.readSettings()).valueOrNull, settings);

    final game = SavedGame.fromState(
      GameState.start(classic).select(1).place(3).undo().tick(),
    );
    await s.writeGame(game);
    expect((await s.readGame()).valueOrNull, game);

    await s.writeStats(sampleStatsBook);
    expect((await s.readStats()).valueOrNull, sampleStatsBook);

    final envelope = jsonDecode(
      file('stats.json').readAsStringSync(),
    ) as Map<String, Object?>;
    expect(envelope['v'], 1);
    expect(envelope['data'], isA<Map<String, Object?>>());
  });

  test('deleteGame forgets the game', () async {
    final s = store();
    await s.writeGame(SavedGame.fromState(GameState.start(classic)));
    await s.deleteGame();
    expect(await s.readGame(), isA<Absent<SavedGame>>());
  });

  test('a truncated file reads corrupt and is set aside, not lost', () async {
    file('settings.json').writeAsStringSync('{"v": 1, "data": {"game": ');
    final r = await store().readSettings();
    expect(r, isA<Corrupt<AppSettings>>());
    expect(file('settings.json').existsSync(), isFalse);
    expect(file('settings.json.corrupt-1234').existsSync(), isTrue);
    expect(logs.single, contains('unreadable'));
  });

  test('a damaged document does not take the others down', () async {
    final s = store();
    await s.writeStats(sampleStatsBook);
    file('game.json').writeAsStringSync('not json');
    expect(await s.readGame(), isA<Corrupt<SavedGame>>());
    expect((await s.readStats()).valueOrNull, sampleStatsBook);
  });

  test('an unknown enum or a wrong length is corrupt', () async {
    file('settings.json')
        .writeAsStringSync('{"v": 1, "data": {"themeKey": "neon"}}');
    expect(await store().readSettings(), isA<Corrupt<AppSettings>>());
    final good = jsonDecode(
      jsonEncode({
        'v': 1,
        'data': jsonDecode(
          jsonEncode(
            _encodedGame(SavedGame.fromState(GameState.start(classic))),
          ),
        ),
      }),
    ) as Map<String, Object?>;
    (good['data']! as Map<String, Object?>)['values'] = [1, 2, 3];
    file('game.json').writeAsStringSync(jsonEncode(good));
    expect(await store().readGame(), isA<Corrupt<SavedGame>>());
  });

  test(
    'a v2 file is newer: left untouched, and a later write is refused',
    () async {
      const text = '{"v": 2, "data": {}}';
      file('settings.json').writeAsStringSync(text);
      final s = store();
      expect(await s.readSettings(), isA<Newer<AppSettings>>());
      expect(file('settings.json').readAsStringSync(), text);
      await expectLater(
        s.writeSettings(const AppSettings()),
        throwsA(isA<StoreNewerVersion>()),
      );
      expect(file('settings.json').readAsStringSync(), text);
    },
  );

  test('a write interrupted before its rename leaves the old file', () async {
    final s = store();
    await s.writeSettings(const AppSettings(themeKey: 'paper'));
    // What a kill between the two steps leaves behind.
    file('settings.json.tmp').writeAsStringSync('{"v": 1, "data": {"themeK');
    expect(
      (await s.readSettings()).valueOrNull,
      const AppSettings(themeKey: 'paper'),
    );
    await AppStore.open(dir);
    expect(
      file('settings.json.tmp').existsSync(),
      isFalse,
      reason: 'open() sweeps leftover tmp files',
    );
  });

  test('an older file is migrated and rewritten', () async {
    file('settings.json')
        .writeAsStringSync('{"v": 1, "data": {"theme": "paper"}}');
    final s = AppStore(
      dir,
      versions: const {
        StoreDocument.settings: 2,
        StoreDocument.game: 1,
        StoreDocument.stats: 1,
      },
      migrations: {
        'settings.json': {
          1: (data) => {'themeKey': data['theme']},
        },
      },
    );
    expect((await s.readSettings()).valueOrNull!.themeKey, 'paper');
    final rewritten = jsonDecode(
      file('settings.json').readAsStringSync(),
    ) as Map<String, Object?>;
    expect(rewritten['v'], 2);
  });

  test('a file over 256 KB is corrupt', () async {
    file(
      'stats.json',
    ).writeAsStringSync('{"v": 1, "data": {"pad": "${'x' * (257 * 1024)}"}}');
    expect(await store().readStats(), isA<Corrupt<StatsBook>>());
  });

  test('a missing root reads absent and a write creates it', () async {
    final nested = Directory('${dir.path}/a/b');
    final s = AppStore(nested);
    expect(await s.readStats(), isA<Absent<StatsBook>>());
    await s.writeStats(sampleStatsBook);
    expect((await s.readStats()).valueOrNull, sampleStatsBook);
  });
}

Map<String, Object?> _encodedGame(SavedGame g) => encodeGame(g);
