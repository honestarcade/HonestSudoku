// Visible text turned into what a screen reader should say (#56): `×` is
// "by", a `·` separator is a comma, `m:ss` is a duration in words, an em dash
// standing for "nothing yet" is said so, and text the design sets in
// capitals for looks is spoken in sentence case, so TalkBack does not spell
// it out.

import 'labels.dart';

/// Names that keep their capitals in sentence case.
const _names = ['Honest Arcade', 'Honest Sudoku', 'GitHub'];

/// [visible] as spoken.
String speak(String visible) {
  if (visible.trim() == '—') return 'none yet';
  final segments = visible
      .replaceAll(RegExp(r'\s*[›↗]\s*$'), '')
      .replaceAll('✕', '')
      .split(RegExp(r'\s*(?:·|\n)\s*'))
      .where((s) => s.trim().isNotEmpty);
  return segments.map(_segment).join(', ').trim();
}

String _segment(String raw) {
  var s = raw.trim();
  // A run of capitals (the design's CSS uppercase) reads as a sentence.
  if (s.contains(RegExp('[A-Z]')) && s == s.toUpperCase()) {
    s = sentenceCase(s);
    for (final name in _names) {
      s = s.replaceAll(RegExp(name, caseSensitive: false), name);
    }
  }
  return s
      .replaceAllMapped(RegExp(r'(\d+)×(\d+)'), (m) => '${m[1]} by ${m[2]}')
      .replaceAllMapped(
        RegExp(r'\b(\d+):(\d\d)(?::(\d\d))?\b'),
        (m) => durationWords(
          m[3] == null
              ? int.parse(m[1]!) * 60 + int.parse(m[2]!)
              : int.parse(m[1]!) * 3600 +
                    int.parse(m[2]!) * 60 +
                    int.parse(m[3]!),
        ),
      )
      .replaceAllMapped(RegExp(r'(^|\s)—(?=\s|$)'), (m) => '${m[1]}none');
}
