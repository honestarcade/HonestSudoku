// What a screen reader says for the board (#51): plain functions over plain
// values, so every phrase is unit-tested apart from the widgets.
//
// A cell reads `Row 3, column 5, 7, given`; the suffixes come in a fixed
// order (value, given, notes, wrong, conflict, hint). Times are spoken, not
// read as digits: `0:42` would be "zero colon forty-two".

import 'package:flutter/semantics.dart';

/// The tag every cell node carries, for the tap-target exemption (#56).
const SemanticsTag kGridCellTag = SemanticsTag('grid-cell');

/// A cell: [row] and [col] are 1-based; [value] is the symbol shown, or
/// null when empty; [notes] are the pencil marks as symbols, [candidates]
/// when they are auto-candidates rather than the player's.
String cellLabel({
  required int row,
  required int col,
  required String? value,
  bool given = false,
  List<String> notes = const [],
  bool candidates = false,
  bool wrong = false,
  bool conflict = false,
  bool hint = false,
}) => [
  'Row $row',
  'column $col',
  value ?? 'empty',
  if (given) 'given',
  if (value == null && notes.isNotEmpty)
    '${candidates ? 'candidates' : 'notes'} ${notes.join(' ')}',
  if (wrong) 'wrong',
  if (conflict) 'conflict',
  if (hint) 'hint',
].join(', ');

/// A pad key: `Place 3`, `Note 3` in note mode, `, all placed` when dimmed.
String padKeyLabel({
  required String symbol,
  bool note = false,
  bool allPlaced = false,
}) => '${note ? 'Note' : 'Place'} $symbol${allPlaced ? ', all placed' : ''}';

/// The tools under the pad.
enum Tool {
  /// ↺
  undo,

  /// ↻
  redo,

  /// ✎
  notes,

  /// ⌫
  erase,

  /// ✦
  hint,

  /// ✓
  check,
}

/// A tool: the notes tool says `, on` in note mode and is `Auto notes` while
/// auto-candidates are on.
String toolLabel(Tool tool, {bool noteMode = false, bool autoNotes = false}) =>
    switch (tool) {
      Tool.undo => 'Undo',
      Tool.redo => 'Redo',
      Tool.notes => autoNotes ? 'Auto notes' : 'Notes${noteMode ? ', on' : ''}',
      Tool.erase => 'Erase',
      Tool.hint => 'Hint',
      Tool.check => 'Check',
    };

/// A size as spoken: `9×9` → `9 by 9`.
String sizeWords(String sizeLabel) => sizeLabel.replaceAll('×', ' by ');

/// The pause button: `Pause, 9 by 9, Medium`.
String pauseLabel(String sizeLabel, String difficulty) =>
    'Pause, ${sizeWords(sizeLabel)}, $difficulty';

String _plural(int n, String unit, [String? many]) =>
    '$n ${n == 1 ? unit : many ?? '${unit}s'}';

/// A duration in words: `3 minutes 42 seconds`, `1 hour 2 minutes`,
/// `0 seconds`. Zero parts are left out once a larger part is present.
String durationWords(int seconds) {
  final h = seconds ~/ 3600;
  final m = seconds % 3600 ~/ 60;
  final s = seconds % 60;
  final parts = [
    if (h > 0) _plural(h, 'hour'),
    if (m > 0) _plural(m, 'minute'),
    if (s > 0 || (h == 0 && m == 0)) _plural(s, 'second'),
  ];
  return parts.join(' ');
}

/// The timer chip: `Time 3 minutes 42 seconds`.
String timeLabel(int seconds) => 'Time ${durationWords(seconds)}';

/// The strike chip: `Zen mode`, `1 of 3 mistakes`, `1 mistake`.
String strikeLabel({required int mistakes, int? limit, bool zen = false}) {
  if (zen) return 'Zen mode';
  if (limit != null) return '$mistakes of $limit mistakes';
  return _plural(mistakes, 'mistake');
}

/// `GRID FULL` → `Grid full`.
String sentenceCase(String tag) =>
    tag.isEmpty ? tag : tag[0].toUpperCase() + tag.substring(1).toLowerCase();

String _sentence(String s) {
  final t = s.trim();
  return t.isEmpty || '.!?'.contains(t[t.length - 1]) ? t : '$t.';
}

/// The notice banner: `Mistake. Strike 1 of 3.`
String noticeLabel(String tag, String body) =>
    '${_sentence(sentenceCase(tag))} ${_sentence(body)}'.trim();

/// A card's announced title: `Puzzle solved. Grid complete.`, or `Paused`
/// for a card with no tag.
String overlayTitleLabel(String? tag, String title) =>
    tag == null ? title : '${_sentence(sentenceCase(tag))} ${_sentence(title)}';

/// A stat tile: `Time, 3 minutes 42 seconds`.
String tileLabel(String name, String value) => '${sentenceCase(name)}, $value';

/// The pause card's meta: `9 by 9, Medium, 3 minutes 42 seconds`.
String pauseMetaLabel(String sizeLabel, String difficulty, int seconds) =>
    '${sizeWords(sizeLabel)}, $difficulty, ${durationWords(seconds)}';

/// The pause card's fill line: `12 of 81 cells filled, 40 entries, 2
/// mistakes` (or `zen mode`).
String fillLabel({
  required int filled,
  required int cells,
  required int entries,
  required int mistakes,
  bool zen = false,
}) =>
    '$filled of $cells cells filled, ${_plural(entries, 'entry', 'entries')}, '
    '${zen ? 'zen mode' : _plural(mistakes, 'mistake')}';
