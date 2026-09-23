// Route names, and the only helpers that navigate to the board or the menu.
//
// Screens never push `/board` or `/menu` themselves: the board is pushed once
// and returned to, never duplicated, and going to the menu clears the stack.
// Keeping those rules here is what makes them true everywhere.

import 'package:flutter/widgets.dart';

import 'app_scope.dart';

/// How the loading screen is being used.
enum LoadingMode {
  /// At launch, while saved data loads.
  launch,

  /// While a board is generated.
  generation,
}

/// Route names and navigation helpers.
abstract final class Routes {
  /// The main menu.
  static const menu = '/menu';

  /// New puzzle setup.
  static const setup = '/setup';

  /// The loading screen; the argument is a [LoadingMode].
  static const loading = '/loading';

  /// The board.
  static const board = '/board';

  /// Statistics.
  static const stats = '/stats';

  /// Settings.
  static const settings = '/settings';

  /// How to play.
  static const howto = '/howto';

  /// About the App.
  static const aboutApp = '/about-app';

  /// About Honest Arcade.
  static const aboutStudio = '/about-studio';

  /// Every route.
  static const all = [
    menu,
    setup,
    loading,
    board,
    stats,
    settings,
    howto,
    aboutApp,
    aboutStudio,
  ];

  /// A fresh board: replaces everything above the menu with the board, so the
  /// stack is `[menu, board]`.
  static void toBoardAfterGeneration(BuildContext context) => Navigator.of(
    context,
  ).pushNamedAndRemoveUntil(board, (route) => route.settings.name == menu);

  /// Back to the existing board (which lands paused), or to a new board
  /// route when there is none.
  static void toBoardPaused(BuildContext context) {
    final nav = Navigator.of(context);
    if (AppScope.of(context).routeNames.contains(board)) {
      nav.popUntil((route) => route.settings.name == board);
    } else {
      nav.pushNamed(board);
    }
  }

  /// The menu, with nothing beneath it.
  static void toMenu(BuildContext context) =>
      Navigator.of(context).pushNamedAndRemoveUntil(menu, (_) => false);

  /// The loading screen, generating.
  static void toLoadingForGeneration(BuildContext context) =>
      Navigator.of(context)
          .pushNamed(loading, arguments: LoadingMode.generation);
}

/// Tracks which named routes are on the stack.
final class RouteNames extends NavigatorObserver {
  final List<Route<dynamic>> _stack = [];

  /// Whether a route named [name] is on the stack.
  bool contains(String name) =>
      _stack.any((route) => route.settings.name == name);

  /// The names on the stack, bottom first.
  List<String?> get names => [for (final r in _stack) r.settings.name];

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _stack.add(route);

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _stack.remove(route);

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _stack.remove(route);

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    final i = oldRoute == null ? -1 : _stack.indexOf(oldRoute);
    if (i >= 0 && newRoute != null) {
      _stack[i] = newRoute;
    } else if (newRoute != null) {
      _stack.add(newRoute);
    }
  }
}
