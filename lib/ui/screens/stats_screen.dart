// Statistics: a tab per difficulty, six cards, the by-size breakdown with
// bars, and Reset behind the design's confirmation. Every value comes from
// the statistics model's own getters.

import 'package:flutter/material.dart';
import 'package:honest_sudoku/engine/engine.dart';
import 'package:honest_sudoku/game/game.dart';

import '../app_scope.dart';
import '../board/board_styles.dart';
import '../board/game_controller.dart';
import '../copy.dart';
import '../routes.dart';
import '../theme/tokens.dart';
import '../widgets/design_button.dart';
import '../widgets/screen_frame.dart';
import '../widgets/screen_header.dart';

/// Each size's bar colour, as the design's breakdown draws them.
Color sizeColor(GridShape s) => switch (s.n) {
  4 => HsColors.teal,
  6 => HsColors.blue,
  9 => HsColors.violet,
  _ => HsColors.hintYellow,
};

/// The statistics screen.
class StatsScreen extends StatefulWidget {
  /// Creates the screen.
  const StatsScreen({super.key});

  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> {
  var _confirming = false;

  @override
  Widget build(BuildContext context) {
    final c = AppScope.of(context).controller;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_confirming) {
          setState(() => _confirming = false);
        } else {
          Routes.toMenu(context);
        }
      },
      child: ListenableBuilder(
        listenable: c,
        builder: (context, _) => _build(context, c),
      ),
    );
  }

  Widget _build(BuildContext context, GameController c) {
    final d = c.statsTab;
    final stats = c.book.forDifficulty(d);
    final empty = stats.isEmpty;
    String dash(Object v) => empty ? '—' : '$v';
    final cards = [
      (
        'solved',
        'SOLVED',
        dash(stats.solved),
        '${dash(stats.started)} started',
        false,
      ),
      (
        'rate',
        'SOLVE RATE',
        empty ? '—' : '${stats.solveRatePct}%',
        'Finished without giving up',
        true,
      ),
      ('best', 'BEST TIME', stats.bestText, 'Fastest solve', false),
      ('average', 'AVERAGE', stats.averageText, 'Across solved puzzles', false),
      (
        'streak',
        'CURRENT STREAK',
        dash(stats.streak),
        'Solves in a row',
        false,
      ),
      (
        'time',
        'TIME PLAYED',
        empty ? '—' : stats.timePlayedText,
        'At this difficulty',
        false,
      ),
    ];
    return ScreenFrame(
      overlay: _confirming ? _confirmCard(c) : null,
      children: [
        ScreenHeader(
          title: Copy.statistics,
          keyPrefix: 'stats',
          onBack: () => Routes.toMenu(context),
        ),
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: HsColors.fill05,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              for (final t in Difficulty.values) ...[
                if (t.index > 0) const SizedBox(width: 5),
                Expanded(child: _tab(c, t, t == d)),
              ],
            ],
          ),
        ),
        for (var r = 0; r < 3; r++)
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var col = 0; col < 2; col++) ...[
                  if (col > 0) const SizedBox(width: 9),
                  Expanded(child: _card(cards[r * 2 + col])),
                ],
              ],
            ),
          ),
        Panel(
          radius: 13,
          padding: const EdgeInsets.all(15),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              kickerText(Copy.byGridSize),
              for (final row in c.book.breakdown(d)) ...[
                const SizedBox(height: 10),
                _row(row),
              ],
            ],
          ),
        ),
        DesignButton(
          key: const ValueKey('stats-reset'),
          spec: const ButtonStyleSpec(
            edge: HsColors.dangerEdge,
            bg: HsColors.dangerFill,
            fg: HsColors.wrongRed,
          ),
          scale: 1,
          radius: 13,
          padding: const EdgeInsets.all(14),
          onPressed: () => setState(() => _confirming = true),
          child: Text(
            Copy.resetStatistics,
            style: outfit(
              13,
              scale: 1,
              weight: FontWeight.w600,
              color: HsColors.wrongRed,
            ),
          ),
        ),
      ],
    );
  }

  Widget _tab(GameController c, Difficulty t, bool active) => Semantics(
    selected: active,
    child: DesignButton(
      key: ValueKey('stats-tab-${t.key}'),
      spec: ButtonStyleSpec(
        edge: const Color(0x00000000),
        bg: active ? HsColors.teal : const Color(0x00000000),
        fg: active ? HsColors.deepNavy : HsColors.chipFg,
      ),
      scale: 1,
      radius: 9,
      padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 2),
      onPressed: () => c.statsTab = t,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          t.label,
          style: outfit(
            10.5,
            scale: 1,
            weight: FontWeight.w600,
            color: active ? HsColors.deepNavy : HsColors.chipFg,
          ),
        ),
      ),
    ),
  );

  Widget _card((String, String, String, String, bool) card) {
    final (name, k, v, sub, teal) = card;
    return Container(
      key: ValueKey('stats-card-$name'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: teal ? HsColors.noticeOkBg : HsColors.fill05,
        borderRadius: BorderRadius.circular(13),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            k,
            style: plexMono(
              9,
              scale: 1,
              color: HsColors.muted,
              letterSpacingEm: .14,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            v,
            style: outfit(
              21,
              scale: 1,
              weight: FontWeight.w600,
              color: teal ? HsColors.teal : HsColors.white,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            sub,
            style: outfit(
              10.5,
              scale: 1,
              color: HsColors.desc,
              lineHeight: 1.3,
            ),
          ),
        ],
      ),
    );
  }

  Widget _row(BreakdownRow row) => Semantics(
    value: '${row.pct}%',
    child: Column(
      key: ValueKey('stats-row-${row.shape.label}'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                row.shape.label,
                style: outfit(
                  11.5,
                  scale: 1,
                  weight: FontWeight.w500,
                  color: HsColors.toolFg,
                ),
              ),
            ),
            Text(
              row.text,
              style: plexMono(11.5, scale: 1, color: HsColors.chipFg),
            ),
          ],
        ),
        const SizedBox(height: 7),
        Container(
          height: 6,
          decoration: BoxDecoration(
            color: HsColors.barTrack,
            borderRadius: BorderRadius.circular(3),
          ),
          alignment: Alignment.centerLeft,
          child: row.pct == 0
              ? null
              : FractionallySizedBox(
                  widthFactor: row.pct / 100,
                  child: Container(
                    decoration: BoxDecoration(
                      color: sizeColor(row.shape),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
        ),
      ],
    ),
  );

  Widget _confirmCard(GameController c) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: () {},
    child: ColoredBox(
      color: HsColors.confirmScrim,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 430),
          child: Padding(
            padding: const EdgeInsets.all(26),
            child: Container(
              key: const ValueKey('stats-confirm-card'),
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: HsColors.cardNavy,
                borderRadius: BorderRadius.circular(18),
                boxShadow: const [
                  BoxShadow(
                    color: Color.fromRGBO(0, 0, 0, .5),
                    offset: Offset(0, 20),
                    blurRadius: 50,
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    Copy.resetTitle,
                    style: outfit(17, scale: 1, weight: FontWeight.w600),
                  ),
                  const SizedBox(height: 11),
                  Text(
                    Copy.resetBody,
                    style: outfit(
                      12.5,
                      scale: 1,
                      color: HsColors.bodySoft,
                      lineHeight: 1.55,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Expanded(
                        child: DesignButton(
                          key: const ValueKey('stats-cancel'),
                          spec: const ButtonStyleSpec(
                            edge: HsColors.edge20,
                            bg: HsColors.fill06,
                            fg: HsColors.white,
                          ),
                          scale: 1,
                          radius: 12,
                          padding: const EdgeInsets.all(13),
                          onPressed: () => setState(() => _confirming = false),
                          child: Text(
                            Copy.cancel,
                            style: outfit(
                              13,
                              scale: 1,
                              weight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 9),
                      Expanded(
                        child: DesignButton(
                          key: const ValueKey('stats-confirm'),
                          spec: const ButtonStyleSpec(
                            edge: Color(0x00000000),
                            bg: HsColors.danger,
                            fg: HsColors.white,
                          ),
                          scale: 1,
                          radius: 12,
                          padding: const EdgeInsets.all(13),
                          onPressed: () async {
                            await c.resetStats();
                            if (mounted) setState(() => _confirming = false);
                          },
                          child: Text(
                            Copy.reset,
                            style: outfit(
                              13,
                              scale: 1,
                              weight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
