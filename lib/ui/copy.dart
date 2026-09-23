// The app's own words for every screen but the board, verbatim from the
// design file (its RULES, GESTURES, FEATURES and PROMISES tables and the
// screen templates), plus the failure messages the plan wrote. One place, so
// the accessibility pass and any later translation have one file to read.

/// A rule card on How to play.
typedef Rule = ({String tag, String body});

/// A row in the CONTROLS panel.
typedef Gesture = ({String key, String value});

/// A row in WHAT'S IN IT.
typedef Feature = ({String title, String body});

/// A row in OUR PROMISES; [color] is the tick's colour.
typedef Promise = ({String title, String body, int color});

/// Copy.
abstract final class Copy {
  // ---- loading ------------------------------------------------------------

  /// Under the wordmark (the design upper-cases it).
  static const byline = 'BY HONEST ARCADE';

  /// Generation failure kicker.
  static const generationFailed = 'GENERATION FAILED';

  /// Generation cancelled kicker.
  static const generationCancelled = 'GENERATION CANCELLED';

  /// The time ceiling passed.
  static const failedTimeout = "Couldn't build a board in time. Try again.";

  /// Attempts ran out.
  static const failedAttempts =
      "Couldn't find a board for this seed. Try again.";

  /// Anything else.
  static const failedUnexpected =
      'Something went wrong building the board. Try again.';

  /// The player backed out.
  static const cancelled = 'Board building was cancelled.';

  /// The retry action.
  static const tryAgain = 'TRY AGAIN';

  /// Back from the failure notice.
  static const back = 'Back';

  /// The store could not be opened at launch.
  static const savedDataUnavailable = 'SAVED DATA UNAVAILABLE';

  /// Its body.
  static const savedDataBody = "Couldn't open the app's saved data. Try again.";

  // ---- menu -----------------------------------------------------------------

  /// Under the menu's wordmark.
  static const menuByline = 'BY HONEST ARCADE · NO ADS';

  /// The primary button with a game to resume.
  static const continuePuzzle = 'Continue puzzle';

  /// The primary button without one.
  static const newPuzzle = 'New puzzle';

  /// The New puzzle card's line.
  static const newPuzzleSub = '4×4, 6×6, 9×9 or 16×16 · Easy through Evil';

  /// Menu buttons.
  static const statistics = 'Statistics';

  /// Menu button.
  static const howToPlay = 'How to play';

  /// Menu button.
  static const settings = 'Settings';

  /// Menu button.
  static const aboutApp = 'About the App';

  /// The studio row.
  static const aboutStudio = 'About Honest Arcade';

  /// The studio row's line.
  static const aboutStudioSub = 'No ads, no tracking, open source.';

  /// The menu glyph's fixed digits, by cell index.
  static const menuDigits = {
    0: 5,
    4: 3,
    11: 7,
    24: 9,
    31: 2,
    40: 8,
    50: 4,
    57: 6,
    68: 1,
    74: 3,
    79: 7,
  };

  // ---- setup ----------------------------------------------------------------

  /// Setup title.
  static const setupTitle = 'New puzzle';

  /// Grid size heading.
  static const gridSize = 'Grid size';

  /// Grid size note.
  static const gridSizeNote = '16×16 uses 1–9 then A–G. Boxes are 4×4.';

  /// Difficulty heading.
  static const difficulty = 'Difficulty';

  /// Mistakes heading.
  static const mistakesAllowed = 'Mistakes allowed';

  /// Setup's mistakes description.
  static const setupMistakesDesc =
      'Zen never counts one. A strike limit ends the puzzle when you hit it.';

  /// Announce heading.
  static const announceMistakes = 'Announce mistakes';

  /// Setup's announce description.
  static const setupAnnounceDesc =
      'Immediately, or only when the grid fills up or you tap Check.';

  /// Start.
  static const startPuzzle = 'Start puzzle';

  /// Keep playing.
  static const keepPlaying = 'Keep playing the current puzzle';

  /// A difficulty the size does not offer (planner wording; the design has
  /// none, because its prototype never greys a card).
  static String notOn(String size) => 'NOT ON $size';

  // ---- settings -------------------------------------------------------------

