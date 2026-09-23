@Tags(['guard'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'repo_files.dart';
import 'secret_shapes.dart';

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
    // Both documents that claim it, not only the memory files. `README.md`'s
    // Release section is what AC6's "documented by name only" is about, and
    // it was outside every content scan: a password and PEM-shaped key
    // material pasted into its secrets table left the suite green (#261).
    final files = [
      ...Directory('${repoRoot.path}/.n8/memory')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.md')),
      File('${repoRoot.path}/README.md'),
    ];

    test('there are documents to check', () {
      // The positive control. A glob that matches nothing makes every
      // assertion below vacuously true, which is how a guard becomes
      // decoration (#226's lesson, applied at the point it bites here).
      expect(
        files.length,
        greaterThan(1),
        reason:
            'memory-guard: the document list is empty, so the scan below '
            'asserts nothing. If `.n8/memory/` moved, move this with it',
      );
    });

    for (final file in files) {
      final name = file.path.substring(repoRoot.path.length + 1);
      test('$name carries no secret-shaped content', () {
        final text = file.readAsStringSync();
        secretShapes.forEach((what, pattern) {
          // A match on a line that DECLARES itself is allowed, with a reason
          // of real length — the same mechanism as the chokepoint rule's
          // `chokepoint-exempt:`, and for the same reason: the alternative
          // was weakening the pattern until the honest case passed, which is
          // how the base64 floor reached 60 and let a whole 32-byte key
          // through (#263).
          //
          // The case this exists for: `play-console.md` records the service
          // account's key ID, which is a 40-character hex run and is public
          // by design — it names the key rather than being the key.
          final match = pattern.allMatches(text).where((m) {
            final line = text.substring(
              text.lastIndexOf('\n', m.start) + 1,
              () {
                final end = text.indexOf('\n', m.start);
                return end == -1 ? text.length : end;
              }(),
            );
            final declared = RegExp(r'not-a-secret:\s*(.{20,})')
                .firstMatch(line);
            return declared == null;
          }).firstOrNull;
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
