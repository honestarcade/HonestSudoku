// Settings: the board theme, the running game's strike and announce modes,
// the eleven toggles in three groups, the stored-on-device note and the
// version. Every change goes through the controller at once and is saved.

import 'package:flutter/material.dart';
import 'package:honest_sudoku/game/game.dart';

import '../app_scope.dart';
import '../board/board_styles.dart';
import '../board/game_controller.dart';
import '../copy.dart';
import '../theme/board_theme.dart';
import '../theme/tokens.dart';
import '../widgets/choice_row.dart';
import '../widgets/design_button.dart';
import '../widgets/screen_frame.dart';
import '../widgets/screen_header.dart';
import '../widgets/toggle.dart';

/// The settings screen.
class SettingsScreen extends StatelessWidget {
  /// Creates the screen.
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final c = scope.controller;
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) => _build(context, c, scope.buildInfo.versionLine),
    );
  }

  Widget _build(BuildContext context, GameController c, String version) {
    final settings = c.settings;
    final game = settings.game;

    // The modes edit the running game; with none running they are also the
    // next board's, so the last setup follows.
    void setModes({StrikeMode? strike, AnnounceMode? announce}) {
      final nextGame = game.copyWith(strikeMode: strike, announce: announce);
      var next = settings.copyWith(game: nextGame);
      if (!c.hasUnfinishedGame) {
        next = next.copyWith(
          lastSetup: settings.lastSetup.copyWith(
            strikeMode: strike,
            announce: announce,
          ),
        );
      }
      c.updateSettings(next);
    }

    return ScreenFrame(
      gap: 12,
      children: [
        ScreenHeader(
          title: Copy.settings,
          keyPrefix: 'settings',
          onBack: () => Navigator.of(context).maybePop(),
        ),
        Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              panelTitle(Copy.boardTheme, size: 13),
              const SizedBox(height: 6),
              panelDesc(Copy.boardThemeNote, size: 10.5, lineHeight: 1.35),
              const SizedBox(height: 12),
              Row(
                children: [
                  for (final t in BoardTheme.all) ...[
                    if (t != BoardTheme.all.first) const SizedBox(width: 10),
                    Expanded(
                      child: _ThemeCard(
                        theme: t,
                        selected: t.key == settings.themeKey,
                        onPick: () => c.updateSettings(
                          settings.copyWith(themeKey: t.key),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
        Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              panelTitle(Copy.mistakesAllowed, size: 13),
              const SizedBox(height: 6),
              panelDesc(
                Copy.settingsMistakesDesc,
                size: 10.5,
                lineHeight: 1.35,
              ),
              const SizedBox(height: 13),
              ChoiceRow<StrikeMode>(
                fontSize: 11,
                options: [
                  for (final m in StrikeMode.values)
                    ChoiceOption(m, m.label, key: 'settings-strike-${m.name}'),
                ],
                selected: game.strikeMode,
                onSelect: (m) => setModes(strike: m),
              ),
              const SizedBox(height: 13),
              panelTitle(Copy.announceMistakes, size: 13),
              const SizedBox(height: 6),
              panelDesc(
                Copy.settingsAnnounceDesc,
                size: 10.5,
                lineHeight: 1.35,
              ),
              const SizedBox(height: 13),
              ChoiceRow<AnnounceMode>(
                fontSize: 11,
                options: [
                  for (final m in AnnounceMode.values)
                    ChoiceOption(
                      m,
                      m.label,
                      key: 'settings-announce-${m.name}',
                    ),
                ],
                selected: game.announce,
                onSelect: (m) => setModes(announce: m),
              ),
            ],
          ),
        ),
        for (final section in SettingSection.values)
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.only(left: 3),
                child: kickerText(section.title),
              ),
              for (final t in SettingToggle.values.where(
                (t) => t.section == section,
              )) ...[
                const SizedBox(height: 8),
                _ToggleRow(
                  keyName: t.key,
                  label: t.label,
                  description: t.description,
                  value: t.read(game),
                  onChanged: (v) => c.updateSettings(
                    settings.copyWith(game: t.write(game, v)),
                  ),
                ),
              ],
              if (section == SettingSection.sound)
                for (final t in SoundToggle.values) ...[
                  const SizedBox(height: 8),
                  _ToggleRow(
                    keyName: t.key,
                    label: t.label,
                    description: t.description,
                    value: t.read(settings),
                    onChanged: (v) => c.updateSettings(t.write(settings, v)),
                  ),
                ],
            ],
          ),
        Panel(
          color: HsColors.fill04,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              kickerText(Copy.storedOnDevice, size: 9),
              const SizedBox(height: 9),
              panelDesc(Copy.storedOnDeviceBody, lineHeight: 1.5),
            ],
          ),
        ),
        Text(
          version,
          key: const ValueKey('settings-version'),
          style: plexMono(
            9.5,
            scale: 1,
            color: HsColors.versionText,
            letterSpacingEm: .14,
            lineHeight: 1.6,
          ),
        ),
      ],
    );
  }
}

class _ToggleRow extends StatelessWidget {
  const _ToggleRow({
    required this.keyName,
    required this.label,
    required this.description,
    required this.value,
    required this.onChanged,
  });

  final String keyName;
  final String label;
  final String description;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: () => onChanged(!value),
    child: Panel(
      radius: 12,
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: outfit(12.5, scale: 1, weight: FontWeight.w600),
                ),
                const SizedBox(height: 5),
                panelDesc(description, size: 10.5, lineHeight: 1.35),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Toggle(
            key: ValueKey('settings-toggle-$keyName'),
            value: value,
            onChanged: onChanged,
            semanticsLabel: label,
          ),
        ],
      ),
    ),
  );
}

class _ThemeCard extends StatelessWidget {
  const _ThemeCard({
    required this.theme,
    required this.selected,
    required this.onPick,
  });

  final BoardTheme theme;
  final bool selected;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) => DesignButton(
    key: ValueKey('settings-theme-${theme.key}'),
    spec: ButtonStyleSpec(
      edge: selected ? HsColors.teal : HsColors.track,
      bg: HsColors.fill04,
      fg: selected ? HsColors.teal : HsColors.desc,
    ),
    scale: 1,
    radius: 12,
    borderWidth: 1.5,
    padding: const EdgeInsets.all(10),
    onPressed: onPick,
    child: Column(
      children: [
        Container(
          key: ValueKey('settings-preview-${theme.key}'),
          height: 54,
          padding: const EdgeInsets.all(5),
          decoration: BoxDecoration(
            color: theme.gridBg,
            borderRadius: BorderRadius.circular(7),
          ),
          child: Column(
            children: [
              for (var r = 0; r < 4; r++) ...[
                if (r > 0) const SizedBox(height: 1),
                Expanded(
                  child: Row(
                    children: [
                      for (var col = 0; col < 8; col++) ...[
                        if (col > 0) const SizedBox(width: 1),
                        Expanded(child: _cell(r * 8 + col)),
                      ],
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 9),
        Text(
          theme.label,
          style: plexMono(
            9.5,
            scale: 1,
            color: selected ? HsColors.teal : HsColors.desc,
          ),
        ),
      ],
    ),
  );

  Widget _cell(int i) {
    final v = Copy.themeSample[i];
    return Container(
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: v == 0 ? null : theme.cellBg,
        borderRadius: BorderRadius.circular(1),
      ),
      child: v == 0
          ? null
          : Text(
              '$v',
              textScaler: TextScaler.noScaling,
              style: outfit(
                7,
                scale: 1,
                weight: FontWeight.w600,
                color: i % 5 == 0 ? theme.userFg : theme.givenFg,
              ),
            ),
    );
  }
}
