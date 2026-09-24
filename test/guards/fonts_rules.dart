// The bundled-fonts rules, as pure functions over strings and directories.
//
// Pure for the reason dependency_rules.dart gives: every failure in #47's test
// plan becomes a permanent unit test with inline fixtures rather than an edit
// someone makes once and throws away.
library;

import 'dart:io';

import 'package:yaml/yaml.dart';

import 'repo_files.dart';

/// One refusal, with the file and line that explain it.
typedef Offender = ({String path, int line, String message});

/// The families the app ships and the weights of each (#47).
const Map<String, Set<int>> kBundledFonts = {
  'Outfit': {300, 400, 500, 600, 700},
  'IBM Plex Mono': {400, 500, 600},
};

/// The family a weight with no family anywhere in its file is set in: the
/// theme's.
const String kThemeFamily = 'Outfit';

/// The licence texts that must sit beside the fonts.
const List<String> kLicenceFiles = ['OFL-Outfit.txt', 'OFL-IBMPlexMono.txt'];

/// The TrueType magic, `00 01 00 00`.
const List<int> kTrueTypeMagic = [0, 1, 0, 0];

/// The `flutter: fonts:` block as family → weight → asset. `weight:` defaults
/// to 400, as Flutter reads it. Null when the block is absent or malformed.
Map<String, Map<int, String>>? declaredFonts(String pubspecText) {
  final doc = loadYaml(pubspecText);
  if (doc is! YamlMap) return null;
  final flutter = doc['flutter'];
  if (flutter is! YamlMap) return null;
  final fonts = flutter['fonts'];
  if (fonts is! YamlList) return null;
  final out = <String, Map<int, String>>{};
  for (final family in fonts) {
    if (family is! YamlMap) return null;
    final name = family['family'];
    final files = family['fonts'];
    if (name is! String || files is! YamlList) return null;
    final weights = out.putIfAbsent(name, () => {});
    for (final file in files) {
      if (file is! YamlMap) return null;
      final asset = file['asset'];
      final weight = file['weight'] ?? 400;
      if (asset is! String || weight is! int) return null;
      weights[weight] = asset;
    }
  }
  return out;
}

/// The pubspec declares exactly [kBundledFonts]: these families, these
/// weights, nothing else.
List<Offender> pubspecFontOffenders(String pubspecText) {
  final declared = declaredFonts(pubspecText);
  if (declared == null) {
    return [
      (
        path: 'pubspec.yaml',
        line: 0,
        message: 'no readable flutter: fonts: block',
      ),
    ];
  }
  final out = <Offender>[];
  final names = {...declared.keys, ...kBundledFonts.keys};
  for (final name in names) {
    final got = declared[name]?.keys.toSet() ?? const <int>{};
    final want = kBundledFonts[name] ?? const <int>{};
    if (got.length != want.length || !got.containsAll(want)) {
      out.add((
        path: 'pubspec.yaml',
        line: _lineOf(pubspecText, 'family: $name'),
        message:
            'family "$name" declares weights ${_sorted(got)}, '
            'expected ${_sorted(want)}',
      ));
    }
  }
  return out;
}

/// Every declared asset exists under [root] and is a TrueType file.
List<Offender> fontAssetOffenders(Directory root, String pubspecText) {
  final declared = declaredFonts(pubspecText) ?? const {};
  final out = <Offender>[];
  for (final weights in declared.values) {
    for (final asset in weights.values) {
      final file = File('${root.path}/$asset');
      if (!file.existsSync()) {
        out.add((path: asset, line: 0, message: 'declared but missing'));
        continue;
      }
      final head = file.openSync();
      final bytes = head.readSync(4);
      head.closeSync();
      if (bytes.length < 4 ||
          !List.generate(
            4,
            (i) => i,
          ).every((i) => bytes[i] == kTrueTypeMagic[i])) {
        out.add((
          path: asset,
          line: 0,
          message: 'does not start with the TrueType magic 00 01 00 00',
        ));
      }
    }
  }
  return out;
}

