// The board inside the app mark: 29 givens, symmetric under a half turn, and
// three teal entries. Transcribed from the mark SVG in Honest Sudoku.dc.html
// on 2026-09-23; the design's five copies of the mark hold the same digits.

/// A digit in the mark's 9×9 board, zero-based.
typedef MarkDigit = ({int row, int col, int value});

/// The givens, drawn in Outfit 700.
const List<MarkDigit> kMarkGivens = [
  (row: 0, col: 0, value: 5),
  (row: 0, col: 2, value: 4),
  (row: 0, col: 6, value: 9),
  (row: 0, col: 8, value: 2),
  (row: 1, col: 1, value: 7),
  (row: 1, col: 4, value: 9),
  (row: 1, col: 7, value: 4),
  (row: 2, col: 0, value: 1),
  (row: 2, col: 3, value: 3),
  (row: 2, col: 5, value: 2),
  (row: 3, col: 2, value: 9),
  (row: 3, col: 6, value: 4),
  (row: 4, col: 0, value: 4),
  (row: 4, col: 3, value: 8),
  (row: 4, col: 4, value: 5),
  (row: 4, col: 5, value: 3),
  (row: 4, col: 8, value: 1),
  (row: 5, col: 2, value: 3),
  (row: 5, col: 6, value: 8),
  (row: 6, col: 3, value: 5),
  (row: 6, col: 5, value: 7),
  (row: 6, col: 8, value: 4),
  (row: 7, col: 1, value: 8),
  (row: 7, col: 4, value: 1),
  (row: 7, col: 7, value: 3),
  (row: 8, col: 0, value: 3),
  (row: 8, col: 2, value: 5),
  (row: 8, col: 6, value: 1),
  (row: 8, col: 8, value: 9),
];

/// The player's entries, drawn in teal Outfit 600.
const List<MarkDigit> kMarkEntries = [
  (row: 1, col: 2, value: 2),
  (row: 3, col: 4, value: 6),
  (row: 6, col: 1, value: 6),
];
