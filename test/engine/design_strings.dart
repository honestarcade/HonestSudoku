// Expected sentences, as literals. Each one is the output of the design
// file's own `hint()` (Honest Sudoku.dc.html, lines 1136–1164) or the text of
// its `check()`/`place()` (lines 1084, 1094, 1127–1128), run in node v24.15.0
// on 2026-09-23 over the same fixture the test uses. They are never built
// from the implementation's templates.

const nakedR1C1is1 =
    'R1C1 can only be 1 — its row, column and box already use every other '
    'number.';
const nakedR5C6is4 =
    'R5C6 can only be 4 — its row, column and box already use every other '
    'number.';
const nakedR2C2is5 =
    'R2C2 can only be 5 — its row, column and box already use every other '
    'number.';
const nakedR1C10isA =
    'R1C10 can only be A — its row, column and box already use every other '
    'number.';
const nakedR9C9is2 =
    'R9C9 can only be 2 — its row, column and box already use every other '
    'number.';
const hidden1Row1 = '1 fits in only one cell of row 1 — R1C1.';
const hiddenARow1 = 'A fits in only one cell of row 1 — R1C1.';
const hidden3Box = '3 fits in only one cell of this box — R9C9.';
const tryR1C1 = 'Try R1C1.';
const tryR1C10 = 'Try R1C10.';
const tryR9C9 = 'Try R9C9.';
const harderR1C1is4 =
    'No single-step deduction left here. R1C1 is 4 — you would need a pair '
    'or a chain to prove it.';
const harderR1C1isG =
    'No single-step deduction left here. R1C1 is G — you would need a pair '
    'or a chain to prove it.';
const checkOneWrong =
    '1 number is wrong — marked in red. They stay marked until you clear '
    'them.';
const checkTwoWrong =
    '2 numbers are wrong — marked in red. They stay marked until you clear '
    'them.';
const checkClean3 = 'Everything on the board so far is correct. 3 cells to go.';
const checkClean1 = 'Everything on the board so far is correct. 1 cells to go.';
const checkClean0 = 'Everything on the board so far is correct. 0 cells to go.';
const mistakeStrike2of3 = 'That number cannot go there. Strike 2 of 3.';
const mistakeNoLimit4 = 'That number cannot go there. 4 so far — no limit set.';
const gridFull =
    'Some numbers are wrong — the ones in red. Fix them and the puzzle '
    'finishes itself.';
