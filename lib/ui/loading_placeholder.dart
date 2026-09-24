// A plain stand-in for the designed loading screen (M4 replaces it): the
// phase word and a percentage while a board is made, or the failure with a
// retry.

import 'package:flutter/widgets.dart';
import 'package:honest_sudoku/engine/engine.dart' show GenerationPhase;

import 'board/game_controller.dart';
import 'board/notice_banner.dart';
import 'strings.dart';
import 'theme/tokens.dart';

/// The loading placeholder.
class LoadingPlaceholder extends StatelessWidget {
  /// Creates the placeholder.
  const LoadingPlaceholder({
    required this.status,
    required this.failure,
    required this.scale,
    required this.onRetry,
    super.key,
  });

  /// Progress, while generating.
  final LoadingStatus? status;

  /// A failure to show instead, with a retry.
  final GenerationFailureView? failure;

  /// Design points to logical pixels.
  final double scale;

  /// TRY AGAIN.
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final f = failure;
    if (f != null) {
      return Center(
        child: NoticeBanner(
          notice: f.notice,
          scale: scale,
          action: NoticeAction(UiStrings.tryAgain, onRetry),
        ),
      );
    }
    final st = status;
    final fraction = st?.fraction ?? 0;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            UiStrings.phaseLabel(st?.phase ?? GenerationPhase.generating),
            key: const ValueKey('loading-label'),
            style: plexMono(
              12,
              scale: scale,
              color: HsColors.muted,
              letterSpacingEm: .2,
            ),
          ),
          SizedBox(height: 10 * scale),
          Text(
            '${(fraction * 100).floor()}%',
            key: const ValueKey('loading-percent'),
            style: outfit(16, scale: scale, weight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}
