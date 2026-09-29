import 'package:honest_sudoku/game/game.dart';

/// Hands out [seeds] in order, then repeats the last one.
final class SequenceSeedSource implements SeedSource {
  SequenceSeedSource(this.seeds);

  final List<int> seeds;

  /// How many seeds have been drawn, the repeats included.
  var drawn = 0;

  @override
  int next() {
    final i = drawn < seeds.length ? drawn : seeds.length - 1;
    drawn++;
    return seeds[i];
  }
}
