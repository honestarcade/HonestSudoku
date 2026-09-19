// The dependency policy for this app, as data.
//
// It enforces two project invariants (CLAUDE.md):
//   1. No ads, no tracking, no analytics, no network.
//   3. Lean dependencies, each carrying a one-line justification.
//
// CHANGING THIS LIST IS A DECISION, NOT A REFACTOR. Removing a name or
// loosening a pattern weakens an invariant the owner set. The procedure is the
// ad-hoc ledger: append an `## Ad-hoc` entry to .n8/decisions.md naming the
// change, the why and the milestones it affects, and say so in the pull
// request. A diff that quietly shortens this list is the thing the guard exists
// to make visible.
library;

/// Packages refused by exact name: ads, analytics, crash reporting, and
/// anything whose reason for existing is to open a socket.
const List<String> blockedNames = [
  'http',
  'dio',
  'web_socket_channel',
  'grpc',
  'google_fonts',
  'google_mobile_ads',
  'in_app_purchase',
  'purchases_flutter',
  'connectivity_plus',
  'firebase_core',
  'firebase_analytics',
  'firebase_crashlytics',
  'sentry',
  'sentry_flutter',
  'bugsnag_flutter',
  'datadog_flutter_plugin',
  'onesignal_flutter',
  'appsflyer_sdk',
  'mixpanel_flutter',
  'amplitude_flutter',
  'posthog_flutter',
  'unity_ads_plugin',
  'applovin_max',
  'ironsource_mediation',
  'facebook_audience_network',
];

/// Refused by shape, for the ones nobody has thought of yet. `*` matches any
/// run including an empty one, and the pattern is anchored to the whole name.
const List<String> blockedPatterns = [
  '*_ads',
  '*ads_*',
  '*analytics*',
  '*crashlytics*',
  '*tracking*',
  'firebase_*',
];

/// Packages that need no `# why:` line, because they are the SDK itself or the
/// lints everyone runs. This list exempts from the *justification* rule only —
/// it never exempts anything from the blocklist.
const List<String> exemptFromJustification = [
  'flutter',
  'flutter_test',
  'flutter_lints',
  'flutter_localizations',
];

/// Returns the blocklist entry or pattern that refuses [name], or null when
/// nothing does. Returning the reason rather than a bool is what lets a failure
/// say *why* a package was refused.
String? matches(String name) {
  final lower = name.toLowerCase().trim();
  if (lower.isEmpty) return null;
  for (final blocked in blockedNames) {
    if (lower == blocked.toLowerCase()) return blocked;
  }
  for (final pattern in blockedPatterns) {
    if (_globMatches(pattern.toLowerCase(), lower)) return pattern;
  }
  return null;
}

/// Whole-name glob where `*` matches any run, including empty.
bool _globMatches(String pattern, String value) {
  final escaped = pattern.split('*').map(RegExp.escape).join('.*');
  return RegExp('^$escaped\$').hasMatch(value);
}
