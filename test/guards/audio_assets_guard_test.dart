@Tags(['guard'])
library;

// Every sound the app ships is either a synthesised placeholder whose digest
// is recorded, or a real clip with its source and licence recorded; one of
// the two per clip, each a short 44.1 kHz mono 16-bit WAV (#49).

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import '../helpers/board_hash.dart';
import 'audio_rules.dart';
import 'repo_files.dart';

String _describe(List<Offender> offenders) =>
    'audio-assets: ${offenders.length} offender(s)\n'
    '${offenders.map((o) => '  assets/audio/${o.path}: ${o.message}').join('\n')}';

/// A WAV of [seconds] of silence.
List<int> _wav(
  double seconds, {
  int rate = 44100,
  int channels = 1,
  int bits = 16,
  int format = 1,
}) {
  final data = (seconds * rate).round() * channels * bits ~/ 8;
  final b = ByteData(44 + data);
  void tag(int at, String s) {
    for (var i = 0; i < 4; i++) {
      b.setUint8(at + i, s.codeUnitAt(i));
    }
  }

  tag(0, 'RIFF');
  b.setUint32(4, 36 + data, Endian.little);
  tag(8, 'WAVE');
  tag(12, 'fmt ');
  b.setUint32(16, 16, Endian.little);
  b.setUint16(20, format, Endian.little);
  b.setUint16(22, channels, Endian.little);
  b.setUint32(24, rate, Endian.little);
  b.setUint32(28, rate * channels * bits ~/ 8, Endian.little);
  b.setUint16(32, channels * bits ~/ 8, Endian.little);
  b.setUint16(34, bits, Endian.little);
  tag(36, 'data');
  b.setUint32(40, data, Endian.little);
  return b.buffer.asUint8List();
}

String _licences(Map<String, List<int>> placeholders, {String licensed = ''}) =>
    '# Audio\n\n## Licensed\n\n| File | Source | Licence |\n|---|---|---|\n'
    '$licensed\n## Placeholders\n\n| File | FNV-1a | Source |\n|---|---|---|\n'
    '${placeholders.entries.map((e) => '| `${e.key}` | `${fnv1a64Of(e.value)}` | x |\n').join()}';

void main() {
  group('the rules', () {
    final clip = _wav(.1);
    Map<String, List<int>> placeholders() => {
      for (final c in kCanonicalClips) 'placeholder-$c.wav': clip,
    };
    List<Offender> check(Map<String, List<int>> files, String licences) =>
        audioOffenders({...files, kLicenceRecord: const []}, licences);

    test('four recorded placeholders pass', () {
      expect(check(placeholders(), _licences(placeholders())), isEmpty);
    });

    test('a file that is neither clip nor placeholder fails, named', () {
      final files = {...placeholders(), 'mystery.wav': clip};
      final o = check(files, _licences(placeholders()));
      expect(o.single.path, 'mystery.wav');
    });

    test('a clip beside its placeholder fails, named', () {
      final files = {...placeholders(), 'place.wav': clip};
      final o = check(
        files,
        _licences(placeholders(), licensed: '| `place.wav` | a | b |\n'),
      );
      expect(o.single.path, 'place.wav');
      expect(o.single.message, contains('both'));
    });

    test('a three-second file fails, named', () {
      final files = {...placeholders(), 'placeholder-solve.wav': _wav(3)};
      final o = check(files, _licences(files));
      // 3 s is also over the size cap: two offenders, one file.
      expect(o.map((x) => x.path).toSet(), {'placeholder-solve.wav'});
      expect(o.map((x) => x.message), contains(contains('over 2 s')));
      expect(wavProblems(_wav(2)), isEmpty, reason: '2.000 s is allowed');
    });

    test('the format: PCM 16-bit 44.1 kHz mono, and a size cap', () {
      expect(wavProblems(_wav(.1, rate: 48000)).single, contains('48000'));
      expect(wavProblems(_wav(.1, channels: 2)).single, contains('mono'));
      expect(wavProblems(_wav(.1, bits: 8)).single, contains('16-bit'));
      expect(wavProblems(_wav(.1, format: 3)).single, contains('PCM'));
      expect(wavProblems([1, 2, 3]).single, contains('RIFF'));
      expect(
        wavProblems(_wav(1.9, channels: 2)),
        contains(contains('over ${250 * 1024}')),
      );
    });

    test('a real clip needs a licensed row with source and licence', () {
      final files = {...placeholders()}..remove('placeholder-lose.wav');
      files['lose.wav'] = clip;
      final rest = {...files}..remove('lose.wav');
      expect(check(files, _licences(rest)).single.path, 'lose.wav');
      expect(
        check(files, _licences(rest, licensed: '| `lose.wav` | a |  |\n')),
        hasLength(1),
        reason: 'an empty licence cell does not count',
      );
      expect(
        check(files, _licences(rest, licensed: '| `lose.wav` | a | b |\n')),
        isEmpty,
      );
      expect(
        licensedClips(
          '## Licensed\n\n| File | Source | Licence |\n|---|---|---|\n\n'
          'Later:\n\n| `lose.wav` | a | b |\n',
        ),
        isEmpty,
        reason: 'only the first table under the heading counts',
      );
    });

    test(
      'digests: a changed placeholder, a missing row, a row with no file',
      () {
        final changed = {...placeholders(), 'placeholder-place.wav': _wav(.2)};
        expect(
          check(changed, _licences(placeholders())).single.message,
          contains('FNV-1a'),
        );
        final noRow = {...placeholders()}..remove('placeholder-mistake.wav');
        expect(
          check(placeholders(), _licences(noRow)).single.message,
          contains('no digest row'),
        );
        final missing = {...placeholders()}..remove('placeholder-mistake.wav');
        expect(
          check(missing, _licences(placeholders())).map((o) => o.message),
          containsAll([contains('neither'), contains('no file')]),
        );
      },
    );
  });

  group('the repository', () {
    test('audio-assets: every file under assets/audio/ is accounted for', () {
      final dir = Directory('${repoRoot.path}/assets/audio');
      final files = {
        for (final f in dir.listSync().whereType<File>())
          f.uri.pathSegments.last: f.readAsBytesSync(),
      };
      final offenders = audioOffenders(
        files,
        readFile('assets/audio/LICENSES.md'),
      );
      expect(offenders, isEmpty, reason: _describe(offenders));
    });

    test('audio-declared: pubspec.yaml bundles the audio directory', () {
      expect(
        RegExp(
          r'^  assets:\n(?:    - .*\n)*    - assets/audio/\n',
          multiLine: true,
        ).hasMatch(stripYamlComments(readFile('pubspec.yaml'))),
        isTrue,
        reason: 'audio-declared: flutter: assets: does not list assets/audio/',
      );
    });
  });
}
