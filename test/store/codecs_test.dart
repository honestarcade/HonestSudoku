import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:honest_sudoku/game/game.dart';
import 'package:honest_sudoku/store/codecs.dart';

import '../game/fixtures.dart';

T roundTrip<T>(
  T value,
  Map<String, Object?> Function(T) encode,
  T Function(Map<String, Object?>) decode,
) => decode(jsonDecode(jsonEncode(encode(value))) as Map<String, Object?>);

void main() {
  test('the defaults are the design defaults for every toggle', () {
    const s = AppSettings();
    for (final t in SettingToggle.values) {
      expect(
        t.read(s.game),
        !(t == SettingToggle.autoNotes || t == SettingToggle.bigDigits),
        reason: t.key,
      );
    }
    expect([s.sfx, s.haptics, s.themeKey], [true, true, 'navy']);
    expect(s.lastSetup, const LastSetup());
    expect(s.lastSetup.shape.label, '9×9');
  });

  test('the toggle table matches the design keys and labels', () {
    expect(SettingToggle.values.map((t) => t.key), [
      'autoNotes',
      'autoClear',
      'conflicts',
      'hintWhy',
      'hlSame',
      'hlUnit',
      'dimDone',
      'showTimer',
      'bigDigits',
    ]);
    expect(SettingToggle.showTimer.description, 'Elapsed time in the top bar.');
    expect(SoundToggle.values.map((t) => t.key), ['sfx', 'haptics']);
    for (final t in SettingToggle.values) {
      expect(t.read(t.write(const GameSettings(), true)), isTrue);
      expect(t.read(t.write(const GameSettings(), false)), isFalse);
    }
  });

  test('settings round-trip with every field changed', () {
    const s = AppSettings(
      game: GameSettings(
        autoNotes: true,
        autoClear: false,
        conflicts: false,
        hintWhy: false,
        hlSame: false,
        hlUnit: false,
        dimDone: false,
        showTimer: false,
        bigDigits: true,
        strikeMode: StrikeMode.five,
        announce: AnnounceMode.atEnd,
      ),
      themeKey: 'paper',
      sfx: false,
      haptics: false,
      lastSetup: LastSetup(
        shapeLabel: '6×6',
        difficultyKey: 'hard',
        strikeMode: StrikeMode.zen,
        announce: AnnounceMode.atEnd,
      ),
    );
    expect(roundTrip(s, encodeSettings, decodeSettings), s);
  });

  test('an unsupported last setup resets only the last setup', () {
    final json = encodeSettings(const AppSettings(themeKey: 'paper'));
    (json['lastSetup']! as Map<String, Object?>)['difficulty'] = 'evil';
    (json['lastSetup']! as Map<String, Object?>)['shape'] = '4×4';
    final s = decodeSettings(json);
    expect(s.lastSetup, const LastSetup());
    expect(s.themeKey, 'paper');
  });

  test('a saved game round-trips with history, future, notes and flags', () {
    final state =
        GameState.start(
              classic,
              const GameSettings(
                strikeMode: StrikeMode.five,
                announce: AnnounceMode.atEnd,
              ),
            )
            .select(1)
            .place(classic.solution[1])
            .select(3)
            .place(wrongValue(classic, 3))
            .select(5)
            .toggleNoteMode()
            .place(2)
            .toggleNoteMode()
            .undo()
            .check()
            .tick()
            .tick();
    final g = SavedGame.fromState(state);
    expect(roundTrip(g, encodeGame, decodeGame), g);
    final restored = g.toState(const GameSettings(hlSame: false));
    expect(restored.values, state.values);
    expect(restored.history, state.history);
    expect(restored.future, state.future);
    expect(restored.settings.strikeMode, StrikeMode.five);
    expect(restored.settings.hlSame, isFalse, reason: 'current toggles');
    expect(restored.paused, isTrue, reason: 'Continue restores it paused');
    expect(restored.revealed, isTrue);
  });

  test('a saved game whose given differs from the solution is refused', () {
    final json = encodeGame(SavedGame.fromState(GameState.start(classic)));
    final values = [...json['values']! as List<int>];
    values[0] = values[0] % 9 + 1;
    json['values'] = values;
    expect(() => decodeGame(json), throwsFormatException);
  });

  test('history longer than 120 keeps the newest', () {
    final json = encodeGame(SavedGame.fromState(GameState.start(classic)));
    final snap = {
      'values': classic.startingValues(),
      'notes': List.filled(81, <int>[]),
      'mistakes': 0,
      'moves': 0,
    };
    json['history'] = [
      for (var k = 0; k < 130; k++) {...snap, 'moves': k},
    ];
    final g = decodeGame(jsonDecode(jsonEncode(json)) as Map<String, Object?>);
    expect(g.history, hasLength(120));
    expect(g.history.first.moves, 10);
  });

  test('statistics round-trip', () {
    expect(
      roundTrip(sampleStatsBook, encodeStats, decodeStats),
      sampleStatsBook,
    );
    expect(
      roundTrip(StatsBook.empty, encodeStats, decodeStats),
      StatsBook.empty,
    );
  });
}
