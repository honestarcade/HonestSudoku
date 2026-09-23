// The banner under the grid: a tag, a sentence, and how to colour it.

import 'package:honest_sudoku/engine/engine.dart';

/// A notice banner's content.
final class Notice {
  /// Creates a notice.
  const Notice(this.kind, this.tag, this.body);

  /// Hint (yellow), ok (teal) or error (red).
  final BannerKind kind;

  /// The kicker, e.g. `MISTAKE`.
  final String tag;

  /// The sentence.
  final String body;

  @override
  bool operator ==(Object other) =>
      other is Notice &&
      other.kind == kind &&
      other.tag == tag &&
      other.body == body;

  @override
  int get hashCode => Object.hash(kind, tag, body);

  @override
  String toString() => 'Notice(${kind.name}, $tag)';
}
