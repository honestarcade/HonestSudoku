// Every sentence the engine hands the player, in the design's words.
//
// Copied from the design file's `hint()`, `check()` and `place()`. The
// grammar is kept verbatim, including `1 cells to go.`, so a later copy pass
// has exactly one place to change it.

/// How the board screen colours a notice banner.
enum BannerKind { hint, ok, error }

/// Which rule a hint used.
enum HintKind { nakedSingle, hiddenSingle, harderStep }

/// Tag for a naked-single hint.
const String kTagNakedSingle = 'NAKED SINGLE';

/// Tag for a hidden-single hint.
const String kTagHiddenSingle = 'HIDDEN SINGLE';

/// Tag for a hint with no single-step deduction.
const String kTagHarderStep = 'HARDER STEP';

/// Tag for the check result.
const String kTagCheck = 'CHECK';

/// Tag for an announced mistake.
const String kTagMistake = 'MISTAKE';

/// Tag for a full grid with wrong entries.
const String kTagGridFull = 'GRID FULL';

/// The tag the design shows for [kind].
String tagFor(HintKind kind) => switch (kind) {
  HintKind.nakedSingle => kTagNakedSingle,
  HintKind.hiddenSingle => kTagHiddenSingle,
  HintKind.harderStep => kTagHarderStep,
};

/// A naked single, explained.
String nakedSingleBody(String cell, String symbol) =>
    '$cell can only be $symbol — its row, column and box already use every '
    'other number.';

/// A hidden single, explained. [unitName] is `row k`, `column k` or
/// `this box`.
String hiddenSingleBody(String cell, String symbol, String unitName) =>
    '$symbol fits in only one cell of $unitName — $cell.';

/// Either single with explanations off.
String tryCellBody(String cell) => 'Try $cell.';

/// A cell no single-step deduction reaches; always reveals the value.
String harderStepBody(String cell, String symbol) =>
    'No single-step deduction left here. $cell is $symbol — you would need a '
    'pair or a chain to prove it.';

/// The check with [wrong] wrong entries (at least one).
String checkWrongBody(int wrong) =>
    '$wrong${wrong == 1 ? ' number is' : ' numbers are'} wrong — marked in '
    'red. They stay marked until you clear them.';

/// The check with nothing wrong and [remaining] empty cells.
String checkCleanBody(int remaining) =>
    'Everything on the board so far is correct. $remaining cells to go.';

/// An announced mistake: [mistakes] so far, against [limit] strikes, or no
/// limit when [limit] is null.
String mistakeBody(int mistakes, int? limit) =>
    'That number cannot go there. '
    '${limit == null ? '$mistakes so far — no limit set.' : 'Strike $mistakes of $limit.'}';

/// A full grid that still holds wrong entries.
const String kGridFullBody =
    'Some numbers are wrong — the ones in red. Fix them and the puzzle '
    'finishes itself.';

/// A full grid with wrong entries in Zen, where nothing is ever tinted red,
/// so the design's "the ones in red" would point at nothing (owner's call,
/// 2026-09-18).
const String kGridFullBodyZen =
    'Some numbers are wrong. Fix them and the puzzle finishes itself.';
