/// The only file in this app allowed to contain a URL.
///
/// Every other file under lib/ fails the dependency guard if it holds one, so
/// a link can never be scattered into a widget where nobody will find it again.
/// These are opened in the system browser; the app itself makes no network
/// call and holds no INTERNET permission (invariant 1).
library;

/// Honest Arcade's site, linked from the About screen.
const String siteUrl = 'https://honestarcade.app';

/// The studio's contribute page, linked from the support card.
const String contributeUrl = 'https://honestarcade.app/contribute';

/// This app's source, linked from About the App.
const String sourceUrl = 'https://github.com/honestarcade/HonestSudoku';
