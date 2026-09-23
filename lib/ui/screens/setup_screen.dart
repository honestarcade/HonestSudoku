// New puzzle: size, difficulty with its givens count, mistakes allowed,
// announce mistakes, Start, and Keep playing. The choices are remembered as
// the settings' last setup; they describe the next board only. A difficulty
// the grader cannot prove at the chosen size is greyed out.

import 'package:flutter/material.dart';
import 'package:honest_sudoku/engine/engine.dart';
import 'package:honest_sudoku/game/game.dart';

import '../app_scope.dart';
import '../board/board_styles.dart';
import '../board/game_controller.dart';
import '../copy.dart';
import '../routes.dart';
import '../theme/tokens.dart';
import '../widgets/choice_row.dart';
import '../widgets/design_button.dart';
import '../widgets/screen_frame.dart';
import '../widgets/screen_header.dart';

/// The setup meta line: `9×9 · MEDIUM · 3 STRIKES`.
String setupMeta(LastSetup s) {
  final strikes = switch (s.strikeMode) {
    StrikeMode.zen => 'ZEN',
    StrikeMode.unlimited => 'NO LIMIT',
    StrikeMode(:final limit) => '$limit STRIKES',
  };
  return '${s.shapeLabel} · ${s.difficulty.label.toUpperCase()} · $strikes';
}

/// The setup screen.
class SetupScreen extends StatelessWidget {
  /// Creates the screen.
  const SetupScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final c = AppScope.of(context).controller;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Routes.toMenu(context);
      },
      child: ListenableBuilder(
        listenable: c,
        builder: (context, _) => _build(context, c),
      ),
    );
  }

  Widget _build(BuildContext context, GameController c) {
    final setup = c.settings.lastSetup;
    final shape = setup.shape;
    void write(LastSetup next) =>
        c.updateSettings(c.settings.copyWith(lastSetup: next));

    return ScreenFrame(
      children: [
        ScreenHeader(
          title: Copy.setupTitle,
          meta: setupMeta(setup),
          keyPrefix: 'setup',
          onBack: () => Routes.toMenu(context),
        ),
        Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              panelTitle(Copy.gridSize),
              const SizedBox(height: 6),
              panelDesc(Copy.gridSizeNote),
              const SizedBox(height: 12),
              ChoiceRow<GridShape>(
                gap: 8,
                fontSize: 13,
                options: [
                  for (final s in GridShape.all)
                    ChoiceOption(
                      s,
                      s.label,
                      sub: s.sub,
                      key: 'setup-size-${s.label}',
                    ),
                ],
                selected: shape,
                onSelect: (s) {
                  final bands = supportedDifficulties(s);
                  write(
                    setup.copyWith(
                      shapeLabel: s.label,
                      difficultyKey: bands.contains(setup.difficulty)
                          ? setup.difficultyKey
                          : bands.last.key,
                    ),
                  );
                },
              ),
            ],
          ),
        ),
        Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              panelTitle(Copy.difficulty),
              const SizedBox(height: 12),
              for (final d in Difficulty.values) ...[
                if (d.index > 0) const SizedBox(height: 8),
                _DifficultyCard(
                  shape: shape,
                  difficulty: d,
                  selected: d == setup.difficulty,
                  onPick: () => write(setup.copyWith(difficultyKey: d.key)),
                ),
              ],
            ],
          ),
        ),
        Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              panelTitle(Copy.mistakesAllowed),
              const SizedBox(height: 6),
              panelDesc(Copy.setupMistakesDesc),
              const SizedBox(height: 12),
              ChoiceRow<StrikeMode>(
                options: [
                  for (final m in StrikeMode.values)
                    ChoiceOption(m, m.label, key: 'setup-strike-${m.name}'),
                ],
                selected: setup.strikeMode,
                onSelect: (m) => write(setup.copyWith(strikeMode: m)),
              ),
            ],
          ),
        ),
        Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              panelTitle(Copy.announceMistakes),
              const SizedBox(height: 6),
              panelDesc(Copy.setupAnnounceDesc),
              const SizedBox(height: 12),
              ChoiceRow<AnnounceMode>(
                options: [
                  for (final m in AnnounceMode.values)
                    ChoiceOption(m, m.label, key: 'setup-announce-${m.name}'),
                ],
                selected: setup.announce,
                onSelect: (m) => write(setup.copyWith(announce: m)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        DesignButton.variant(
          DesignButtonVariant.primary,
          key: const ValueKey('setup-start'),
          scale: 1,
          radius: 14,
          padding: const EdgeInsets.all(17),
          onPressed: () {
            c.startNew(shape, setup.difficulty);
            Routes.toLoadingForGeneration(context);
          },
          child: Text(
            Copy.startPuzzle,
            style: outfit(
              16,
              scale: 1,
              weight: FontWeight.w600,
              color: HsColors.deepNavy,
            ),
          ),
        ),
        if (c.hasUnfinishedGame)
          DesignButton(
            key: const ValueKey('setup-keep'),
            spec: const ButtonStyleSpec(
              edge: HsColors.edge16,
              bg: HsColors.fill04,
              fg: HsColors.chipFg,
            ),
            scale: 1,
            radius: 14,
            padding: const EdgeInsets.all(14),
            onPressed: () => Routes.toBoardPaused(context),
            child: Text(
              Copy.keepPlaying,
              textAlign: TextAlign.center,
              style: outfit(
                13,
                scale: 1,
                weight: FontWeight.w500,
                color: HsColors.chipFg,
              ),
            ),
          ),
      ],
    );
  }
}

class _DifficultyCard extends StatelessWidget {
  const _DifficultyCard({
    required this.shape,
    required this.difficulty,
    required this.selected,
    required this.onPick,
  });

  final GridShape shape;
  final Difficulty difficulty;
  final bool selected;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    final offered = supportedDifficulties(shape).contains(difficulty);
    final spec = selected ? selectedChoiceSpec : choiceSpec;
    final card = DesignButton(
      key: ValueKey('setup-diff-${difficulty.key}'),
      spec: spec,
      scale: 1,
      radius: 12,
      borderWidth: 1.5,
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 14),
      onPressed: offered ? onPick : null,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  difficulty.label,
                  style: outfit(
                    13.5,
                    scale: 1,
                    weight: FontWeight.w600,
                    color: spec.fg,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  difficulty.description,
                  style: outfit(
                    10.5,
                    scale: 1,
                    color: HsColors.desc,
                    lineHeight: 1.3,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text(
            offered
                ? '${targetGivens(shape, difficulty)} GIVENS'
                : Copy.notOn(shape.label),
            key: ValueKey('setup-diff-${difficulty.key}-meta'),
            style: plexMono(
              9.5,
              scale: 1,
              color: selected ? HsColors.teal : HsColors.labelDim,
              letterSpacingEm: .08,
            ),
          ),
        ],
      ),
    );
    if (offered) return card;
    return Semantics(enabled: false, child: Opacity(opacity: .4, child: card));
  }
}
