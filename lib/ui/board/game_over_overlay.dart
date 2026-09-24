// The win and out-of-strikes cards, rising in as the design's `hs-rise`
// does: 8 points up and faded in over 350 ms, ease-out. Under the phone's
// remove-animations setting the card simply appears.

import 'package:flutter/widgets.dart';
import 'package:honest_sudoku/game/game.dart';

import '../strings.dart';
import '../theme/tokens.dart';
import 'overlay_parts.dart';

/// The won or lost card over its scrim.
class GameOverOverlay extends StatefulWidget {
  /// Creates the card for a finished [state].
  const GameOverOverlay({
    required this.state,
    required this.stats,
    required this.scale,
    required this.onNewDeal,
    required this.onChangeSetup,
    required this.onMainMenu,
    super.key,
  });

  /// The finished game.
  final GameState state;

  /// Where the streak comes from.
  final StatsSource stats;

  /// Design points to logical pixels.
  final double scale;

  /// Next puzzle / New puzzle.
  final VoidCallback onNewDeal;

  /// Change size or difficulty.
  final VoidCallback onChangeSetup;

  /// Main menu.
  final VoidCallback onMainMenu;

  @override
  State<GameOverOverlay> createState() => _GameOverOverlayState();
}

class _GameOverOverlayState extends State<GameOverOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _rise = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 350),
  );
  late final CurvedAnimation _curve = CurvedAnimation(
    parent: _rise,
    curve: Curves.easeOut,
  );
  late final int _streak;

  @override
  void initState() {
    super.initState();
    // Read once, when the card mounts.
    _streak = widget.stats.currentStreak(
      shape: widget.state.shape,
      difficulty: widget.state.difficulty,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      _rise.value = 1;
    } else if (!_rise.isAnimating && _rise.value == 0) {
      _rise.forward();
    }
  }

  @override
  void dispose() {
    _curve.dispose();
    _rise.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final s = widget.scale;
    final won = state.won;
    assert(
      won || state.settings.strikeMode.limit != null,
      'a lost game always has a strike limit',
    );
    final zen = state.settings.strikeMode == StrikeMode.zen;
    final tiles = won
        ? [
            ('time', UiStrings.time, fmt(state.elapsedSeconds)),
            ('entries', UiStrings.entries, '${state.moves}'),
            ('mistakes', UiStrings.mistakes, zen ? '—' : '${state.mistakes}'),
            ('streak', UiStrings.streak, '$_streak'),
          ]
        : [
            ('time', UiStrings.time, fmt(state.elapsedSeconds)),
            (
              'filled',
              UiStrings.filled,
              '${state.filledCount}/${state.shape.cellCount}',
            ),
            ('mistakes', UiStrings.mistakes, '${state.mistakes}'),
            ('difficulty', UiStrings.difficulty, state.difficulty.label),
          ];
    final kicker = won ? HsColors.teal : HsColors.wrongRed;
    final card = Container(
      padding: EdgeInsets.all(24 * s),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [HsColors.cardNavy, HsColors.deepNavy],
          // CSS 170deg: nearly straight down.
          transform: GradientRotation(80 * 3.141592653589793 / 180),
        ),
        borderRadius: BorderRadius.circular(20 * s),
        border: Border.all(color: won ? HsColors.wonRing : HsColors.lostRing),
        boxShadow: cardShadow(s),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            won ? UiStrings.wonTag : UiStrings.lostTag,
            textScaler: TextScaler.noScaling,
            style: plexMono(10, scale: s, color: kicker, letterSpacingEm: .2),
          ),
          SizedBox(height: 11 * s),
          Text(
            won ? UiStrings.wonTitle : UiStrings.lostTitle,
            textScaler: TextScaler.noScaling,
            style: outfit(
              26,
              scale: s,
              weight: FontWeight.w700,
              letterSpacingEm: -.02,
              lineHeight: 1.1,
            ),
          ),
          SizedBox(height: 10 * s),
          Text(
            won
                ? UiStrings.wonBody(state.shape.label, state.difficulty.label)
                : UiStrings.lostBody(state.settings.strikeMode.limit ?? 0),
            textScaler: TextScaler.noScaling,
            style: outfit(
              12.5,
              scale: s,
              color: HsColors.bodySoft,
              lineHeight: 1.5,
            ),
          ),
          SizedBox(height: 18 * s),
          for (var r = 0; r < 2; r++) ...[
            if (r > 0) SizedBox(height: 9 * s),
            Row(
              children: [
                for (var c = 0; c < 2; c++) ...[
                  if (c > 0) SizedBox(width: 9 * s),
                  Expanded(
                    child: StatTile(
                      name: tiles[r * 2 + c].$1,
                      label: tiles[r * 2 + c].$2,
                      value: tiles[r * 2 + c].$3,
                      scale: s,
                    ),
                  ),
                ],
              ],
            ),
          ],
          SizedBox(height: 18 * s),
          cardButton(
            label: won ? UiStrings.nextPuzzle : UiStrings.newPuzzle,
            name: 'new-deal',
            onPressed: widget.onNewDeal,
            spec: primarySpec,
            scale: s,
            padding: 15,
            fontSize: 15,
            weight: FontWeight.w600,
          ),
          SizedBox(height: 9 * s),
          cardButton(
            label: UiStrings.changeSetup,
            name: 'change-setup',
            onPressed: widget.onChangeSetup,
            spec: changeSetupSpec,
            scale: s,
            padding: 13,
            fontSize: 13.5,
          ),
          SizedBox(height: 9 * s),
          cardButton(
            label: UiStrings.mainMenu,
            name: 'main-menu',
            onPressed: widget.onMainMenu,
            spec: ghostSpec,
            scale: s,
            padding: 12,
            fontSize: 13,
          ),
        ],
      ),
    );
    return OverlayFrame(
      key: const ValueKey('overlay-over'),
      scrim: HsColors.overScrim,
      scale: s,
      card: AnimatedBuilder(
        animation: _curve,
        builder: (context, child) => Opacity(
          opacity: _curve.value,
          child: Transform.translate(
            offset: Offset(0, 8 * s * (1 - _curve.value)),
            child: child,
          ),
        ),
        child: card,
      ),
    );
  }
}