  /// Board theme heading.
  static const boardTheme = 'Board theme';

  /// Board theme note.
  static const boardThemeNote =
      'Deep navy felt, or a light paper grid. The rest of the app stays navy.';

  /// Settings' mistakes description.
  static const settingsMistakesDesc =
      'Zen never counts a mistake and never marks a cell wrong.';

  /// Settings' announce description.
  static const settingsAnnounceDesc =
      'Straight away, or only when the grid is full or you tap Check.';

  /// Stored-on-device kicker.
  static const storedOnDevice = 'STORED ON DEVICE ONLY';

  /// Stored-on-device paragraph.
  static const storedOnDeviceBody =
      'Puzzles are generated on your phone. Progress, statistics and settings '
      'never leave it — no account, no sync, nothing to delete on a server.';

  /// The theme previews' fixed sample: 32 cells, 0 empty.
  static const themeSample = [
    5, 0, 2, 0, 0, 8, 0, 1, 0, 7, 0, 3, 9, 0, 0, 4, //
    6, 0, 0, 1, 0, 0, 2, 0, 0, 0, 4, 0, 7, 0, 5, 0,
  ];

  // ---- statistics -----------------------------------------------------------

  /// By-size heading.
  static const byGridSize = 'BY GRID SIZE';

  /// Reset button.
  static const resetStatistics = 'Reset statistics';

  /// Confirmation title.
  static const resetTitle = 'Reset statistics?';

  /// Confirmation paragraph.
  static const resetBody =
      'Clears every solved puzzle, streak and best time at every size and '
      'difficulty. Nothing was ever uploaded, so this is the only copy.';

  /// Confirmation buttons.
  static const cancel = 'Cancel';

  /// Confirmation buttons.
  static const reset = 'Reset';

  // ---- how to play ----------------------------------------------------------

  /// The design's RULES.
  static const List<Rule> rules = [
    (
      tag: 'THE GOAL',
      body:
          'Fill every empty cell so that each row, each column and each box '
          'contains all the numbers exactly once. On 16×16 the numbers run 1 to '
          '9, then A to G.',
    ),
    (
      tag: 'ENTERING A NUMBER',
      body:
          'Tap a cell, then tap a number on the pad. Tap the same number again '
          'to clear the cell. Given numbers are set in stone and cannot be '
          'changed.',
    ),
    (
      tag: 'PENCIL MARKS',
      body:
          'Switch the pad to Notes and your taps leave small candidates '
          'instead. Turn on auto candidates in Settings and the app keeps every '
          'empty cell marked for you.',
    ),
    (
      tag: 'MISTAKES',
      body:
          'Choose Zen for a board that never judges you, or three, five or '
          'unlimited strikes. Mistakes can be flagged the instant you make one, '
          'or held back until the grid is full or you tap Check.',
    ),
    (
      tag: 'HINTS',
      body:
          'A hint finds the easiest cell left. With explanations on it names '
          'the rule: the only number that fits this cell, or the only cell in a '
          'unit that can take a number.',
    ),
  ];

  /// CONTROLS heading.
  static const controls = 'CONTROLS';

  /// The design's GESTURES.
  static const List<Gesture> gestures = [
    (key: 'TAP CELL', value: 'Select it. Its row, column and box light up.'),
    (
      key: 'TAP NUMBER',
      value: 'Place it, or leave a pencil mark when Notes is on.',
    ),
    (key: 'TAP AGAIN', value: 'The same number a second time clears the cell.'),
    (
      key: 'ERASE',
      value: 'Wipes the value and every pencil mark from the selected cell.',
    ),
    (
      key: 'CHECK',
      value:
          'Marks any wrong entries right now, whatever your announce setting.',
    ),
  ];

  // ---- about the app --------------------------------------------------------

  /// The app's name.
  static const appName = 'Honest Sudoku';

  /// About the App's paragraph.
  static const aboutIntro =
      'Sudoku with the options set properly. Four grid sizes, five '
      'difficulties, and every assist off or on as you like it — strike limits, '
      'when mistakes are announced, conflict highlighting, pencil marks, auto '
      'candidates, hints that explain themselves. Puzzles are generated on the '
      'device, so it works with the radio off forever.';

