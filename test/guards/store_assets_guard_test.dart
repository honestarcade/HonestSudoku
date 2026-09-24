@Tags(['guard'])
library;

// The Play listing's art (#57): the feature graphic, the icon and eight phone
// screenshots exist in the repo at the sizes Play takes, reproducible by the
// scripts beside them.

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'launcher_icon_rules.dart';
import 'repo_files.dart';

const _store = 'ArtSource/store';

/// The eight screenshots, in listing order.
const kStoreScreenshots = [
  '01-menu',
  '02-setup',
  '03-board-9x9',
  '04-board-16x16',
  '05-paper-hint',
  '06-stats',
  '07-settings',
  '08-howto',
];

/// `path: problem` for every store asset under [root] that is missing or the
/// wrong shape.
List<String> storeAssetOffenders(Directory root) {
  List<int>? read(String path) {
    final f = File('${root.path}/$path');
    return f.existsSync() ? f.readAsBytesSync() : null;
  }

  List<String> check(String path, int w, int h, Set<int> types) {
    final bytes = read(path);
    if (bytes == null) return ['$path: missing'];
    final head = pngHeader(bytes);
    if (head == null) return ['$path: not a PNG'];
    return [
      if (head.width != w || head.height != h)
        '$path: ${head.width}×${head.height}, not $w×$h',
      if (!types.contains(head.colorType))
        '$path: colour type ${head.colorType}, not one of $types',
    ];
  }

  return [
    for (final name in kStoreScreenshots)
      ...check('$_store/screenshots/$name.png', 1080, 1920, {2, 6}),
    // Play refuses alpha on the feature graphic.
    ...check('$_store/feature-graphic-1024x500.png', 1024, 500, {2}),
    ...check('$_store/icon-512.png', 512, 512, {6}),
  ];
}

List<int> _png(int w, int h, int type) {
  final b = ByteData(33);
  const sig = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
  for (var i = 0; i < 8; i++) {
    b.setUint8(i, sig[i]);
  }
  b.setUint32(8, 13);
  for (var i = 0; i < 4; i++) {
    b.setUint8(12 + i, 'IHDR'.codeUnitAt(i));
  }
  b
    ..setUint32(16, w)
    ..setUint32(20, h)
    ..setUint8(24, 8)
    ..setUint8(25, type);
  return b.buffer.asUint8List();
}

void main() {
  test('the rule: right sizes pass; a 9:19.5 screenshot fails, named', () {
    final tmp = Directory.systemTemp.createTempSync('store-assets');
    addTearDown(() => tmp.deleteSync(recursive: true));
    void write(String path, List<int> bytes) => File('${tmp.path}/$path')
      ..createSync(recursive: true)
      ..writeAsBytesSync(bytes);
    for (final name in kStoreScreenshots) {
      write('$_store/screenshots/$name.png', _png(1080, 1920, 2));
    }
    write('$_store/feature-graphic-1024x500.png', _png(1024, 500, 2));
    write('$_store/icon-512.png', _png(512, 512, 6));
    expect(storeAssetOffenders(tmp), isEmpty);

    write('$_store/screenshots/04-board-16x16.png', _png(1080, 2340, 2));
    expect(storeAssetOffenders(tmp), [
      '$_store/screenshots/04-board-16x16.png: 1080×2340, not 1080×1920',
    ]);
    write('$_store/screenshots/04-board-16x16.png', _png(1080, 1920, 2));
    write('$_store/feature-graphic-1024x500.png', _png(1024, 500, 6));
    expect(storeAssetOffenders(tmp).single, contains('colour type 6'));
  });

  test('store-assets: every listing asset is present and Play-shaped', () {
    final offenders = storeAssetOffenders(repoRoot);
    expect(
      offenders,
      isEmpty,
      reason:
          'store-assets: ${offenders.length} offender(s)\n  '
          '${offenders.join('\n  ')}',
    );
  });

  test('store-sources: the graphic\'s mark is the icon\'s, and the scripts '
      'are there', () {
    expect(
      inlineMark(readFile('assets/brand/feature-graphic.svg')),
      inlineMark(readFile('assets/brand/icon-tile.svg')),
      reason:
          'store-sources: the feature graphic\'s mark drifted from the icon',
    );
    for (final script in [
      'tools/render_store_assets.sh',
      'tools/screenshots.sh',
      'tools/png_strip_alpha.py',
    ]) {
      final f = File('${repoRoot.path}/$script');
      expect(f.existsSync(), isTrue, reason: script);
      expect(f.statSync().mode & 0x49, isNot(0), reason: '$script executable');
    }
    expect(pathExists('$_store/README.md'), isTrue);
  });
}
