// The design's SETTING_ROWS as one table: the key the store writes, the
// label and description the settings screen shows, and how each reads and
// writes its value. The codec, the settings screen and the tests share it,
// so a toggle cannot be spelt two ways.

import 'app_settings.dart';
import 'game_settings.dart';

/// A settings section heading.
enum SettingSection {
  /// ASSISTS.
  assists('ASSISTS'),

  /// DISPLAY.
  display('DISPLAY'),

  /// SOUND.
  sound('SOUND');

  const SettingSection(this.title);

  /// The heading.
  final String title;
}

/// The nine toggles that change how a board plays or looks.
enum SettingToggle {
  /// Auto candidate notes.
  autoNotes(
    SettingSection.assists,
    'Auto candidate notes',
    'Keep every empty cell marked with what still fits.',
  ),

  /// Clear notes on placement.
  autoClear(
    SettingSection.assists,
    'Clear notes on placement',
    'Placing a number removes it from its row, column and box.',
  ),

  /// Highlight conflicts.
  conflicts(
    SettingSection.assists,
    'Highlight conflicts',
    'Tint the cells that clash with the number you just placed.',
  ),

  /// Explain hints.
  hintWhy(
    SettingSection.assists,
    'Explain hints',
    'Say which rule cracked the cell, not just the answer.',
  ),

  /// Highlight same number.
  hlSame(
    SettingSection.display,
    'Highlight same number',
    'Every copy of the selected number lights up.',
  ),

  /// Highlight row, column and box.
  hlUnit(
    SettingSection.display,
    'Highlight row, column and box',
    'Shade the three units the selected cell belongs to.',
  ),

  /// Dim finished numbers.
  dimDone(
    SettingSection.display,
    'Dim finished numbers',
    'Fade a number on the pad once all of them are placed.',
  ),

  /// Show timer.
  showTimer(
    SettingSection.display,
    'Show timer',
    'Elapsed time in the top bar.',
  ),

  /// Large digits.
  bigDigits(
    SettingSection.display,
    'Large digits',
    'Heavier numerals, thinner pencil marks.',
  );

  const SettingToggle(this.section, this.label, this.description);

  /// The heading it sits under.
  final SettingSection section;

  /// The row's label.
  final String label;

  /// The row's description.
  final String description;

  /// The design's key: the enum's name (`autoNotes`, …).
  String get key => name;

  /// Its value in [s].
  bool read(GameSettings s) => switch (this) {
    autoNotes => s.autoNotes,
    autoClear => s.autoClear,
    conflicts => s.conflicts,
    hintWhy => s.hintWhy,
    hlSame => s.hlSame,
    hlUnit => s.hlUnit,
    dimDone => s.dimDone,
    showTimer => s.showTimer,
    bigDigits => s.bigDigits,
  };

  /// [s] with this toggle set to [value].
  GameSettings write(GameSettings s, bool value) => switch (this) {
    autoNotes => s.copyWith(autoNotes: value),
    autoClear => s.copyWith(autoClear: value),
    conflicts => s.copyWith(conflicts: value),
    hintWhy => s.copyWith(hintWhy: value),
    hlSame => s.copyWith(hlSame: value),
    hlUnit => s.copyWith(hlUnit: value),
    dimDone => s.copyWith(dimDone: value),
    showTimer => s.copyWith(showTimer: value),
    bigDigits => s.copyWith(bigDigits: value),
  };
}

/// The two sound toggles, which live on [AppSettings] rather than the game.
enum SoundToggle {
  /// Sound effects.
  sfx('Sound effects', 'A soft click on placement, a thud on a mistake.'),

  /// Haptics.
  haptics('Haptics', 'A short tick when a number lands or clashes.');

  const SoundToggle(this.label, this.description);

  /// The row's label.
  final String label;

  /// The row's description.
  final String description;

  /// The design's key.
  String get key => name;

  /// Its value in [s].
  bool read(AppSettings s) => switch (this) {
    sfx => s.sfx,
    haptics => s.haptics,
  };

  /// [s] with this toggle set to [value].
  AppSettings write(AppSettings s, bool value) => switch (this) {
    sfx => s.copyWith(sfx: value),
    haptics => s.copyWith(haptics: value),
  };
}
