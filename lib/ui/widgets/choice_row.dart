// A row of equal choices, one selected: the setup and settings screens'
// strike and announce rows and the size cards.

import 'package:flutter/widgets.dart';

import '../a11y/speak.dart';
import '../board/board_styles.dart';
import '../theme/tokens.dart';
import 'design_button.dart';

/// One choice.
final class ChoiceOption<T> {
  /// Creates a choice.
  const ChoiceOption(this.value, this.label, {this.sub, this.key});

  /// What choosing it selects.
  final T value;

  /// Its label.
  final String label;

  /// A mono line under the label (the size cards).
  final String? sub;

  /// Its widget key.
  final String? key;
}

/// A selected choice's colours.
const ButtonStyleSpec selectedChoiceSpec = ButtonStyleSpec(
  edge: HsColors.teal,
  bg: HsColors.tealFill14,
  fg: HsColors.teal,
);

/// An unselected choice's colours.
const ButtonStyleSpec choiceSpec = ButtonStyleSpec(
  edge: HsColors.edge14,
  bg: HsColors.fill04,
  fg: HsColors.toolFg,
);

/// A row of choices.
class ChoiceRow<T> extends StatelessWidget {
  /// Creates the row.
  const ChoiceRow({
    required this.options,
    required this.selected,
    required this.onSelect,
    this.fontSize = 11.5,
    this.gap = 7,
    super.key,
  });

  /// The choices.
  final List<ChoiceOption<T>> options;

  /// The selected value.
  final T selected;

  /// A choice was tapped.
  final ValueChanged<T> onSelect;

  /// The labels' size.
  final double fontSize;

  /// Space between choices.
  final double gap;

  @override
  Widget build(BuildContext context) => IntrinsicHeight(
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < options.length; i++) ...[
          if (i > 0) SizedBox(width: gap),
          Expanded(child: _choice(options[i])),
        ],
      ],
    ),
  );

  Widget _choice(ChoiceOption<T> o) {
    final on = o.value == selected;
    final spec = on ? selectedChoiceSpec : choiceSpec;
    return DesignButton(
      key: o.key == null ? null : ValueKey<String>(o.key!),
      semanticsSelected: on,
      semanticsLabel: o.sub == null
          ? speak(o.label)
          : '${speak(o.label)}, ${speak(o.sub!)}',
      spec: spec,
      scale: 1,
      radius: 11,
      borderWidth: 1.5,
      padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 4),
      onPressed: () => onSelect(o.value),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            o.label,
            textAlign: TextAlign.center,
            style: outfit(
              fontSize,
              scale: 1,
              weight: FontWeight.w600,
              color: spec.fg,
            ),
          ),
          if (o.sub != null) ...[
            const SizedBox(height: 5),
            Text(
              o.sub!,
              textAlign: TextAlign.center,
              style: plexMono(
                8.5,
                scale: 1,
                color: HsColors.cardKicker,
                letterSpacingEm: .08,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
