// The launcher-icon rules (#54), as pure functions over bytes and text.
library;

/// A PNG's width, height and colour type, read from its signature and IHDR
/// by hand; null when [bytes] is not a PNG.
({int width, int height, int colorType})? pngHeader(List<int> bytes) {
  const signature = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
  if (bytes.length < 26) return null;
  for (var i = 0; i < 8; i++) {
    if (bytes[i] != signature[i]) return null;
  }
  if (String.fromCharCodes(bytes.sublist(12, 16)) != 'IHDR') return null;
  int u32(int at) =>
      bytes[at] << 24 |
      bytes[at + 1] << 16 |
      bytes[at + 2] << 8 |
      bytes[at + 3];
  return (width: u32(16), height: u32(20), colorType: bytes[25]);
}

const _res = 'android/app/src/main/res';

/// Every raster the icon needs, with its exact pixel size.
const Map<String, int> kIconPngs = {
  '$_res/mipmap-mdpi/ic_launcher_foreground.png': 108,
  '$_res/mipmap-hdpi/ic_launcher_foreground.png': 162,
  '$_res/mipmap-xhdpi/ic_launcher_foreground.png': 216,
  '$_res/mipmap-xxhdpi/ic_launcher_foreground.png': 324,
  '$_res/mipmap-xxxhdpi/ic_launcher_foreground.png': 432,
  '$_res/mipmap-mdpi/ic_launcher_monochrome.png': 108,
  '$_res/mipmap-hdpi/ic_launcher_monochrome.png': 162,
  '$_res/mipmap-xhdpi/ic_launcher_monochrome.png': 216,
  '$_res/mipmap-xxhdpi/ic_launcher_monochrome.png': 324,
  '$_res/mipmap-xxxhdpi/ic_launcher_monochrome.png': 432,
  '$_res/mipmap-mdpi/ic_launcher.png': 48,
  '$_res/mipmap-hdpi/ic_launcher.png': 72,
  '$_res/mipmap-xhdpi/ic_launcher.png': 96,
  '$_res/mipmap-xxhdpi/ic_launcher.png': 144,
  '$_res/mipmap-xxxhdpi/ic_launcher.png': 192,
  'ArtSource/store/icon-512.png': 512,
};

/// `path: problem` for each raster in [files] (path → bytes, null when
/// missing) that is absent, the wrong size, or not RGBA.
List<String> pngOffenders(Map<String, List<int>?> files) => [
  for (final MapEntry(key: path, value: size) in kIconPngs.entries)
    ...() {
      final bytes = files[path];
      if (bytes == null) return ['$path: missing'];
      final h = pngHeader(bytes);
      if (h == null) return ['$path: not a PNG'];
      return [
        if (h.width != size || h.height != size)
          '$path: ${h.width}×${h.height}, not $size×$size',
        if (h.colorType != 6) '$path: colour type ${h.colorType}, not RGBA (6)',
      ];
    }(),
];

/// What the adaptive icon XML lacks of its three layers.
List<String> adaptiveIconOffenders(String xml) => [
  for (final (layer, ref) in [
    ('background', '@color/ic_launcher_background'),
    ('foreground', '@mipmap/ic_launcher_foreground'),
    ('monochrome', '@mipmap/ic_launcher_monochrome'),
  ])
    if (!RegExp('<$layer\\s+android:drawable="${RegExp.escape(ref)}"\\s*/>')
        .hasMatch(xml))
      'no <$layer android:drawable="$ref"/>',
];

/// What a v31 styles file lacks: both themes set the splash navy, and the
/// normal theme's window is navy.
List<String> splashOffenders(String xml) {
  const navy = r'(@color/splash_navy|#FF05285F|#05285F)';
  String? theme(String name) => RegExp(
    '<style name="$name"[^>]*>(.*?)</style>',
    dotAll: true,
  ).firstMatch(xml)?[1];
  return [
    for (final name in ['LaunchTheme', 'NormalTheme'])
      if (!RegExp(
        '<item name="android:windowSplashScreenBackground">$navy</item>',
      ).hasMatch(theme(name) ?? ''))
        '$name has no navy windowSplashScreenBackground',
    if (!RegExp('<item name="android:windowBackground">$navy</item>')
        .hasMatch(theme('NormalTheme') ?? ''))
      'NormalTheme\'s windowBackground is not navy',
  ];
}

/// The four corner paths of an SVG's corner group: (stroke, d) with the
/// path data's whitespace normalised.
List<(String, String)> cornerPaths(String svg) {
  final group = RegExp(
    r'<g fill="none" stroke-width="6" stroke-linecap="round" '
    r'stroke-linejoin="round">(.*?)</g>',
    dotAll: true,
  ).firstMatch(svg);
  if (group == null) return const [];
  return [
    for (final m in RegExp(
      r'<path stroke="(#[0-9A-Fa-f]{6})" d="([^"]*)"',
    ).allMatches(group[1]!))
      (m[1]!.toUpperCase(), m[2]!.trim().replaceAll(RegExp(r'\s+'), ' ')),
  ];
}

/// How [svg]'s corner group differs from the studio mark's; with
/// [colours] false only the geometry is compared (the monochrome layer).
List<String> cornerOffenders(String svg, String studio, {bool colours = true}) {
  final got = cornerPaths(svg);
  final want = cornerPaths(studio);
  if (want.length != 4) return ['the studio mark has ${want.length} corners'];
  if (got.length != 4) return ['${got.length} corner paths, not 4'];
  return [
    for (var i = 0; i < 4; i++) ...[
      if (got[i].$2 != want[i].$2)
        'corner ${i + 1} is "${got[i].$2}", not "${want[i].$2}"',
      if (colours && got[i].$1 != want[i].$1)
        'corner ${i + 1} is ${got[i].$1}, not ${want[i].$1}',
    ],
  ];
}

/// The mark-and-board block between `mark:begin` and `mark:end`, each line
/// stripped of its indentation; null when absent.
String? inlineMark(String svg) {
  final m = RegExp(
    r'<!-- mark:begin -->(.*?)<!-- mark:end -->',
    dotAll: true,
  ).firstMatch(svg);
  return m?[1]!.split('\n').map((l) => l.trim()).join('\n').trim();
}

/// The `0xFF......` value assigned to [identifier] in Dart [source].
String? dartHex(String source, String identifier) =>
    RegExp('\\b$identifier\\b[^;]*?0x[Ff]{2}([0-9A-Fa-f]{6})')
        .firstMatch(source)?[1]
        ?.toUpperCase();

/// The `#FF......` value of Android colour [name] in colors.xml [xml].
String? androidColor(String xml, String name) =>
    RegExp('<color name="$name">#(?:FF)?([0-9A-Fa-f]{6})</color>')
        .firstMatch(xml)?[1]
        ?.toUpperCase();
