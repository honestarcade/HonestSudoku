// A stand-in for a screen M4 builds (rules, settings, the menu, setup): it
// names where the button meant to go and has a way back.

import 'package:flutter/material.dart';

import 'theme/tokens.dart';

/// A placeholder route naming [destination].
class PlaceholderScreen extends StatelessWidget {
  /// Creates the placeholder.
  const PlaceholderScreen({required this.destination, super.key});

  /// The screen this stands in for.
  final String destination;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: HsColors.navy,
    body: SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IconButton(
            key: const ValueKey('placeholder-back'),
            tooltip: 'Back',
            color: HsColors.white,
            icon: const Text('‹', style: TextStyle(fontSize: 28)),
            onPressed: () => Navigator.of(context).maybePop(),
          ),
          Expanded(
            child: Center(
              child: Text(
                destination,
                key: const ValueKey('placeholder-destination'),
                style: outfit(24, scale: 1, weight: FontWeight.w600),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
