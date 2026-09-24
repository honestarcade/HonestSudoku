@Tags(['guard'])
library;

// Every text colour on the board screen and its cards reaches 4.5:1 on each
// surface it is drawn on, in both themes (#52). Flutter's pixel guideline
// (contrast_test.dart) only samples text whose semantics label is its own
// string, and the board's digits, keys, chips and card titles speak their
// own labels (#51); this is the check that covers them.
//
// Surfaces: translucent fills composited over the grid background, the
// card's two gradient stops, or the screen gradient's two stops.

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:honest_sudoku/ui/theme/board_theme.dart';
import 'package:honest_sudoku/ui/theme/contrast.dart';
import 'package:honest_sudoku/ui/theme/tokens.dart';

const _gradientTop = Color(0xFF0A3A80);
const _gradientLow = Color(0xFF031634);
const _clear = Color(0x00000000);

List<Color> _onGradient(Color fill) => [
  composite(fill, _gradientTop),
  composite(fill, _gradientLow),
];

List<Color> _onCard(Color fill) => [
  composite(fill, HsColors.cardNavy),
  composite(fill, HsColors.deepNavy),
];

List<Color> _onGrid(BoardTheme t, List<Color> fills) => [
  for (final f in fills) composite(f, t.gridBg),
];

/// (where, text colour, surfaces).
List<(String, Color, List<Color>)> _pairs() => [
  for (final t in BoardTheme.all) ...[
    (
      '${t.key}: given digits',
      t.givenFg,
      _onGrid(t, [t.cellBg, t.peerBg, t.sameBg, t.selBg]),
    ),
    (
      '${t.key}: the player\'s digits',
      t.userFg,
      _onGrid(t, [t.cellBg, t.peerBg, t.sameBg, t.selBg]),
    ),
    ('${t.key}: wrong digits', t.wrongFg, _onGrid(t, [t.wrongBg, t.selBg])),
    (
      '${t.key}: pencil marks',
      t.noteFg,
      _onGrid(t, [t.cellBg, t.peerBg, t.selBg]),
    ),
    (
      '${t.key}: the hinted cell\'s marks',
      t.hintNoteFg,
      _onGrid(t, [t.cellBg, t.peerBg, t.selBg]),
    ),
  ],
  ('timer chip', HsColors.chipFg, _onGradient(HsColors.fill07)),
  ('strike chip, counting', HsColors.wrongRed, _onGradient(HsColors.strikeBg)),
  ('ZEN chip', HsColors.zenChipFg, _onGradient(HsColors.zenBg)),
  ('pause button', HsColors.white, _onGradient(HsColors.fill06)),
  ('pad digits', HsColors.textBright, _onGradient(HsColors.fill07)),
  (
    'pad digits, note mode',
    HsColors.hintYellow,
    _onGradient(HsColors.noteKeyBg),
  ),
  ('pad erase key', HsColors.chipFg, _onGradient(HsColors.fill04)),
  ('tool labels', HsColors.toolFg, _onGradient(HsColors.fill06)),
  (
    'notes tool, active',
    HsColors.hintYellow,
    _onGradient(HsColors.toolActiveBg),
  ),
  for (final (kind, bg, kicker) in [
    ('error', HsColors.noticeErrorBg, HsColors.wrongRed),
    ('ok', HsColors.noticeOkBg, HsColors.teal),
    ('hint', HsColors.noticeHintBg, HsColors.hintYellow),
  ]) ...[
    ('$kind notice body', HsColors.bodyBlue, _onGradient(bg)),
    ('$kind notice kicker', kicker, _onGradient(bg)),
  ],
  (
    'loading phase label',
    HsColors.labelDim,
    [_gradientTop, _gradientLow, ..._onCard(_clear)],
  ),
  ('card titles and tile values', HsColors.white, _onCard(_clear)),
  ('card tile values', HsColors.white, _onCard(HsColors.fill06)),
  ('pause meta, ghost button', HsColors.muted, _onCard(_clear)),
  ('tile labels', HsColors.muted, _onCard(HsColors.fill06)),
  (
    'card kicker',
    HsColors.cardKicker,
    [..._onCard(_clear), ..._onCard(HsColors.fill06)],
  ),
  (
    'card body',
    HsColors.bodySoft,
    [..._onCard(_clear), ..._onCard(HsColors.fill06)],
  ),
  ('secondary buttons', HsColors.white, _onCard(HsColors.fill05)),
  ('soft buttons', HsColors.chipFg, _onCard(HsColors.fill04)),
  ('primary buttons', HsColors.deepNavy, [HsColors.teal]),
  ('win kicker', HsColors.teal, _onCard(_clear)),
  ('out-of-strikes kicker', HsColors.wrongRed, _onCard(_clear)),
];

