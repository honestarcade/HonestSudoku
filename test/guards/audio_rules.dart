// The audio-assets rules (#49), as pure functions over file names, bytes and
// the licence record's text.
library;

import '../helpers/board_hash.dart';

/// One refusal, naming the file.
typedef Offender = ({String path, String message});

/// The four clips the game plays.
const List<String> kCanonicalClips = ['place', 'mistake', 'solve', 'lose'];

/// The one file tolerated beside the clips.
const String kLicenceRecord = 'LICENSES.md';

/// The longest a clip may run.
const Duration kMaxClip = Duration(seconds: 2);

/// The largest a clip may be.
const int kMaxClipBytes = 250 * 1024;

/// What a clip must be: RIFF/WAVE PCM, 16-bit, 44.1 kHz, mono, no longer
/// than [kMaxClip], no larger than [kMaxClipBytes].
List<String> wavProblems(List<int> bytes) {
  final out = <String>[];
  if (bytes.length > kMaxClipBytes) {
    out.add('${bytes.length} bytes, over $kMaxClipBytes');
  }
  String tag(int at) => at + 4 <= bytes.length
      ? String.fromCharCodes(bytes.sublist(at, at + 4))
      : '';
  int u16(int at) => bytes[at] | bytes[at + 1] << 8;
  int u32(int at) => u16(at) | u16(at + 2) << 16;
  if (tag(0) != 'RIFF' || tag(8) != 'WAVE') {
    return [...out, 'not a RIFF/WAVE file'];
  }
  int? format, channels, rate, bits, dataBytes;
  var at = 12;
  while (at + 8 <= bytes.length) {
    final id = tag(at);
    final size = u32(at + 4);
    if (id == 'fmt ' && at + 24 <= bytes.length) {
      format = u16(at + 8);
      channels = u16(at + 10);
      rate = u32(at + 12);
      bits = u16(at + 22);
    } else if (id == 'data') {
      dataBytes = size;
    }
    at += 8 + size + size % 2;
  }
  if (format == null || dataBytes == null) {
    return [...out, 'no fmt or data chunk'];
  }
  if (format != 1) out.add('format $format, not PCM');
  if (bits != 16) out.add('$bits-bit, not 16-bit');
  if (rate != 44100) out.add('$rate Hz, not 44100 Hz');
  if (channels != 1) out.add('$channels channels, not mono');
  if (channels! > 0 && bits! > 0 && rate! > 0) {
    final micros = dataBytes * 1000000 ~/ (channels * bits ~/ 8 * rate);
    if (micros > kMaxClip.inMicroseconds) {
      out.add('${micros / 1000000} s long, over ${kMaxClip.inSeconds} s');
    }
  }
  return out;
}

/// The Licensed table's clips, each with a source and a licence: rows of the
/// first markdown table under `## Licensed` whose three cells are non-empty.
Set<String> licensedClips(String licences) {
  final section = RegExp(
    r'^## Licensed\s*$(.*?)(?=^## |\Z)',
    multiLine: true,
    dotAll: true,
  ).firstMatch(licences);
  if (section == null) return const {};
  final out = <String>{};
  var inTable = false;
  for (final line in section[1]!.split('\n')) {
    final cells = line.trim();
    if (!cells.startsWith('|')) {
      if (inTable) break; // only the first table counts
      continue;
    }
    inTable = true;
    final parts = cells
        .substring(1, cells.length - (cells.endsWith('|') ? 1 : 0))
        .split('|')
        .map((c) => c.trim())
        .toList();
    if (parts.length != 3 || parts.any((c) => c.isEmpty)) continue;
    final name = parts[0].replaceAll('`', '');
    if (name == 'File' || name.startsWith('---')) continue;
    out.add(name);
  }
  return out;
}

/// The Placeholders table: file → recorded FNV-1a digest.
Map<String, String> placeholderDigests(String licences) => {
  for (final m in RegExp(
    r'^\| `(placeholder-[^`]+)` \| `([0-9a-f]{16})` \|',
    multiLine: true,
  ).allMatches(licences))
    m[1]!: m[2]!,
};

/// Every rule over the directory's [files] (name → bytes) and [licences].
List<Offender> audioOffenders(Map<String, List<int>> files, String licences) {
  final out = <Offender>[];
  final licensed = licensedClips(licences);
  final digests = placeholderDigests(licences);
  final canonical = {for (final c in kCanonicalClips) '$c.wav'};
  final placeholders = {for (final c in kCanonicalClips) 'placeholder-$c.wav'};

  if (!files.containsKey(kLicenceRecord)) {
    out.add((path: kLicenceRecord, message: 'the licence record is missing'));
  }
  for (final MapEntry(key: name, value: bytes) in files.entries) {
    if (name == kLicenceRecord) continue;
    if (canonical.contains(name)) {
      if (!licensed.contains(name)) {
        out.add((
          path: name,
          message:
              'a real clip with no source and licence in the Licensed '
              'table',
        ));
      }
    } else if (placeholders.contains(name)) {
      final want = digests[name];
      if (want == null) {
        out.add((path: name, message: 'a placeholder with no digest row'));
      } else if (fnv1a64Of(bytes) != want) {
        out.add((
          path: name,
          message: 'its FNV-1a ${fnv1a64Of(bytes)} is not the recorded $want',
        ));
      }
    } else {
      out.add((
        path: name,
        message: 'neither a canonical clip nor a placeholder for one',
      ));
      continue;
    }
    for (final problem in wavProblems(bytes)) {
      out.add((path: name, message: problem));
    }
  }
  for (final c in kCanonicalClips) {
    final real = files.containsKey('$c.wav');
    final placeholder = files.containsKey('placeholder-$c.wav');
    if (real == placeholder) {
      out.add((
        path: '$c.wav',
        message: real
            ? 'both the clip and its placeholder are present'
            : 'neither the clip nor its placeholder is present',
      ));
    }
  }
  for (final name in licensed) {
    if (!files.containsKey(name)) {
      out.add((path: name, message: 'licensed but absent'));
    }
  }
  for (final name in digests.keys) {
    if (!files.containsKey(name)) {
      out.add((path: name, message: 'a digest row with no file'));
    }
  }
  return out;
}
