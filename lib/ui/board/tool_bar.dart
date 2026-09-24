// The six tools under the pad: undo, redo, notes (AUTO and inert when
// auto-candidates are on), erase, hint and check.

import 'package:flutter/widgets.dart';
import 'package:honest_sudoku/game/game.dart';

import '../a11y/labels.dart';
import '../theme/tokens.dart';
import '../widgets/design_button.dart';
import 'board_layout.dart';
import 'board_styles.dart';

/// The tool row. Position-agnostic: the screen places it at `kToolBarY`.
class ToolBar extends StatelessWidget {
  /// Creates the row for [state].
  const ToolBar({
    required this.state,
    required this.scale,
    required this.onUndo,
    required this.onRedo,
    required this.onToggleNotes,
    required this.onErase,
    required this.onHint,
    required this.onCheck,
    super.key,
  });

  /// The game.
  final GameState state;

  /// Design points to logical pixels.
  final double scale;

  /// ↺ UNDO.
  final VoidCallback onUndo;

  /// ↻ REDO.
  final VoidCallback onRedo;

  /// ✎ NOTES; never called while it reads AUTO.
  final VoidCallback onToggleNotes;

  /// ⌫ ERASE.
  final VoidCallback onErase;

  /// ✦ HINT.
  final VoidCallback onHint;

  /// ✓ CHECK.
  final VoidCallback onCheck;

  @override
  Widget build(BuildContext context) {
    final auto = state.settings.autoNotes;
    final note = state.effectiveNoteMode;
    final tools = [
      // Undo and Redo are inert, and announced disabled, with nothing to
      // take back or forward.
      (Tool.undo, '↺', 'UNDO', state.canUndo ? onUndo : null, false, null),
      (Tool.redo, '↻', 'REDO', state.canRedo ? onRedo : null, false, null),
      (
        Tool.notes,
        '✎',
        auto ? 'AUTO' : 'NOTES',
        auto ? null : onToggleNotes,
        note,
        auto || note,
      ),
      (Tool.erase, '⌫', 'ERASE', onErase, false, null),
      (Tool.hint, '✦', 'HINT', onHint, false, null),
      (Tool.check, '✓', 'CHECK', onCheck, false, null),
    ];
    return Container(
      width: kFrameWidth * scale,
      height: kToolBarHeight * scale,
      padding: EdgeInsets.symmetric(horizontal: 14 * scale),
      alignment: Alignment.center,
      child: Row(
        children: [
          for (var i = 0; i < tools.length; i++) ...[
            if (i > 0) SizedBox(width: 7 * scale),
            Expanded(child: _tool(tools[i])),
          ],
        ],
      ),
    );
  }

  Widget _tool((Tool, String, String, VoidCallback?, bool, bool?) t) {
    final (tool, icon, label, onTap, active, toggled) = t;
    final spec = toolStyle(active: active);
    return DesignButton(
      key: ValueKey('tool-${tool.name}'),
      spec: spec,
      scale: scale,
      height: 50,
      onPressed: onTap,
      semanticsLabel: toolLabel(
        tool,
        noteMode: state.effectiveNoteMode,
        autoNotes: state.settings.autoNotes,
      ),
      semanticsToggled: toggled,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            icon,
            textScaler: TextScaler.noScaling,
            style: outfit(
              14,
              scale: scale,
              weight: FontWeight.w500,
              color: spec.fg,
            ),
          ),
          SizedBox(height: 5 * scale),
          Text(
            label,
            softWrap: false,
            textScaler: TextScaler.noScaling,
            style: plexMono(
              8,
              scale: scale,
              color: spec.fg,
              letterSpacingEm: .08,
            ),
          ),
        ],
      ),
    );
  }
}