/// (token, design value, value now, surfaces it was nudged against).
List<(String, Color, Color, List<Color>)> _nudges() {
  const n = BoardTheme.navy;
  const p = BoardTheme.paper;
  return [
    (
      'paperUserFg',
      const Color(0xFF0076F1),
      HsColors.paperUserFg,
      _onGrid(p, [p.cellBg, p.peerBg, p.sameBg, p.selBg]),
    ),
    (
      'paperWrongFg',
      const Color(0xFFC6483D),
      HsColors.paperWrongFg,
      _onGrid(p, [p.wrongBg, p.selBg]),
    ),
    (
      'paperNoteFg',
      const Color(0xFF6E93C4),
      HsColors.paperNoteFg,
      _onGrid(p, [p.cellBg, p.peerBg, p.selBg]),
    ),
    (
      'paperHintNote',
      const Color(0xFFFFC94A),
      HsColors.paperHintNote,
      _onGrid(p, [p.cellBg, p.peerBg, p.selBg]),
    ),
    (
      'navyNoteFg',
      const Color(0xFF7FA6D8),
      HsColors.navyNoteFg,
      _onGrid(n, [n.cellBg, n.peerBg, n.selBg]),
    ),
    (
      'navyWrongFg',
      const Color(0xFFFF8C7E),
      HsColors.navyWrongFg,
      _onGrid(n, [n.wrongBg, n.selBg]),
    ),
    (
      'wrongRed',
      const Color(0xFFFF8C7E),
      HsColors.wrongRed,
      [
        ..._onGradient(HsColors.strikeBg),
        ..._onGradient(HsColors.noticeErrorBg),
        ..._onCard(_clear),
      ],
    ),
    (
      'zenChipFg',
      HsColors.teal,
      HsColors.zenChipFg,
      _onGradient(HsColors.zenBg),
    ),
    (
      'labelDim',
      const Color(0xFF5C7FB0),
      HsColors.labelDim,
      [_gradientTop, _gradientLow, ..._onCard(_clear)],
    ),
    (
      'cardKicker',
      const Color(0xFF6E93C4),
      HsColors.cardKicker,
      [
        ..._onCard(_clear),
        ..._onCard(HsColors.fill06),
        _gradientTop,
        _gradientLow,
      ],
    ),
    (
      'muted',
      const Color(0xFF7FA6D8),
      HsColors.muted,
      [
        ..._onCard(_clear),
        ..._onCard(HsColors.fill06),
        _gradientTop,
        _gradientLow,
      ],
    ),
  ];
}

String _hex(Color c) =>
    '#${c.toARGB32().toRadixString(16).substring(2).toUpperCase()}';

void main() {
  test('the arithmetic: luminance, ratio, compositing, the nudge', () {
    expect(
      contrastRatio(const Color(0xFF000000), HsColors.white),
      closeTo(21, 1e-9),
    );
    expect(contrastRatio(HsColors.white, HsColors.white), 1);
    // WCAG's worked value for #777 on white.
    expect(
      contrastRatio(const Color(0xFF777777), HsColors.white),
      closeTo(4.48, 0.01),
    );
    expect(
      composite(const Color.fromRGBO(0, 0, 0, .5), HsColors.white).r,
      closeTo(.5, 1e-9),
    );
    final n = nudge(const Color(0xFF777777), [HsColors.white]);
    expect(n.steps, greaterThan(0));
    expect(contrastRatio(n.color, HsColors.white), greaterThanOrEqualTo(4.5));
    expect(nudge(HsColors.white, [HsColors.cardNavy]).steps, 0);
  });

  test('contrast: every board text colour reaches 4.5:1 on its surfaces', () {
    final failures = [
      for (final (where, fg, surfaces) in _pairs())
        for (final s in surfaces)
          if (contrastRatio(fg, s) < kTextContrast)
            '$where: ${_hex(fg)} on ${_hex(s)} is '
                '${contrastRatio(fg, s).toStringAsFixed(2)}:1',
    ];
    expect(
      failures,
      isEmpty,
      reason:
          'contrast: ${failures.length} pair(s) under '
          '$kTextContrast:1\n  ${failures.join('\n  ')}',
    );
  });

  test('contrast-nudges: each nudged token is its design value nudged', () {
    for (final (token, design, now, surfaces) in _nudges()) {
      final derived = nudge(design, surfaces).color;
      expect(
        _hex(now),
        _hex(derived),
        reason:
            'contrast-nudges: $token is ${_hex(now)}, but nudging the '
            'design\'s ${_hex(design)} gives ${_hex(derived)}',
      );
    }
  });

  test('the brand swatches are the design\'s', () {
    expect(
      [
        HsColors.teal,
        HsColors.blue,
        HsColors.violet,
        HsColors.navy,
        HsColors.red,
        HsColors.paper,
      ].map(_hex),
      ['#00D6B4', '#0076F1', '#8448FC', '#05285F', '#C6483D', '#F7F5EF'],
    );
  });
}
