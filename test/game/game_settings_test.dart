import 'package:flutter_test/flutter_test.dart';
import 'package:honest_sudoku/game/game.dart';

void main() {
  test('defaults are the design defaults: three strikes, announced now', () {
    const s = GameSettings();
    expect(s.strikeMode, StrikeMode.three);
    expect(s.announce, AnnounceMode.now);
    expect(
      [
        s.autoNotes,
        s.autoClear,
        s.conflicts,
        s.hintWhy,
        s.hlSame,
        s.hlUnit,
        s.dimDone,
        s.showTimer,
        s.bigDigits,
      ],
      [false, true, true, true, true, true, true, true, false],
    );
  });

  test('an unset toggle reads its default, as the design opt() does', () {
    expect(GameSettings.fromToggles(const {}), const GameSettings());
    final s = GameSettings.fromToggles(const {
      'autoNotes': true,
      'hlSame': false,
    });
    expect([s.autoNotes, s.hlSame, s.autoClear], [true, false, true]);
  });

  test('strike and announce modes carry the setup labels and limits', () {
    expect(
      [for (final m in StrikeMode.values) m.label],
      ['Zen', '3', '5', 'No limit'],
    );
    expect([for (final m in StrikeMode.values) m.limit], [null, 3, 5, null]);
    expect(
      [for (final m in StrikeMode.values) m.countsMistakes],
      [false, true, true, true],
    );
    expect(
      [for (final m in AnnounceMode.values) m.label],
      ['Immediately', 'At the end'],
    );
  });

  test('value equality and copyWith', () {
    const a = GameSettings();
    expect(a.copyWith(bigDigits: true), isNot(a));
    expect(a.copyWith(bigDigits: true).copyWith(bigDigits: false), a);
    expect(a.hashCode, const GameSettings().hashCode);
  });
}
