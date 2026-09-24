// The settings that change how a board plays: the strike and announce modes
// chosen on the setup screen, and the board-affecting toggles from the
// design's SETTING_ROWS with their defaults.

/// How many wrong entries a puzzle allows.
enum StrikeMode {
  /// Never counts a mistake.
  zen(null, 'Zen'),

  /// Ends the puzzle on the third.
  three(3, '3'),

  /// Ends the puzzle on the fifth.
  five(5, '5'),

  /// Counts, never ends the puzzle.
  unlimited(null, 'No limit');

  const StrikeMode(this.limit, this.label);

  /// The strike that ends the puzzle, or null when none does.
  final int? limit;

  /// The setup screen's label.
  final String label;

  /// False only for Zen.
  bool get countsMistakes => this != zen;
}

/// When a wrong entry is announced.
enum AnnounceMode {
  /// A MISTAKE notice at once.
  now('Immediately'),

  /// Only when the grid fills up or the player taps Check.
  atEnd('At the end');

  const AnnounceMode(this.label);

  /// The setup screen's label.
  final String label;
}

/// The design's SETTING_ROWS keys that affect the board, with their `def`.
const Map<String, bool> kBoardSettingDefaults = {
  'autoNotes': false,
  'autoClear': true,
  'conflicts': true,
  'hintWhy': true,
  'hlSame': true,
  'hlUnit': true,
  'dimDone': true,
  'showTimer': true,
  'bigDigits': false,
};

/// Everything a board needs to know about how the player wants to play.
final class GameSettings {
  /// The design's defaults: three strikes, announced immediately.
  const GameSettings({
    this.strikeMode = StrikeMode.three,
    this.announce = AnnounceMode.now,
    this.autoNotes = false,
    this.autoClear = true,
    this.conflicts = true,
    this.hintWhy = true,
    this.hlSame = true,
    this.hlUnit = true,
    this.dimDone = true,
    this.showTimer = true,
    this.bigDigits = false,
  });

  /// Resolves [toggles] the way the design's `opt()` does: a key that is
  /// not set reads its default.
  factory GameSettings.fromToggles(
    Map<String, bool> toggles, {
    StrikeMode strikeMode = StrikeMode.three,
    AnnounceMode announce = AnnounceMode.now,
  }) {
    bool opt(String key) => toggles[key] ?? kBoardSettingDefaults[key]!;
    return GameSettings(
      strikeMode: strikeMode,
      announce: announce,
      autoNotes: opt('autoNotes'),
      autoClear: opt('autoClear'),
      conflicts: opt('conflicts'),
      hintWhy: opt('hintWhy'),
      hlSame: opt('hlSame'),
      hlUnit: opt('hlUnit'),
      dimDone: opt('dimDone'),
      showTimer: opt('showTimer'),
      bigDigits: opt('bigDigits'),
    );
  }

  /// Mistakes allowed.
  final StrikeMode strikeMode;

  /// When mistakes are announced.
  final AnnounceMode announce;

  /// Keep every empty cell marked with its candidates.
  final bool autoNotes;

  /// Placing a number removes it from its peers' pencil marks.
  final bool autoClear;

  /// Tint the peers that clash with the selected number.
  final bool conflicts;

  /// Hints name the rule, not just the cell.
  final bool hintWhy;

  /// Light every copy of the selected number.
  final bool hlSame;

  /// Shade the selected cell's row, column and box.
  final bool hlUnit;

  /// Fade a pad number once all of them are placed.
  final bool dimDone;

  /// Show the elapsed time.
  final bool showTimer;

  /// Heavier numerals, thinner pencil marks.
  final bool bigDigits;

  /// A copy with the given fields replaced.
  GameSettings copyWith({
    StrikeMode? strikeMode,
    AnnounceMode? announce,
    bool? autoNotes,
    bool? autoClear,
    bool? conflicts,
    bool? hintWhy,
    bool? hlSame,
    bool? hlUnit,
    bool? dimDone,
    bool? showTimer,
    bool? bigDigits,
  }) => GameSettings(
    strikeMode: strikeMode ?? this.strikeMode,
    announce: announce ?? this.announce,
    autoNotes: autoNotes ?? this.autoNotes,
    autoClear: autoClear ?? this.autoClear,
    conflicts: conflicts ?? this.conflicts,
    hintWhy: hintWhy ?? this.hintWhy,
    hlSame: hlSame ?? this.hlSame,
    hlUnit: hlUnit ?? this.hlUnit,
    dimDone: dimDone ?? this.dimDone,
    showTimer: showTimer ?? this.showTimer,
    bigDigits: bigDigits ?? this.bigDigits,
  );

  List<Object> get _fields => [
    strikeMode,
    announce,
    autoNotes,
    autoClear,
    conflicts,
    hintWhy,
    hlSame,
    hlUnit,
    dimDone,
    showTimer,
    bigDigits,
  ];

  @override
  bool operator ==(Object other) {
    if (other is! GameSettings) return false;
    final a = _fields;
    final b = other._fields;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAll(_fields);

  @override
  String toString() =>
      'GameSettings(${strikeMode.name}, ${announce.name}, '
      'autoNotes: $autoNotes)';
}
