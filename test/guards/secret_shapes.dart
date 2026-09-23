/// What a credential looks like when it lands in a committed document.
///
/// Shared, because two files make the same claim about themselves and the
/// claim is worth exactly one implementation: `.n8/memory/*.md` says in bold
/// that credentials are never stored there, and `README.md`'s Release section
/// documents the five secrets "by name only" (#258, #261).
///
/// Deliberately shaped rather than exhaustive, and the scope is stated here
/// rather than in a document that says the claim is simply "asserted" — a
/// guard believed to be stronger than it is, is worse than the habit it
/// replaced. What these catch, as of 2026-09-23:
///
///  * a PEM block and a JSON `private_key` field;
///  * an unbroken base64 or base64url run of 32 characters or more, which is
///    where a 24-byte key lands — the floor was 60, and a 32-byte AES key is
///    44 characters, so a whole key escaped (#263);
///  * a hex run of 40 characters or more, checked BEFORE base64 because every
///    hex run is also a base64 run and the base64 rule used to fire first,
///    which made the hex rule dead code;
///  * an assignment or a plain-English statement of something named like a
///    credential, where the value looks like one;
///  * a URL with an embedded password.
///
/// What they do NOT catch, recorded so the next reader knows the edge: a
/// credential split across lines, one shorter than 20 characters with no
/// keyword near it, and anything encrypted or encoded in a form not listed
/// above.
library;

/// A value that looks like a credential rather than like prose: at least
/// eight characters, and not a run of ordinary words.
const _credentialish =
    r'''[^\s'"]*[A-Za-z][^\s'"]*[0-9][^\s'"]*|[A-Za-z0-9+/_=-]{20,}''';

const _assignment =
    '(password|passwd|pass|secret|token|api[_-]?key)\\s*[:=]\\s*($_credentialish)';

const _inProse =
    '\\b(password|passphrase|secret|token|key)\\s+is\\s+($_credentialish)';

final Map<String, RegExp> secretShapes = {
  'a PEM private key block': RegExp(r'-----BEGIN [A-Z ]*PRIVATE KEY-----'),
  'a JSON private_key field': RegExp(r'"private_key"\s*:'),
  // Hex first: `[0-9a-f]{40,}` is also a base64 run, so with base64 first this
  // could never fire (#263).
  'a hex run of 40 characters or more': RegExp(r'\b[0-9a-fA-F]{40,}\b'),
  // The lookaheads are what keep this off ordinary paths. At 32 characters
  // with `/` and `-` in the class, `HonestArcadeApps/secrets/sudoku-signing-
  // credentials` and `repos/honestarcade/HonestSudoku/pages` both matched —
  // a guard that cries wolf on a file path gets its floor raised back, which
  // is how the floor got to 60 in the first place. A key has a digit and
  // both cases; a path of English words does not.
  'a base64 or base64url run of 32 characters or more': RegExp(
    r'\b(?=[A-Za-z0-9+/_=-]*[0-9])(?=[A-Za-z0-9+/_=-]*[a-z])'
    r'(?=[A-Za-z0-9+/_=-]*[A-Z])[A-Za-z0-9+/_=-]{32,}={0,2}',
  ),
  // `caseSensitive: false`, not an inline `(?i)` — Dart's RegExp rejects the
  // inline form with `FormatException: Invalid group`.
  //
  // No leading `\b` on the name: the shape this project would paste is
  // `HS_KEYSTORE_PASS=…`, and an underscore is a word character, so
  // `\bpass\b` never matches inside it (probed, #258).
  'an assignment of something named like a credential': RegExp(
    _assignment,
    caseSensitive: false,
  ),
  'a statement of a credential in prose': RegExp(
    _inProse,
    caseSensitive: false,
  ),
  'a URL with an embedded password': RegExp(
    r'\b[a-z][a-z0-9+.-]*://[^\s/@]+:[^\s/@]+@',
    caseSensitive: false,
  ),
};
