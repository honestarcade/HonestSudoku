import 'package:honest_sudoku/game/game.dart';

/// Hands out [seeds] in order, then repeats the last one.
final class SequenceSeedSource implements SeedSource {
  SequenceSeedSource(this.seeds);

  final List<int> seeds;
  var _i = 0;

  /// How many seeds have been drawn.
  int get drawn => _i;

  @override
  int next() => seeds[_i < seeds.length ? _i++ : seeds.length - 1];
}