  /// Features heading.
  static const whatsInIt = "WHAT'S IN IT";

  /// The design's FEATURES.
  static const List<Feature> features = [
    (
      title: 'Four grid sizes',
      body: '4×4 and 6×6 for a short sit, 9×9 classic, 16×16 with 1–9 and A–G.',
    ),
    (
      title: 'Five difficulties',
      body:
          'Easy through Evil, generated on the device — never the same puzzle '
          'twice.',
    ),
    (
      title: 'Mistakes your way',
      body:
          'Zen, three strikes, five strikes or unlimited — announced instantly '
          'or held until the end.',
    ),
    (
      title: 'Pencil marks and auto candidates',
      body: 'Mark by hand, or let the app keep every candidate current as you go.',
    ),
    (
      title: 'Hints that explain themselves',
      body: 'Naked single, hidden single — it names the rule and the unit it used.',
    ),
    (
      title: 'Honest statistics',
      body:
          'Solves, streaks, best times and average times, split by size and '
          'difficulty.',
    ),
  ];

  /// Promises heading on About the App.
  static const honestPromises = 'THE HONEST PROMISES';

  /// The seven chips.
  static const promiseChips = [
    'NO ADS',
    'NO TRACKING',
    'NO ACCOUNTS',
    'NO PURCHASES',
    'NO PERMISSIONS',
    'OPEN SOURCE',
    'WORKS OFFLINE',
  ];

  /// The button to the studio screen.
  static const promisesButton = 'Honest Arcade Promises';

  /// Footer lead.
  static const madeBy = 'MADE BY';

  /// Link label.
  static const linkHonestArcade = 'HONEST ARCADE ↗';

  /// Link label.
  static const linkSource = 'SOURCE ON GITHUB ↗';

  // ---- about honest arcade --------------------------------------------------

  /// The studio's first paragraph.
  static const studioIntro =
      'Honest Arcade makes simple games and useful apps with no ads, no '
      'tracking, and no hidden agenda. Everything we build is open source, so '
      "you can see exactly what you're getting.";

  /// The studio's second paragraph.
  static const studioLine =
      'Just good software that respects your time, privacy, and device.';

  /// Support card kicker.
  static const supportKicker = 'SUPPORT HONEST ARCADE';

  /// Support card body.
  static const supportBody =
      "Our games stay free and ad-free because people chip in. If you'd like "
      'to help keep them that way, visit the website for details.';

  /// Support card link line.
  static const supportLink = 'honestarcade.app/contribute →';

  /// Promises heading on the studio screen.
  static const ourPromises = 'OUR PROMISES';

  /// The design's PROMISES.
  static const List<Promise> promises = [
    (
      title: 'No ads. Ever.',
      body:
          'No banners, no interstitials, no "watch a video to unlock". What '
          'you open is the whole thing.',
      color: 0xFF00D6B4,
    ),
    (
      title: 'No tracking, no analytics',
      body: 'We collect nothing. No identifiers, no crash pings, no usage events.',
      color: 0xFF6FB4FF,
    ),
    (
      title: 'No accounts, no sign-in',
      body:
          'Your progress stays on your device (unless an account is explicitly '
          'needed for the app to function).',
      color: 0xFFB48CFF,
    ),
    (
      title: 'No in-app purchases',
      body: 'Everything is included. Nothing is held back for money.',
      color: 0xFF00D6B4,
    ),
    (
      title: 'No permissions',
      body:
          'We ask for nothing — no contacts, no location, no storage, no '
          'network (unless explicitly needed for the app to function).',
      color: 0xFF6FB4FF,
    ),
    (
      title: 'Open source',
      body:
          'The code is readable. Check how it works rather than taking our word '
          'for it.',
      color: 0xFFB48CFF,
    ),
    (
      title: 'Works offline, stays small',
      body:
          'No background activity, no battery drain while you are not using it '
          '(unless being online is explicitly needed for the app to function).',
      color: 0xFF00D6B4,
    ),
  ];

  /// The studio's three chips.
  static const studioChips = ['NO ADS', 'NO TRACKING', 'OPEN SOURCE'];

  /// Footer link.
  static const linkSite = 'HONESTARCADE.APP ↗';
}
