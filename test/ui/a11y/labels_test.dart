import 'package:flutter_test/flutter_test.dart';
import 'package:honest_sudoku/ui/a11y/labels.dart';

void main() {
  group('cellLabel', () {
    test('value, empty, given', () {
      expect(
        cellLabel(row: 1, col: 1, value: '5', given: true),
        'Row 1, column 1, 5, given',
      );
      expect(cellLabel(row: 1, col: 2, value: null), 'Row 1, column 2, empty');
    });

    test('notes, and auto-candidates, only on an empty cell', () {
      expect(
        cellLabel(row: 3, col: 4, value: null, notes: ['1', '4', '7']),
        'Row 3, column 4, empty, notes 1 4 7',
      );
      expect(
        cellLabel(
          row: 3,
          col: 4,
          value: null,
          notes: ['A', 'C'],
          candidates: true,
        ),
        'Row 3, column 4, empty, candidates A C',
      );
      expect(
        cellLabel(row: 3, col: 4, value: '2', notes: ['1']),
        'Row 3, column 4, 2',
      );
    });

    test('suffixes in order: given, notes, wrong, conflict, hint', () {
      expect(
        cellLabel(
          row: 9,
          col: 9,
          value: '3',
          wrong: true,
          conflict: true,
          hint: true,
        ),
        'Row 9, column 9, 3, wrong, conflict, hint',
      );
      expect(
        cellLabel(row: 2, col: 2, value: null, notes: ['5'], hint: true),
        'Row 2, column 2, empty, notes 5, hint',
      );
    });
  });

  test('pad keys', () {
    expect(padKeyLabel(symbol: '3'), 'Place 3');
    expect(padKeyLabel(symbol: 'A', note: true), 'Note A');
    expect(
      padKeyLabel(symbol: '3', note: true, allPlaced: true),
      'Note 3, all placed',
    );
  });

  test('tools', () {
    expect(Tool.values.map(toolLabel), [
      'Undo',
      'Redo',
      'Notes',
      'Erase',
      'Hint',
      'Check',
    ]);
    expect(toolLabel(Tool.notes, noteMode: true), 'Notes, on');
    expect(
      toolLabel(Tool.notes, noteMode: true, autoNotes: true),
      'Auto notes',
    );
  });

  test('the pause button and sizes', () {
    expect(pauseLabel('9×9', 'Medium'), 'Pause, 9 by 9, Medium');
    expect(sizeWords('16×16'), '16 by 16');
  });

  test('time: plurals, zero parts left out, hours when present', () {
    expect(timeLabel(0), 'Time 0 seconds');
    expect(timeLabel(1), 'Time 1 second');
    expect(timeLabel(42), 'Time 42 seconds');
    expect(timeLabel(60), 'Time 1 minute');
    expect(timeLabel(222), 'Time 3 minutes 42 seconds');
    expect(timeLabel(3600 + 120), 'Time 1 hour 2 minutes');
    expect(timeLabel(7201), 'Time 2 hours 1 second');
  });

  test('strikes', () {
    expect(strikeLabel(mistakes: 2, limit: 3), '2 of 3 mistakes');
    expect(strikeLabel(mistakes: 1, limit: 3), '1 of 3 mistakes');
    expect(strikeLabel(mistakes: 1), '1 mistake');
    expect(strikeLabel(mistakes: 0), '0 mistakes');
    expect(strikeLabel(mistakes: 4, zen: true), 'Zen mode');
  });

  test('notices and card titles are sentence-cased sentences', () {
    expect(noticeLabel('MISTAKE', 'Strike 1 of 3.'), 'Mistake. Strike 1 of 3.');
    expect(
      noticeLabel('GRID FULL', 'Something is wrong'),
      'Grid full. Something is wrong.',
    );
    expect(
      overlayTitleLabel('PUZZLE SOLVED', 'Grid complete'),
      'Puzzle solved. Grid complete.',
    );
    expect(overlayTitleLabel(null, 'Paused'), 'Paused');
  });

  test('tiles, pause meta and fill', () {
    expect(
      tileLabel('TIME', '3 minutes 42 seconds'),
      'Time, 3 minutes 42 seconds',
    );
    expect(
      pauseMetaLabel('9×9', 'Medium', 222),
      '9 by 9, Medium, 3 minutes 42 seconds',
    );
    expect(
      fillLabel(filled: 12, cells: 81, entries: 1, mistakes: 1),
      '12 of 81 cells filled, 1 entry, 1 mistake',
    );
    expect(
      fillLabel(filled: 12, cells: 81, entries: 40, mistakes: 2, zen: true),
      '12 of 81 cells filled, 40 entries, zen mode',
    );
  });

  test('the grid-cell tag', () {
    expect(kGridCellTag.name, 'grid-cell');
  });
}
