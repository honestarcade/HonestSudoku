// The board screen: every piece on the design's 390×844 frame, scaled to the
// phone.
//
// The frame is scaled by `min(width / 390, height / 844, 430 / 390)` and
// centred; the screen gradient fills the whole phone behind it. The frame's
// own 44-point status band absorbs the phone's top inset, and when the inset
// is taller the frame moves down by the difference (and the scale shrinks to
// keep the bottom on screen). The cards size to the whole phone.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:honest_sudoku/game/game.dart';

import '../loading_placeholder.dart';
import '../placeholder_screen.dart';
import '../strings.dart';
import '../theme/board_theme.dart';
import 'board_grid.dart';
import 'board_layout.dart';
import 'board_overlays.dart';
import 'game_controller.dart';
import 'notice_banner.dart';
import 'number_pad.dart';
import 'tool_bar.dart';
import 'top_bar.dart';

/// The largest frame scale: the frame never grows past 430 points wide.
const double kMaxFrameScale = 430 / kFrameWidth;

/// The frame's scale and vertical offset for a [size] with a [topInset].
///
/// The frame's 44-point band absorbs the inset. When the inset is taller,
/// the frame moves down by the excess, and the scale is solved so the frame
/// still ends at the bottom: `top + 800 × scale = height`.
({double scale, double top}) frameGeometry(Size size, double topInset) {
  final widthBound = size.width / kFrameWidth;
  final fit = math.min(
    math.min(widthBound, size.height / kFrameHeight),
    kMaxFrameScale,
  );
  if (topInset <= kTopBarY * fit) return (scale: fit, top: 0);
  final scale = math.min(
    math.min(widthBound, (size.height - topInset) / (kFrameHeight - kTopBarY)),
    kMaxFrameScale,
  );
  return (scale: scale, top: topInset - kTopBarY * scale);
}

/// The board screen.
class BoardScreen extends StatefulWidget {
  /// Creates the screen over [controller].
  const BoardScreen({
    required this.controller,
    required this.routeObserver,
    super.key,
  });

  /// Owns the game.
  final GameController controller;

  /// Tells the screen when another route covers it.
  final RouteObserver<ModalRoute<void>> routeObserver;

  @override
  State<BoardScreen> createState() => _BoardScreenState();
}

class _BoardScreenState extends State<BoardScreen> with RouteAware {
  GameController get _c => widget.controller;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route != null) widget.routeObserver.subscribe(this, route);
  }

  @override
  void dispose() {
    widget.routeObserver.unsubscribe(this);
    super.dispose();
  }

  @override
  void didPush() => _c.enterBoard();

  @override
  void didPushNext() => _c.setBoardVisible(false);

  @override
  void didPopNext() => _c.enterBoard();

  void _goTo(String destination) {
    // Leaving the board pauses the game, so time does not run behind the
    // placeholder and the card is waiting on the way back.
    final s = _c.state;
    if (s != null && !s.won && !s.lost) _c.pause();
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PlaceholderScreen(destination: destination),
      ),
    );
  }

  void _onBack() {
    if (_c.loading != null) {
      _c.cancelGeneration();
      return;
    }
    final s = _c.state;
    if (s == null) return;
    if (s.won || s.lost || s.paused) {
      _goTo(UiStrings.mainMenu);
    } else {
      _c.pause();
    }
  }

  @override
  Widget build(BuildContext context) => AnnotatedRegion<SystemUiOverlayStyle>(
    value: SystemUiOverlayStyle.light,
    child: PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _onBack();
      },
      child: Material(
        type: MaterialType.transparency,
        child: DecoratedBox(
          decoration: const BoxDecoration(gradient: kScreenGradient),
          child: SafeArea(
            top: false,
            child: LayoutBuilder(
              builder: (context, box) => ListenableBuilder(
                listenable: _c,
                builder: (context, _) => _content(context, box.biggest),
              ),
            ),
          ),
        ),
      ),
    ),
  );

  Widget _content(BuildContext context, Size size) {
    final geo = frameGeometry(size, MediaQuery.paddingOf(context).top);
    final s = geo.scale;
    final state = _c.state;
    if (state == null || _c.loading != null) {
      return LoadingPlaceholder(
        status: _c.loading,
        failure: _c.generationFailure,
        scale: s,
        onRetry: _c.retry,
      );
    }
    return SizedBox.expand(
      child: BoardOverlays(
        state: state,
        stats: _c.stats,
        scale: s,
        onResume: _c.resume,
        onRestart: _c.restart,
        onNewDeal: _c.newDeal,
        onRules: () => _goTo(UiStrings.rules),
        onSettings: () => _goTo(UiStrings.settings),
        onMainMenu: () => _goTo(UiStrings.mainMenu),
        onChangeSetup: () => _goTo(UiStrings.newPuzzle),
        board: (_) => Stack(
          children: [
            Positioned(
              left: (size.width - kFrameWidth * s) / 2,
              top: geo.top,
              width: kFrameWidth * s,
              height: kFrameHeight * s,
              child: _frame(state, s),
            ),
          ],
        ),
      ),
    );
  }

  Widget _frame(GameState state, double s) {
    final grid = ScaledGrid(BoardLayout.of(state.shape), s);
    final failure = _c.generationFailure;
    final notice = failure?.notice ?? state.notice;
    final noticeY = kGridY * s + grid.gridPx + 12 * s;
    final padY = noticeY + (notice == null ? 0 : kNoticeShift * s);
    return Stack(
      key: const ValueKey('board-frame'),
      children: [
        Positioned(
          left: 0,
          top: kTopBarY * s,
          child: TopBar(
            title: state.boardTitle,
            elapsedSeconds: state.elapsedSeconds,
            mistakes: state.mistakes,
            strikeMode: state.settings.strikeMode,
            showTimer: state.settings.showTimer,
            isOver: state.won || state.lost,
            scale: s,
            onPause: _c.pause,
          ),
        ),
        Positioned(
          left: grid.gridX,
          top: kGridY * s,
          child: BoardGrid(
            state: state,
            theme: _c.theme,
            scale: s,
            onTapCell: _c.select,
          ),
        ),
        if (notice != null)
          Positioned(
            left: kSideInset * s,
            top: noticeY,
            child: NoticeBanner(
              notice: notice,
              scale: s,
              action: failure == null
                  ? null
                  : NoticeAction(UiStrings.tryAgain, _c.retry),
            ),
          ),
        Positioned(
          left: kSideInset * s,
          top: padY,
          child: NumberPad(
            key: const ValueKey('pad'),
            state: state,
            scale: s,
            onPlace: _c.place,
            onErase: _c.erase,
          ),
        ),
        Positioned(
          left: 0,
          top: kToolBarY * s,
          child: ToolBar(
            key: const ValueKey('tools'),
            state: state,
            scale: s,
            onUndo: _c.undo,
            onRedo: _c.redo,
            onToggleNotes: _c.toggleNotes,
            onErase: _c.erase,
            onHint: _c.hint,
            onCheck: _c.check,
          ),
        ),
      ],
    );
  }
}
