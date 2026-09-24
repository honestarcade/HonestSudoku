// JSON for the three documents, written by hand with explicit keys so a
// rename is a migration, never an accident. Decoding throws FormatException
// on anything it cannot trust — an unknown enum name, a list of the wrong
// length, a value out of range — and the store turns that into Corrupt.
// Extra keys are ignored; missing optional keys take their defaults.

import 'package:honest_sudoku/engine/engine.dart';
import 'package:honest_sudoku/game/game.dart';

/// Keeps the newest [kHistoryCap] snapshots.
List<Snapshot> _capped(List<Snapshot> list) =>
    list.length > kHistoryCap ? list.sublist(list.length - kHistoryCap) : list;

T _byName<T extends Enum>(List<T> values, Object? name, String field) {
  for (final v in values) {
    if (v.name == name) return v;
  }
  throw FormatException('unknown $field: $name');
}

Map<String, Object?> _map(Object? v, String field) {
  if (v is Map<String, Object?>) return v;
  throw FormatException('$field is not an object');
}

int _int(Object? v, String field) {
  if (v is int) return v;
  throw FormatException('$field is not an integer');
}

bool _bool(Object? v, String field, {bool? orElse}) {
  if (v == null && orElse != null) return orElse;
  if (v is bool) return v;
  throw FormatException('$field is not a boolean');
}

List<Object?> _list(Object? v, String field) {
  if (v is List<Object?>) return v;
  throw FormatException('$field is not a list');
}

List<int> _ints(Object? v, String field) => [
  for (final e in _list(v, field)) _int(e, field),
];

// ---- settings --------------------------------------------------------------

/// Settings to JSON.
Map<String, Object?> encodeSettings(AppSettings s) => {
  'game': {
    for (final t in SettingToggle.values) t.key: t.read(s.game),
    'strikeMode': s.game.strikeMode.name,
    'announceMode': s.game.announce.name,
  },
  'themeKey': s.themeKey,
  for (final t in SoundToggle.values) t.key: t.read(s),
  'lastSetup': {
    'shape': s.lastSetup.shapeLabel,
    'difficulty': s.lastSetup.difficultyKey,
    'strikeMode': s.lastSetup.strikeMode.name,
    'announceMode': s.lastSetup.announce.name,
  },
};

/// JSON to settings.
AppSettings decodeSettings(Map<String, Object?> json) {
  const defaults = AppSettings();
  final gameJson = json['game'] == null
      ? const <String, Object?>{}
      : _map(json['game'], 'game');
  var game = defaults.game;
  for (final t in SettingToggle.values) {
    game = t.write(
      game,
      _bool(gameJson[t.key], t.key, orElse: t.read(defaults.game)),
    );
  }
  if (gameJson['strikeMode'] != null) {
    game = game.copyWith(
      strikeMode: _byName(
        StrikeMode.values,
        gameJson['strikeMode'],
        'strikeMode',
      ),
    );
  }
  if (gameJson['announceMode'] != null) {
    game = game.copyWith(
      announce: _byName(
        AnnounceMode.values,
        gameJson['announceMode'],
        'announceMode',
      ),
    );
  }
  final theme = json['themeKey'] ?? defaults.themeKey;
  if (theme != 'navy' && theme != 'paper') {
    throw FormatException('unknown themeKey: $theme');
  }
  var settings = AppSettings(game: game, themeKey: theme as String);
  for (final t in SoundToggle.values) {
    settings = t.write(settings, _bool(json[t.key], t.key, orElse: true));
  }
  return settings.copyWith(lastSetup: _decodeLastSetup(json['lastSetup']));
}

LastSetup _decodeLastSetup(Object? v) {
  if (v == null) return const LastSetup();
  final m = _map(v, 'lastSetup');
  try {
    final setup = LastSetup(
      shapeLabel: m['shape'] as String? ?? '9×9',
      difficultyKey: m['difficulty'] as String? ?? 'medium',
      strikeMode: m['strikeMode'] == null
          ? StrikeMode.three
          : _byName(StrikeMode.values, m['strikeMode'], 'strikeMode'),
      announce: m['announceMode'] == null
          ? AnnounceMode.now
          : _byName(AnnounceMode.values, m['announceMode'], 'announceMode'),
    );
    // An unknown or unsupported pair resets only the last setup.
    if (!supportedDifficulties(setup.shape).contains(setup.difficulty)) {
      return const LastSetup();
    }
    return setup;
  } on Object {
    return const LastSetup();
  }
}

// ---- saved game ------------------------------------------------------------

Map<String, Object?> _encodeSnapshot(Snapshot s) => {
  'values': s.values,
  'notes': s.notes,
  'mistakes': s.mistakes,
  'moves': s.moves,
};

Snapshot _decodeSnapshot(Object? v, int cells) {
  final m = _map(v, 'snapshot');
  final values = _ints(m['values'], 'snapshot.values');
  final notes = [
    for (final n in _list(m['notes'], 'snapshot.notes')) _ints(n, 'note'),
  ];
  if (values.length != cells || notes.length != cells) {
    throw const FormatException('snapshot has the wrong length');
  }
  return Snapshot(
    List.unmodifiable(values),
    List.unmodifiable([for (final n in notes) List<int>.unmodifiable(n)]),
    _int(m['mistakes'], 'snapshot.mistakes'),
    _int(m['moves'], 'snapshot.moves'),
  );
}