/// The README table, `SHA256SUMS` and `SOURCES.tsv` record the same files
/// with the same hashes; the fonts among them are exactly the pubspec's
/// assets; both licence texts are among them.
List<Offender> provenanceOffenders({
  required String readme,
  required String sums,
  required String sources,
  required String pubspecText,
}) {
  final out = <Offender>[];
  final sumHashes = <String, String>{
    for (final m in RegExp(
      r'^([0-9a-f]{64})  (\S+)$',
      multiLine: true,
    ).allMatches(sums))
      m[2]!: m[1]!,
  };
  final readmeHashes = <String, String>{};
  final table = RegExp(
    r'<!-- fonts:begin -->(.*)<!-- fonts:end -->',
    dotAll: true,
  ).firstMatch(readme);
  if (table == null) {
    out.add((
      path: 'assets/fonts/README.md',
      line: 0,
      message: 'no table between the fonts:begin/fonts:end markers',
    ));
  } else {
    for (final m in RegExp(
      r'^\| `([^`]+)` \|.*\| `([0-9a-f]{64})` \|$',
      multiLine: true,
    ).allMatches(table[1]!)) {
      readmeHashes[m[1]!] = m[2]!;
    }
  }
  final sourceNames = {
    for (final line in sources.split('\n').skip(1))
      if (line.trim().isNotEmpty) line.split('\t').first,
  };
  final recorded = sumHashes.keys.toSet();
  void same(String what, Set<String> names) {
    final missing = recorded.difference(names);
    final extra = names.difference(recorded);
    if (missing.isNotEmpty || extra.isNotEmpty) {
      out.add((
        path: what,
        line: 0,
        message:
            'differs from SHA256SUMS: missing ${_sorted(missing)}, '
            'extra ${_sorted(extra)}',
      ));
    }
  }

  same('assets/fonts/README.md', readmeHashes.keys.toSet());
  same('assets/fonts/SOURCES.tsv', sourceNames);
  for (final e in readmeHashes.entries) {
    if (sumHashes[e.key] != null && sumHashes[e.key] != e.value) {
      out.add((
        path: 'assets/fonts/README.md',
        line: _lineOf(readme, '`${e.key}`'),
        message: '${e.key}: the table\'s hash is not the one in SHA256SUMS',
      ));
    }
  }
  for (final licence in kLicenceFiles) {
    if (!recorded.contains(licence)) {
      out.add((
        path: 'assets/fonts/SHA256SUMS',
        line: 0,
        message: 'the licence text $licence is not recorded',
      ));
    }
  }
  final assets = {
    for (final weights in (declaredFonts(pubspecText) ?? const {}).values)
      for (final asset in weights.values) asset.split('/').last,
  };
  final recordedFonts = recorded.where((n) => n.endsWith('.ttf')).toSet();
  if (assets.length != recordedFonts.length ||
      !assets.containsAll(recordedFonts)) {
    out.add((
      path: 'pubspec.yaml',
      line: 0,
      message:
          'declares ${_sorted(assets)} but SHA256SUMS records '
          '${_sorted(recordedFonts)}',
    ));
  }
  return out;
}

/// Every `FontWeight` used with a bundled family under [lib] is one of that
/// family's weights in [bundled].
List<Offender> weightOffenders(Directory lib, Map<String, Set<int>> bundled) {
  final base = lib.absolute.parent.path;
  final files = {
    for (final f in lib.absolute.listSync(recursive: true).whereType<File>())
      if (f.path.endsWith('.dart'))
        f.path.substring(base.length + 1): f.readAsStringSync(),
  };
  return weightOffendersIn(files, bundled);
}

