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

import '../a11y/labels.dart';
import '../routes.dart';
import '../strings.dart';
import '../theme/board_theme.dart';
import '../widgets/tap_target.dart';
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

  /// Leaves for another screen over the board. A live game pauses first, so
  /// no time runs behind the other screen and the card waits on the return.
  void _push(String route) {
    final s = _c.state;
    if (s != null && !s.won && !s.lost) _c.pause();
    Navigator.of(context).pushNamed(route);
  }

  void _mainMenu() {
    final s = _c.state;
    if (s != null && !s.won && !s.lost) _c.pause();
    Routes.toMenu(context);
  }

  void _newDeal() {
    _c.newDeal();
    Routes.toLoadingForGeneration(context);
  }

  void _onBack() {
    final s = _c.state;
    if (s == null) return;
    if (s.won || s.lost || s.paused) {
      _mainMenu();
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
    if (state == null) return const SizedBox.expand();
    // The phone's font size reaches everything but the grid, up to 1.3×
    // (owner, 2026-09-19); the grid is geometry and ignores it (#53).
    final scaled = MediaQuery.of(context).copyWith(
      textScaler: MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.3),
    );
    return MediaQuery(
      data: scaled,
      child: SizedBox.expand(
        // One live region over board and cards alike, so pausing, winning
        // and losing each change its label and TalkBack speaks the title.
        child: _live(state, s, geo, size),
      ),
    );
  }

  Widget _live(
    GameState state,
    double s,
    ({double scale, double top}) geo,
    Size size,
  ) => Semantics(
    key: const ValueKey('overlay-live'),
    container: true,
    liveRegion: true,
    label: overlayAnnouncement(state),
    child: BoardOverlays(
      state: state,
      stats: _c.stats,
      scale: s,
      onResume: _c.resume,
      onRestart: _c.restart,
      onNewDeal: _newDeal,
      onRules: () => _push(Routes.howto),
      onSettings: () => _push(Routes.settings),
      onMainMenu: _mainMenu,
      onChangeSetup: () => _push(Routes.setup),
      board: (inner) => Stack(
        children: [
          Positioned(
            left: (size.width - kFrameWidth * s) / 2,
            top: geo.top,
            width: kFrameWidth * s,
            height: kFrameHeight * s,
            child: _frame(inner, state, s),
          ),
        ],
      ),
    ),
  );

  Widget _frame(BuildContext context, GameState state, double s) {
    final layout = BoardLayout.of(state.shape);
    final grid = ScaledGrid(layout, s);
    final notice = state.notice;
    final noticeY = kGridY * s + grid.gridPx + 12 * s;
    // The banner is measured before layout: its height places the pad, and
    // a three-line banner that would push the pad into the tools gets two.
    var noticeLines = 3;
    var noticeHeight = 0.0;
    if (notice != null) {
      final scaler = MediaQuery.textScalerOf(context);
      double measure(int lines) => NoticeBanner.measureHeight(
        notice: notice,
        scale: s,
        textScaler: scaler,
        maxLines: lines,
      );
      noticeHeight = measure(3);
      noticeLines = layout.noticeMaxLines(noticeHeight / s);
      if (noticeLines < 3) noticeHeight = measure(noticeLines);
    }
    final padY =
        noticeY +
        (layout.padY(noticeHeight: noticeHeight / s) - layout.noticeY) * s;
    return Stack(
      key: const ValueKey('board-frame'),
      children: [
        _outset(
          left: 0,
          top: kTopBarY * s,
          child: TopBar(
            title: state.boardTitle,
            pauseSemantics: pauseLabel(
              state.shape.label,
              state.difficulty.label,
            ),
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
          child: MediaQuery.withNoTextScaling(
            child: BoardGrid(
              state: state,
              theme: _c.theme,
              scale: s,
              onTapCell: _c.select,
            ),
          ),
        ),
        // Always present, so every new notice is a label change on the same
        // live region; an empty label while there is none.
        Positioned(
          left: kSideInset * s,
          top: noticeY,
          child: Semantics(
            key: const ValueKey('notice-live'),
            container: true,
            liveRegion: true,
            label: notice == null ? '' : noticeLabel(notice.tag, notice.body),
            child: notice == null
                ? SizedBox(width: kPadWidth * s, height: 1)
                : NoticeBanner(
                    notice: notice,
                    scale: s,
                    labelled: false,
                    maxLines: noticeLines,
                  ),
          ),
        ),
        _outset(
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
        _outset(
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

/// [child] at ([left], [top]) with room around it for its controls' 48-dp
/// tap targets (#56): a hit in a key's grown margin must reach the key, and a
/// parent rejects any hit outside its own box. Painting does not move.
Positioned _outset({
  required double left,
  required double top,
  required Widget child,
}) {
  const m = kMinTapTarget / 2;
  return Positioned(
    left: left - m,
    top: top - m,
    child: TapTargetGroup(
      child: Padding(padding: const EdgeInsets.all(m), child: child),
    ),
  );
}

/// What the overlays' live region says: the card's title, or nothing while
/// the board shows.
String overlayAnnouncement(GameState s) {
  if (s.won) return overlayTitleLabel(UiStrings.wonTag, UiStrings.wonTitle);
  if (s.lost) return overlayTitleLabel(UiStrings.lostTag, UiStrings.lostTitle);
  if (s.paused) return overlayTitleLabel(null, UiStrings.paused);
  return '';
}