/// A saved game to JSON.
Map<String, Object?> encodeGame(SavedGame g) => {
  'shape': g.shape.label,
  'difficulty': g.difficulty.key,
  'seed': g.seed,
  'solution': g.solution,
  'givens': g.givens,
  'values': g.values,
  'notes': g.notes,
  'mistakes': g.mistakes,
  'moves': g.moves,
  'elapsed': g.elapsedSeconds,
  'strikeMode': g.strikeMode.name,
  'announceMode': g.announce.name,
  'history': [for (final s in g.history) _encodeSnapshot(s)],
  'future': [for (final s in g.future) _encodeSnapshot(s)],
  'revealed': g.revealed,
  'won': g.won,
  'lost': g.lost,
  'noteMode': g.noteMode,
  'selected': g.selected,
};

/// JSON to a saved game. Checks that it would restore: the lists fit the
/// size, the values are in range, the givens match the solution.
SavedGame decodeGame(Map<String, Object?> json) {
  final GridShape shape;
  final Difficulty difficulty;
  try {
    shape = GridShape.byLabel(json['shape']! as String);
    difficulty = Difficulty.byKey(json['difficulty']! as String);
  } on Object catch (e) {
    throw FormatException('bad shape or difficulty: $e');
  }
  final cells = shape.cellCount;
  final givens = [
    for (final g in _list(json['givens'], 'givens')) _bool(g, 'givens'),
  ];
  final game = SavedGame(
    shape: shape,
    difficulty: difficulty,
    seed: _int(json['seed'], 'seed'),
    solution: _ints(json['solution'], 'solution'),
    givens: givens,
    values: _ints(json['values'], 'values'),
    notes: [for (final n in _list(json['notes'], 'notes')) _ints(n, 'note')],
    mistakes: _int(json['mistakes'], 'mistakes'),
    moves: _int(json['moves'], 'moves'),
    elapsedSeconds: _int(json['elapsed'], 'elapsed'),
    strikeMode: _byName(StrikeMode.values, json['strikeMode'], 'strikeMode'),
    announce: _byName(
      AnnounceMode.values,
      json['announceMode'],
      'announceMode',
    ),
    history: _capped([
      for (final s in _list(json['history'] ?? const [], 'history'))
        _decodeSnapshot(s, cells),
    ]),
    future: _capped([
      for (final s in _list(json['future'] ?? const [], 'future'))
        _decodeSnapshot(s, cells),
    ]),
    revealed: _bool(json['revealed'], 'revealed', orElse: false),
    won: _bool(json['won'], 'won', orElse: false),
    lost: _bool(json['lost'], 'lost', orElse: false),
    noteMode: _bool(json['noteMode'], 'noteMode', orElse: false),
    selected: json['selected'] == null
        ? null
        : _int(json['selected'], 'selected'),
  );
  if (game.notes.length != cells) {
    throw const FormatException('notes have the wrong length');
  }
  for (var i = 0; i < cells && i < game.values.length; i++) {
    if (game.givens.length == cells &&
        game.solution.length == cells &&
        game.givens[i] &&
        game.values[i] != game.solution[i]) {
      throw const FormatException('a given differs from the solution');
    }
  }
  try {
    game.toState(const GameSettings());
  } on Object catch (e) {
    throw FormatException('the game does not restore: $e');
  }
  return game;
}

// ---- statistics ------------------------------------------------------------

/// Statistics to JSON: `{shapes: {difficulty: {shape: {...}}}, streaks}`.
Map<String, Object?> encodeStats(StatsBook b) {
  final shapes = <String, Map<String, Object?>>{};
  for (final e in b.entries) {
    final (d, shape) = e.key;
    final s = e.value;
    (shapes[d.key] ??= {})[shape.label] = {
      'started': s.started,
      'solved': s.solved,
      'best': s.bestSeconds,
      'total': s.solvedSecondsTotal,
      'time': s.timePlayedSeconds,
    };
  }
  return {
    'shapes': shapes,
    'streaks': {for (final e in b.streaks.entries) e.key.key: e.value},
  };
}

/// JSON to statistics.
StatsBook decodeStats(Map<String, Object?> json) {
  final shapes = <(Difficulty, GridShape), ShapeStats>{};
  try {
    final byDifficulty = _map(json['shapes'] ?? const {}, 'shapes');
    for (final d in byDifficulty.entries) {
      final difficulty = Difficulty.byKey(d.key);
      for (final s in _map(d.value, d.key).entries) {
        final m = _map(s.value, s.key);
        shapes[(difficulty, GridShape.byLabel(s.key))] = ShapeStats(
          started: _int(m['started'], 'started'),
          solved: _int(m['solved'], 'solved'),
          bestSeconds: m['best'] == null ? null : _int(m['best'], 'best'),
          solvedSecondsTotal: _int(m['total'], 'total'),
          timePlayedSeconds: _int(m['time'], 'time'),
        );
      }
    }
    final streaks = {
      for (final e in _map(json['streaks'] ?? const {}, 'streaks').entries)
        Difficulty.byKey(e.key): _int(e.value, 'streak'),
    };
    return StatsBook(shapes: shapes, streaks: streaks);
  } on FormatException {
    rethrow;
  } on Object catch (e) {
    throw FormatException('bad statistics: $e');
  }
}
