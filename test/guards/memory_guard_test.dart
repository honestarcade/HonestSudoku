@Tags(['guard'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'repo_files.dart';

/// `.n8/memory/` is the project's own record of things like the Play Console
/// account, and `play-console.md` says of itself, in bold, that credentials
/// are never stored there.
///
/// Nothing asserted it. The file is written by hand, read by people, and the
/// one property it claims about itself rested on whoever edited it last
/// remembering the rule (#258). This is that claim, executed — the same shape
/// as the guard that holds CLAUDE.md's dependency exemption to `pubspec.yaml`,
/// which is the only mechanism in this project that has ever stopped a written
/// claim from rotting.
void main() {
  group('the memory files hold no credential', () {
    /// What a secret looks like when it lands in a document by accident.
    ///
    /// Deliberately shaped rather than exhaustive: a PEM block, a long
    /// unbroken base64 or hex run (a key, a keystore, a token), and the
    /// assignment forms a copied line arrives in. An identifier that merely
    /// NAMES a key — the service account's key id is in `play-console.md` on
    /// purpose, and says so — is not a secret, which is why the base64 rule
    /// needs a length no human identifier reaches.
    final shapes = <String, RegExp>{
      'a PEM private key block': RegExp(r'-----BEGIN [A-Z ]*PRIVATE KEY-----'),
      'a JSON private_key field': RegExp(r'"private_key"\s*:'),
      'a 60-character unbroken base64 run': RegExp(r'[A-Za-z0-9+/]{60,}={0,2}'),
      'a 64-character unbroken hex run': RegExp(r'\b[0-9a-fA-F]{64,}\b'),
      // `caseSensitive: false`, not an inline `(?i)` — Dart's RegExp rejects
      // the inline form with `FormatException: Invalid group`, and every
      // assertion here threw before the first file was read.
      'an assignment of something named like a secret': RegExp(
        r'\b(password|passwd|secret|token|api[_-]?key)\b\s*[:=]\s*\S{8,}',
        caseSensitive: false,
      ),
    };

    final files = Directory('${repoRoot.path}/.n8/memory')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.md'))
        .toList();

    test('there are memory files to check', () {
      // The positive control. A glob that matches nothing makes every
      // assertion below vacuously true, which is how a guard becomes
      // decoration (#226's lesson, applied at the point it bites here).
      expect(
        files,
        isNotEmpty,
        reason:
            'memory-guard: no `.md` under `.n8/memory/`, so the scan below '
            'asserts nothing. If the directory moved, move this with it',
      );
    });

    for (final file in files) {
      final name = file.path.substring(repoRoot.path.length + 1);
      test('$name carries no secret-shaped content', () {
        final text = file.readAsStringSync();
        shapes.forEach((what, pattern) {
          final match = pattern.firstMatch(text);
          expect(
            match,
            isNull,
            reason:
                'memory-guard: $name contains $what — '
                '`${match?.group(0) ?? ''}`. These files are committed, '
                'readable by anyone with the repository, and are meant to '
                'record where a credential lives rather than the credential',
          );
        });
      });
    }
  });
}