/// [weightOffenders] over path → source.
///
/// A weight belongs to the innermost call around it. That call's family is
/// the family of a style helper (a function returning `TextStyle` whose body
/// sets `fontFamily:`), or its own `fontFamily:` argument. Otherwise the
/// weight takes its file's family when the file names exactly one, the
/// theme's when it names none, and is ignored when it names several.
List<Offender> weightOffendersIn(
  Map<String, String> files,
  Map<String, Set<int>> bundled,
) {
  final stripped = {
    for (final e in files.entries) e.key: stripDartComments(e.value),
  };
  // Constants naming a family, from every file.
  final tokens = <String, String>{};
  for (final src in stripped.values) {
    for (final m in RegExp(
      r'''const\s+(?:String\s+)?(\w+)\s*=\s*['"]([^'"]+)['"]\s*;''',
    ).allMatches(src)) {
      if (bundled.containsKey(m[2])) tokens[m[1]!] = m[2]!;
    }
  }
  String? resolve(String ref) {
    final literal = RegExp(r'''^['"](.+)['"]$''').firstMatch(ref);
    if (literal != null) {
      return bundled.containsKey(literal[1]) ? literal[1] : null;
    }
    return tokens[ref];
  }

  final familyArg = RegExp(r'''fontFamily:\s*('[^']*'|"[^"]*"|\w+)''');
  // Style helpers, from every file.
  final helpers = <String, String>{};
  for (final src in stripped.values) {
    final defs = RegExp(r'TextStyle\s+(\w+)\s*\(').allMatches(src).toList();
    for (var i = 0; i < defs.length; i++) {
      final end = i + 1 < defs.length ? defs[i + 1].start : src.length;
      final arg = familyArg.firstMatch(src.substring(defs[i].start, end));
      final family = arg == null ? null : resolve(arg[1]!);
      if (family != null) helpers[defs[i][1]!] = family;
    }
  }

  final out = <Offender>[];
  final weight = RegExp(r'FontWeight\.(w[1-9]00|bold|normal)\b');
  for (final e in stripped.entries) {
    final src = e.value;
    final masked = _maskStrings(src);
    final named = <String>{
      for (final m in familyArg.allMatches(src)) ?resolve(m[1]!),
      for (final h in helpers.entries)
        if (RegExp('\\b${h.key}\\s*\\(').hasMatch(src)) h.value,
    };
    for (final m in weight.allMatches(masked)) {
      final value = switch (m[1]!) {
        'bold' => 700,
        'normal' => 400,
        final w => int.parse(w.substring(1)),
      };
      String? family;
      final open = _enclosingParen(masked, m.start);
      if (open != null) {
        final callee = RegExp(r'(\w+)\s*$')
            .firstMatch(masked.substring(0, open))?[1];
        family = helpers[callee];
        if (family == null) {
          final close = _matchingParen(masked, open);
          final arg = familyArg.firstMatch(src.substring(open, close));
          if (arg != null) family = resolve(arg[1]!);
        }
      }
      family ??= switch (named.length) {
        0 => kThemeFamily,
        1 => named.single,
        _ => null,
      };
      if (family == null) continue;
      if (!(bundled[family]?.contains(value) ?? false)) {
        out.add((
          path: e.key,
          line: '\n'.allMatches(src.substring(0, m.start)).length + 1,
          message:
              'FontWeight.${m[1]} ($value) with "$family", which bundles '
              '${_sorted(bundled[family] ?? const <int>{})}',
        ));
      }
    }
  }
  return out;
}

/// [source] with every string's contents blanked, lengths and newlines kept,
/// so parentheses inside strings do not count.
String _maskStrings(String source) {
  final out = StringBuffer();
  var i = 0;
  while (i < source.length) {
    final ch = source[i];
    if (ch != "'" && ch != '"') {
      out.write(ch);
      i++;
      continue;
    }
    final quote = source.startsWith(ch * 3, i) ? ch * 3 : ch;
    out.write(quote);
    i += quote.length;
    while (i < source.length && !source.startsWith(quote, i)) {
      if (source[i] == r'\' && i + 1 < source.length) {
        out.write('  ');
        i += 2;
        continue;
      }
      out.write(source[i] == '\n' ? '\n' : ' ');
      i++;
    }
    if (i < source.length) {
      out.write(quote);
      i += quote.length;
    }
  }
  return out.toString();
}

int? _enclosingParen(String src, int at) {
  var depth = 0;
  for (var i = at - 1; i >= 0; i--) {
    final ch = src[i];
    if (ch == ')') depth++;
    if (ch == '(') {
      if (depth == 0) return i;
      depth--;
    }
  }
  return null;
}

int _matchingParen(String src, int open) {
  var depth = 0;
  for (var i = open; i < src.length; i++) {
    if (src[i] == '(') depth++;
    if (src[i] == ')' && --depth == 0) return i + 1;
  }
  return src.length;
}

int _lineOf(String text, String needle) {
  final at = text.indexOf(needle);
  return at < 0 ? 0 : '\n'.allMatches(text.substring(0, at)).length + 1;
}

List<T> _sorted<T extends Object>(Iterable<T> xs) => xs.toList()..sort();
