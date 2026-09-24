@Tags(['guard'])
library;

// The launcher icon in every form Android asks for, and a start screen that
// is navy, never white (#54). The rasters are rendered by
// tools/render_icons.sh and committed; this holds their shape, the resources
// that reference them, and the sources to the studio's shared mark.

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'launcher_icon_rules.dart';
import 'repo_files.dart';

const _res = 'android/app/src/main/res';

/// A PNG header only: signature and IHDR, which is all the checker reads.
List<int> _png(int w, int h, {int colorType = 6}) {
  final b = ByteData(33);
  const sig = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
  for (var i = 0; i < 8; i++) {
    b.setUint8(i, sig[i]);
  }
  b.setUint32(8, 13);
  for (var i = 0; i < 4; i++) {
    b.setUint8(12 + i, 'IHDR'.codeUnitAt(i));
  }
  b.setUint32(16, w);
  b.setUint32(20, h);
  b.setUint8(24, 8);
  b.setUint8(25, colorType);
  return b.buffer.asUint8List();
}

String _describe(String rule, List<String> offenders) =>
    '$rule: ${offenders.length} offender(s)\n  ${offenders.join('\n  ')}';

void main() {
  group('the rules', () {
    test('rasters: right sizes pass; a 100×100 file fails, named', () {
      final good = {
        for (final e in kIconPngs.entries) e.key: _png(e.value, e.value),
      };
      expect(pngOffenders(good), isEmpty);
      const path = '$_res/mipmap-hdpi/ic_launcher_foreground.png';
      final bad = {...good, path: _png(100, 100)};
      expect(pngOffenders(bad), ['$path: 100×100, not 162×162']);
      expect(pngOffenders({...good, path: null}), ['$path: missing']);
      expect(pngOffenders({...good, path: _png(162, 162, colorType: 2)}), [
        '$path: colour type 2, not RGBA (6)',
      ]);
      expect(pngHeader([1, 2, 3]), isNull);
    });

    test('the adaptive icon needs all three layers', () {
      const full = '''
<adaptive-icon>
    <background android:drawable="@color/ic_launcher_background"/>
    <foreground android:drawable="@mipmap/ic_launcher_foreground"/>
    <monochrome android:drawable="@mipmap/ic_launcher_monochrome"/>
</adaptive-icon>''';
      expect(adaptiveIconOffenders(full), isEmpty);
      final noMono = full.replaceFirst(RegExp(r'\s*<monochrome[^>]*/>'), '');
      expect(adaptiveIconOffenders(noMono).single, contains('monochrome'));
    });

    test('a corner in another colour fails, named; geometry-only ignores '
        'colour', () {
      final studio = readFile('assets/brand/STUDIO-MARK.svg');
      final tile = readFile('assets/brand/icon-tile.svg');
      expect(cornerOffenders(tile, studio), isEmpty);
      final violet = tile.replaceFirst('#8448FC', '#FF00FF');
      expect(violet, isNot(tile));
      expect(
        cornerOffenders(violet, studio).single,
        'corner 2 is #FF00FF, not #8448FC',
      );
      expect(cornerOffenders(violet, studio, colours: false), isEmpty);
      final bent = tile.replaceFirst('L 21 3', 'L 22 3');
      expect(cornerOffenders(bent, studio).single, startsWith('corner 1 is "'));
    });

    test('the splash colour on both themes, and a navy normal window', () {
      const ok = '''
<style name="LaunchTheme" parent="x">
  <item name="android:windowSplashScreenBackground">@color/splash_navy</item>
</style>
<style name="NormalTheme" parent="x">
  <item name="android:windowBackground">@color/splash_navy</item>
  <item name="android:windowSplashScreenBackground">@color/splash_navy</item>
</style>''';
      expect(splashOffenders(ok), isEmpty);
      expect(
        splashOffenders(ok.replaceFirst('@color/splash_navy', '#FFFFFFFF')),
        hasLength(1),
      );
    });
  });

  group('the repository', () {
    test(
      'launcher-rasters: every mipmap and the store icon, at size, RGBA',
      () {
        final files = {
          for (final path in kIconPngs.keys)
            path: pathExists(path)
                ? File('${repoRoot.path}/$path').readAsBytesSync()
                : null,
        };
        final offenders = pngOffenders(files);
        expect(
          offenders,
          isEmpty,
          reason: _describe('launcher-rasters', offenders),
        );
      },
    );

    test('launcher-adaptive: background, foreground and monochrome', () {
      final offenders = adaptiveIconOffenders(
        readFile('$_res/mipmap-anydpi-v26/ic_launcher.xml'),
      );
      expect(
        offenders,
        isEmpty,
        reason: _describe('launcher-adaptive', offenders),
      );
    });

    test('launcher-splash: Android 12+ themes splash on navy', () {
      final offenders = [
        for (final dir in ['values-v31', 'values-night-v31'])
          for (final o in splashOffenders(readFile('$_res/$dir/styles.xml')))
            '$dir: $o',
        for (final dir in ['values', 'values-night'])
          if (!readFile('$_res/$dir/styles.xml').contains(
            '<item name="android:windowBackground">@color/splash_navy</item>',
          ))
            '$dir: NormalTheme\'s windowBackground is not @color/splash_navy',
        if (!readFile('$_res/drawable/launch_background.xml')
            .contains('@color/splash_navy'))
          'drawable/launch_background.xml does not use @color/splash_navy',
      ];
      expect(
        offenders,
        isEmpty,
        reason: _describe('launcher-splash', offenders),
      );
    });

    test(
      'launcher-manifest: the icon is @mipmap/ic_launcher, no roundIcon',
      () {
        final manifest = readFile('android/app/src/main/AndroidManifest.xml');
        expect(manifest, contains('android:icon="@mipmap/ic_launcher"'));
        expect(manifest, isNot(contains('roundIcon')));
      },
    );

    test('launcher-colours: the native navies are the app\'s', () {
      final colors = readFile('$_res/values/colors.xml');
      final tokens = readFile('lib/ui/theme/tokens.dart');
      final themes = readFile('lib/ui/theme/board_theme.dart');
      final navy = RegExp(r'static const navy = Color\(0xFF([0-9A-Fa-f]{6})\)')
          .firstMatch(tokens)?[1];
      final grid = RegExp(
        r'static const navy = BoardTheme\._\(.*?gridBg: Color\(0xFF([0-9A-Fa-f]{6})\)',
        dotAll: true,
      ).firstMatch(themes)?[1];
      expect(navy, isNotNull);
      expect(grid, isNotNull);
      expect(androidColor(colors, 'splash_navy'), navy!.toUpperCase());
      expect(
        androidColor(colors, 'ic_launcher_background'),
        grid!.toUpperCase(),
      );
    });

    test('launcher-mark: the sources carry the studio mark', () {
      final studio = readFile('assets/brand/STUDIO-MARK.svg');
      final offenders = [
        for (final (file, colours) in [
          ('icon-tile.svg', true),
          ('icon-legacy.svg', true),
          ('android-foreground.svg', true),
          ('android-monochrome.svg', false),
        ])
          for (final o in cornerOffenders(
            readFile('assets/brand/$file'),
            studio,
            colours: colours,
          ))
            '$file: $o',
      ];
      expect(offenders, isEmpty, reason: _describe('launcher-mark', offenders));
      expect(
        studio,
        contains('android-foreground-frog-mint.svg'),
        reason:
            'launcher-mark: STUDIO-MARK.svg must name the file it was '
            'copied from',
      );
    });

    test('launcher-sources: the inline mark is one copy, the files exist, and '
        'nothing here ships', () {
      final marks = {
        for (final f in [
          'icon-tile.svg',
          'icon-legacy.svg',
          'android-foreground.svg',
        ])
          f: inlineMark(readFile('assets/brand/$f')),
      };
      expect(marks.values, everyElement(isNotNull));
      expect(
        marks.values.toSet(),
        hasLength(1),
        reason: 'launcher-sources: the inline mark copies differ',
      );
      for (final f in ['STUDIO-MARK.svg', 'README.md', 'fonts.conf']) {
        expect(pathExists('assets/brand/$f'), isTrue, reason: f);
      }
      expect(filesUnder('assets/brand').map((p) => p.split('/').last).toSet(), {
        'icon-tile.svg',
        'icon-legacy.svg',
        'android-foreground.svg',
        'android-monochrome.svg',
        'STUDIO-MARK.svg',
        'README.md',
        'fonts.conf',
      });
      expect(
        stripYamlComments(readFile('pubspec.yaml')),
        isNot(contains('assets/brand')),
        reason: 'launcher-sources: the brand sources are not app assets',
      );
      final mode = File('${repoRoot.path}/tools/render_icons.sh')
          .statSync()
          .mode;
      expect(mode & 0x49, isNot(0), reason: 'render_icons.sh is executable');
    });
  });
}
