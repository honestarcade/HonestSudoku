// The number pad: one key per value (A–G on 16×16), in the design's columns
// per size, yellow in note mode, faded once a number is finished, and an
// erase key on 9×9.

import 'package:flutter/widgets.dart';
import 'package:honest_sudoku/game/game.dart';

import '../theme/tokens.dart';
import '../widgets/design_button.dart';
import 'board_layout.dart';
import 'board_styles.dart';

/// The pad. Position-agnostic: the screen places it at `padY`.
class NumberPad extends StatelessWidget {
  /// Creates the pad for [state].
  const NumberPad({
    required this.state,
    required this.scale,
    required this.onPlace,
    required this.onErase,
    this.semanticsLabel,
    super.key,
  });

  /// The game.
  final GameState state;

  /// Design points to logical pixels.
  final double scale;

  /// A number key was tapped.
  final ValueChanged<int> onPlace;

  /// The erase key was tapped.
  final VoidCallback onErase;

  /// A spoken label per key value (0 for erase); M5 supplies it.
  final String? Function(int value)? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    final layout = BoardLayout.of(state.shape);
    final n = state.n;
    final note = state.effectiveNoteMode;
    final keys = <Widget>[
      for (var v = 1; v <= n; v++)
        _key(
          key: ValueKey('pad-$v'),
          label: state.shape.symbolFor(v),
          fontSize: layout.padFontSize,
          spec: padKeyStyle(
            noteMode: note,
            done: state.settings.dimDone && state.countOf(v) >= n,
          ),
          onTap: () => onPlace(v),
          layout: layout,
          semantics: semanticsLabel?.call(v),
        ),
      if (n == 9)
        _key(
          key: const ValueKey('pad-erase'),
          label: '⌫',
          fontSize: 17,
          spec: eraseKeyStyle,
          onTap: onErase,
          layout: layout,
          semantics: semanticsLabel?.call(0),
        ),
    ];
    final cols = layout.padCols;
    final gap = kPadGap * scale;
    return SizedBox(
      width: kPadWidth * scale,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var r = 0; r < layout.padRows; r++) ...[
            if (r > 0) SizedBox(height: gap),
            SizedBox(
              height: layout.padKeyHeight * scale,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var c = 0; c < cols; c++) ...[
                    if (c > 0) SizedBox(width: gap),
                    Expanded(
                      child: r * cols + c < keys.length
                          ? keys[r * cols + c]
                          : const SizedBox.shrink(),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _key({
    required Key key,
    required String label,
    required double fontSize,
    required ButtonStyleSpec spec,
    required VoidCallback onTap,
    required BoardLayout layout,
    required String? semantics,
  }) => DesignButton(
    key: key,
    spec: spec,
    scale: scale,
    radius: 12,
    onPressed: onTap,
    semanticsLabel: semantics,
    child: Text(
      label,
      softWrap: false,
      textScaler: TextScaler.noScaling,
      style: outfit(
        fontSize,
        scale: scale,
        weight: FontWeight.w600,
        color: spec.fg,
      ),
    ),
  );
}
