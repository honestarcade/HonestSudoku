// Literal copies of the design file's RULES, GESTURES, FEATURES and PROMISES
// tables (Honest Sudoku.dc.html, lines 919–949), extracted with node on
// 2026-09-23 — independent of lib/ui/copy.dart, which the tests check.

const designRules = [
  (
    'THE GOAL',
    'Fill every empty cell so that each row, each column and each box contains all the numbers exactly once. On 16×16 the numbers run 1 to 9, then A to G.',
  ),
  (
    'ENTERING A NUMBER',
    'Tap a cell, then tap a number on the pad. Tap the same number again to clear the cell. Given numbers are set in stone and cannot be changed.',
  ),
  (
    'PENCIL MARKS',
    'Switch the pad to Notes and your taps leave small candidates instead. Turn on auto candidates in Settings and the app keeps every empty cell marked for you.',
  ),
  (
    'MISTAKES',
    'Choose Zen for a board that never judges you, or three, five or unlimited strikes. Mistakes can be flagged the instant you make one, or held back until the grid is full or you tap Check.',
  ),
  (
    'HINTS',
    'A hint finds the easiest cell left. With explanations on it names the rule: the only number that fits this cell, or the only cell in a unit that can take a number.',
  ),
];

const designGestures = [
  ('TAP CELL', 'Select it. Its row, column and box light up.'),
  ('TAP NUMBER', 'Place it, or leave a pencil mark when Notes is on.'),
  ('TAP AGAIN', 'The same number a second time clears the cell.'),
  ('ERASE', 'Wipes the value and every pencil mark from the selected cell.'),
  (
    'CHECK',
    'Marks any wrong entries right now, whatever your announce setting.',
  ),
];

const designFeatures = [
  (
    'Four grid sizes',
    '4×4 and 6×6 for a short sit, 9×9 classic, 16×16 with 1–9 and A–G.',
  ),
  (
    'Five difficulties',
    'Easy through Evil, generated on the device — never the same puzzle twice.',
  ),
  (
    'Mistakes your way',
    'Zen, three strikes, five strikes or unlimited — announced instantly or held until the end.',
  ),
  (
    'Pencil marks and auto candidates',
    'Mark by hand, or let the app keep every candidate current as you go.',
  ),
  (
    'Hints that explain themselves',
    'Naked single, hidden single — it names the rule and the unit it used.',
  ),
  (
    'Honest statistics',
    'Solves, streaks, best times and average times, split by size and difficulty.',
  ),
];

const designPromises = [
  (
    'No ads. Ever.',
    'No banners, no interstitials, no "watch a video to unlock". What you open is the whole thing.',
  ),
  (
    'No tracking, no analytics',
    'We collect nothing. No identifiers, no crash pings, no usage events.',
  ),
  (
    'No accounts, no sign-in',
    'Your progress stays on your device (unless an account is explicitly needed for the app to function).',
  ),
  (
    'No in-app purchases',
    'Everything is included. Nothing is held back for money.',
  ),
  (
    'No permissions',
    'We ask for nothing — no contacts, no location, no storage, no network (unless explicitly needed for the app to function).',
  ),
  (
    'Open source',
    'The code is readable. Check how it works rather than taking our word for it.',
  ),
  (
    'Works offline, stays small',
    'No background activity, no battery drain while you are not using it (unless being online is explicitly needed for the app to function).',
  ),
];
