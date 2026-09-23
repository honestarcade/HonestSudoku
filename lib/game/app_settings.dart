// Everything the player sets that outlives a game: the board toggles, the
// board theme, the two sound toggles, and the last setup chosen.

import 'package:honest_sudoku/engine/engine.dart';

import 'game_settings.dart';

/// The setup screen's last choices.
final class LastSetup {
  /// The design's setup defaults: 9×9, Medium, three strikes, immediately.
  const LastSetup({
    this.shapeLabel = '9×9',
    this.difficultyKey = 'medium',
    this.strikeMode = StrikeMode.three,
    this.announce = AnnounceMode.now,
  });

  /// The size's label.
  final String shapeLabel;

  /// The band's key.
  final String difficultyKey;

  /// Mistakes allowed.
  final StrikeMode strikeMode;

  /// When mistakes are announced.
  final AnnounceMode announce;

  /// The size.
  GridShape get shape => GridShape.byLabel(shapeLabel);

  /// The band.
  Difficulty get difficulty => Difficulty.byKey(difficultyKey);

  /// A copy with the given fields replaced.
  LastSetup copyWith({
    String? shapeLabel,
    String? difficultyKey,
    StrikeMode? strikeMode,
    AnnounceMode? announce,
  }) => LastSetup(
    shapeLabel: shapeLabel ?? this.shapeLabel,
    difficultyKey: difficultyKey ?? this.difficultyKey,
    strikeMode: strikeMode ?? this.strikeMode,
    announce: announce ?? this.announce,
  );

  @override
  bool operator ==(Object other) =>
      other is LastSetup &&
      other.shapeLabel == shapeLabel &&
      other.difficultyKey == difficultyKey &&
      other.strikeMode == strikeMode &&
      other.announce == announce;

  @override
  int get hashCode =>
      Object.hash(shapeLabel, difficultyKey, strikeMode, announce);
}

/// The player's settings.
final class AppSettings {
  /// The design's defaults.
  const AppSettings({
    this.game = const GameSettings(),
    this.themeKey = 'navy',
    this.sfx = true,
    this.haptics = true,
    this.lastSetup = const LastSetup(),
  });

  /// The board toggles (the strike and announce modes here are the setup's;
  /// a saved game keeps its own).
  final GameSettings game;

  /// `navy` or `paper`.
  final String themeKey;

  /// Sound effects.
  final bool sfx;

  /// Haptics.
  final bool haptics;

  /// The setup screen's last choices.
  final LastSetup lastSetup;

  /// A copy with the given fields replaced.
  AppSettings copyWith({
    GameSettings? game,
    String? themeKey,
    bool? sfx,
    bool? haptics,
    LastSetup? lastSetup,
  }) => AppSettings(
    game: game ?? this.game,
    themeKey: themeKey ?? this.themeKey,
    sfx: sfx ?? this.sfx,
    haptics: haptics ?? this.haptics,
    lastSetup: lastSetup ?? this.lastSetup,
  );

  @override
  bool operator ==(Object other) =>
      other is AppSettings &&
      other.game == game &&
      other.themeKey == themeKey &&
      other.sfx == sfx &&
      other.haptics == haptics &&
      other.lastSetup == lastSetup;

  @override
  int get hashCode => Object.hash(game, themeKey, sfx, haptics, lastSetup);
}
