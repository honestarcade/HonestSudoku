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
  // Added by #94, after verification probed the list and found fifteen
  // ads, analytics and network packages walking straight through it. The
  // originals matched #15's acceptance criteria exactly, so this extends
  // what was specified — see the ad-hoc entry in .n8/decisions.md.
  'facebook_app_events',
  'adjust_sdk',
  'flutter_branch_sdk',
  'appmetrica_plugin',
  'socket_io_client',
  'graphql_flutter',
  'graphql',
  'retrofit',
  'chopper',
  'http2',
  'cronet_http',
  'cupertino_http',
  'native_dio_adapter',
  'googleapis',
  'googleapis_auth',
  'supabase_flutter',
  'amplify_flutter',
  'aws_common',
  'new_relic_mobile',
  'pusher_channels_flutter',
  'mqtt_client',
  'universal_io',
  'flutter_downloader',
  'flutter_appauth',
  'vungle',
  'chartboost',
];

/// Refused by shape, for the ones nobody has thought of yet. `*` matches any
/// run including an empty one, and the pattern is anchored to the whole name.
const List<String> blockedPatterns = [
  // Shapes that mean advertising, not letters that spell it. `*ads` and
  // `*ads_*` were both too broad: they refused `gamepads` (a real package from
  // the Flame team, and a plausible want for a game), its three federated
  // platform packages, `downloads_path_provider` and `threads`. A blocklist
  // that refuses ordinary packages gets deleted, and the glob is also what
  // catches the ads SDKs nobody has named yet (#97).
  '*_ads',
  '*_ads_*',
  'ads_*',
  'admob*',
  '*mobileads*',
  '*analytics*',
  '*crashlytics*',
  '*tracking*',
  '*attribution*',
  '*webview*',
  'firebase_*',
  'googleapis*',
  'sentry_*',
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
