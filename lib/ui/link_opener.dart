// Opens a link in the phone's browser. The only place the app hands anything
// to another app; screens call this rather than url_launcher, so a test can
// record what would have opened. The URLs themselves live in lib/links.dart,
// the one file allowed to hold one.

import 'dart:developer' as developer;

import 'package:url_launcher/url_launcher.dart';

import '../links.dart';

/// How a link opens.
enum LinkMode {
  /// In the phone's browser, outside the app.
  external,
}

/// The About screens' destinations, parsed once.
abstract final class AppLinks {
  /// Honest Arcade's site.
  static final Uri site = Uri.parse(siteUrl);

  /// The studio's contribute page.
  static final Uri contribute = Uri.parse(contributeUrl);

  /// This app's source.
  static final Uri source = Uri.parse(sourceUrl);
}

/// Opens links.
abstract class LinkOpener {
  /// Creates an opener.
  const LinkOpener();

  /// Opens [uri]. Never throws; a failure is logged.
  Future<void> open(Uri uri, LinkMode mode);
}

/// Opens links with url_launcher, in the browser.
final class UrlLauncherLinkOpener extends LinkOpener {
  /// Creates the opener.
  const UrlLauncherLinkOpener({this.log = _log});

  /// Where failures are reported.
  final void Function(String message) log;

  static void _log(String message) =>
      developer.log(message, name: 'honest_sudoku.links');

  @override
  Future<void> open(Uri uri, LinkMode mode) async {
    try {
      final opened = await launchUrl(
        uri,
        mode: switch (mode) {
          LinkMode.external => LaunchMode.externalApplication,
        },
      );
      if (!opened) log('could not open $uri');
    } on Object catch (e) {
      log('could not open $uri: $e');
    }
  }
}
