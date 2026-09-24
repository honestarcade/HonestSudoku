// A mono text link with the design's underline, and the footer row of them.

import 'package:flutter/widgets.dart';

import '../link_opener.dart';
import '../theme/tokens.dart';

/// One underlined mono link.
class TextLink extends StatelessWidget {
  /// Creates a link to [uri] labelled [label].
  const TextLink({
    required this.label,
    required this.uri,
    required this.opener,
    super.key,
  });

  /// `HONEST ARCADE ↗`.
  final String label;

  /// Where it goes.
  final Uri uri;

  /// Opens it.
  final LinkOpener opener;

  @override
  Widget build(BuildContext context) => Semantics(
    link: true,
    label: label.replaceAll(' ↗', ''),
    excludeSemantics: true,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => opener.open(uri, LinkMode.external),
      child: Container(
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: HsColors.linkUnderline)),
        ),
        child: Text(
          label,
          style: plexMono(
            9.5,
            scale: 1,
            color: HsColors.muted,
            letterSpacingEm: .12,
            lineHeight: 1.7,
          ),
        ),
      ),
    ),
  );
}

/// A row of links separated by `·`, with an optional lead.
class FooterLinks extends StatelessWidget {
  /// Creates the row.
  const FooterLinks({
    required this.links,
    this.lead,
    this.center = false,
    super.key,
  });

  /// The links.
  final List<TextLink> links;

  /// `MADE BY`.
  final String? lead;

  /// Centred (the studio screen) rather than left-aligned.
  final bool center;

  @override
  Widget build(BuildContext context) {
    final dim = plexMono(
      9.5,
      scale: 1,
      color: HsColors.versionText,
      letterSpacingEm: .12,
      lineHeight: 1.7,
    );
    return Wrap(
      spacing: 8,
      alignment: center ? WrapAlignment.center : WrapAlignment.start,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (lead != null) Text(lead!, style: dim),
        for (var i = 0; i < links.length; i++) ...[
          if (i > 0) Text('·', style: dim),
          links[i],
        ],
      ],
    );
  }
}
