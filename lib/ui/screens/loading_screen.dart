// The designed loading screen: the mark, the wordmark, a progress bar and
// the phase label. At launch it shows while saved data loads, then hands
// over to the menu; while a board is generated it shows real progress, then
// hands over to the board. A failure stops the bar and offers a retry.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:honest_sudoku/engine/engine.dart';
import 'package:honest_sudoku/game/game.dart';

import '../app_scope.dart';
import '../board/board_layout.dart';
import '../board/game_controller.dart';
import '../board/notice_banner.dart';
import '../copy.dart';
import '../routes.dart';
import '../strings.dart';
import '../theme/board_theme.dart';
import '../theme/tokens.dart';
import '../widgets/app_mark.dart';
import '../widgets/design_button.dart';
import '../widgets/wordmark.dart';

/// The launch splash stays at least this long, so it never flashes.
const Duration kSplashMinimum = Duration(milliseconds: 800);

/// Generation shows the screen at least this long, so a fast 4×4 does not
/// flash.
const Duration kGenerationMinimum = Duration(milliseconds: 400);

/// The splash background: the design's
/// `radial-gradient(120% 110% at 50% 18%, #0a3a80 0%, #05285F 55%, #031634)`.
const RadialGradient kSplashGradient = RadialGradient(
  center: Alignment(0, -.64),
  radius: 1,
  colors: [Color(0xFF0A3A80), Color(0xFF05285F), Color(0xFF031634)],
  stops: [0, .55, 1],
  transform: EllipseGradientTransform(1.2, 1.1, Offset(.5, .18)),
);

/// The loading screen.
class LoadingScreen extends StatefulWidget {
  /// Creates the screen in [mode].
  const LoadingScreen({required this.mode, super.key});

  /// Launch or generation.
  final LoadingMode mode;

  @override
  State<LoadingScreen> createState() => _LoadingScreenState();
}

class _LoadingScreenState extends State<LoadingScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _bar = AnimationController(
    vsync: this,
    duration: widget.mode == LoadingMode.launch
        ? kSplashMinimum
        : const Duration(milliseconds: 200),
  );
  GameController? _controller;
  Timer? _minimum;
  var _minimumPassed = false;
  var _ready = false;
  var _handedOver = false;
  Notice? _launchFailure;

  bool get _launch => widget.mode == LoadingMode.launch;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_controller != null) return;
    final c = _controller = AppScope.of(context).controller;
    _minimum = Timer(_launch ? kSplashMinimum : kGenerationMinimum, () {
      _minimumPassed = true;
      _maybeHandOver();
    });
    if (_launch) {
      _bar.forward();
      _startLaunch();
    } else {
      c.addListener(_onProgress);
      _watchGeneration();
    }
  }

  void _startLaunch() {
    _launchFailure = null;
    _controller!.load().then(
      (_) {
        _ready = true;
        _maybeHandOver();
      },
      onError: (Object e) {
        if (!mounted) return;
        setState(
          () => _launchFailure = const Notice(
            BannerKind.error,
            Copy.savedDataUnavailable,
            Copy.savedDataBody,
          ),
        );
      },
    );
  }

  void _watchGeneration() {
    _ready = false;
    _controller!.generationDone.then(
      (_) {
        _ready = true;
        // Let the bar reach the end before the board replaces it.
        _bar.animateTo(1, curve: Curves.easeOut).whenComplete(_maybeHandOver);
      },
      onError: (Object _) {
        if (mounted) setState(() {});
      },
    );
  }

  void _onProgress() {
    final status = _controller?.loading;
    if (status != null && mounted) {
      _bar.animateTo(status.fraction, curve: Curves.easeOut);
    }
    if (mounted) setState(() {});
  }

  void _maybeHandOver() {
    if (_handedOver || !_ready || !_minimumPassed || !mounted) return;
    _handedOver = true;
    if (_launch) {
      Routes.toMenu(context);
    } else {
      Routes.toBoardAfterGeneration(context);
    }
  }

  void _retry() {
    if (_launch) {
      _startLaunch();
      return;
    }
    _bar.value = 0;
    _controller!.retry();
    _watchGeneration();
    setState(() {});
  }

  void _back() {
    final c = _controller!;
    if (!_launch && c.loading != null) c.cancelGeneration();
    // pop, not maybePop: this screen's PopScope refuses a pop and sends it
    // here, so maybePop would loop.
    final nav = Navigator.of(context);
    if (nav.canPop()) nav.pop();
  }

  @override
  void dispose() {
    _minimum?.cancel();
    _controller?.removeListener(_onProgress);
    _bar.dispose();
    super.dispose();
  }

  Notice? get _failure =>
      _launch ? _launchFailure : _controller?.generationFailure?.notice;

  String get _label {
    if (_launch) return UiStrings.phaseLabel(GenerationPhase.ready);
    final status = _controller?.loading;
    return UiStrings.phaseLabel(status?.phase ?? GenerationPhase.generating);
  }

  @override
  Widget build(BuildContext context) {
    final failure = _failure;
    return PopScope(
      // Back during the launch splash leaves the app; during generation it
      // cancels and returns to whatever lies beneath.
      canPop: _launch,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: Material(
        type: MaterialType.transparency,
        child: DecoratedBox(
          decoration: const BoxDecoration(gradient: kSplashGradient),
          child: SafeArea(
            child: Center(
              child: SingleChildScrollView(
                child: MediaQuery.withNoTextScaling(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const RepaintBoundary(
                        child: AppMark(size: 132, interior: MarkInterior.board),
                      ),
                      const SizedBox(height: 30),
                      const Wordmark(size: 40),
                      const SizedBox(height: 14),
                      Text(
                        Copy.byline,
                        style: plexMono(
                          11,
                          scale: 1,
                          color: HsColors.muted,
                          letterSpacingEm: .28,
                        ),
                      ),
                      const SizedBox(height: 30),
                      _progressBar(),
                      const SizedBox(height: 30),
                      Text(
                        _label,
                        key: const ValueKey('loading-label'),
                        style: plexMono(
                          10,
                          scale: 1,
                          color: HsColors.labelDim,
                          letterSpacingEm: .2,
                        ),
                      ),
                      if (failure != null) ...[
                        const SizedBox(height: 24),
                        NoticeBanner(
                          key: const ValueKey('loading-notice'),
                          notice: failure,
                          scale: 1,
                          action: NoticeAction(Copy.tryAgain, _retry),
                        ),
                        if (!_launch) ...[
                          const SizedBox(height: 12),
                          SizedBox(
                            width: kPadWidth,
                            child: DesignButton.variant(
                              DesignButtonVariant.secondary,
                              key: const ValueKey('loading-back'),
                              scale: 1,
                              padding: const EdgeInsets.all(13),
                              onPressed: _back,
                              child: Text(
                                Copy.back,
                                style: outfit(
                                  13,
                                  scale: 1,
                                  weight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _progressBar() => AnimatedBuilder(
    animation: _bar,
    builder: (context, _) => Semantics(
      value: '${(_bar.value * 100).floor()}%',
      child: Container(
        key: const ValueKey('loading-bar'),
        width: 220,
        height: 5,
        decoration: BoxDecoration(
          color: HsColors.track,
          borderRadius: BorderRadius.circular(3),
        ),
        alignment: Alignment.centerLeft,
        child: FractionallySizedBox(
          widthFactor: _bar.value.clamp(0, 1),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(3),
              gradient: const LinearGradient(
                colors: [HsColors.teal, HsColors.blue],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
