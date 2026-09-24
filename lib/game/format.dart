// Time and the pause card's two lines, as the design formats them.

/// `m:ss`, minutes counting on past an hour: the design's `fmt(t)`.
String fmt(int seconds) =>
    '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
