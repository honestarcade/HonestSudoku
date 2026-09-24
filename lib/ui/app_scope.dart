// What every screen reaches for: the controller, the route observers, the
// link opener and the build's version. Handed down once from the app root.

import 'package:flutter/widgets.dart';

import '../build_info.dart';
import 'board/game_controller.dart';
import 'link_opener.dart';
import 'routes.dart';

/// The app's shared objects.
class AppScope extends InheritedWidget {
  /// Creates the scope.
  const AppScope({
    required this.controller,
    required this.routeNames,
    required this.routeObserver,
    required this.links,
    required this.buildInfo,
    required super.child,
    super.key,
  });

  /// The game controller.
  final GameController controller;

  /// Which routes are on the stack.
  final RouteNames routeNames;

  /// Tells screens when they are covered and uncovered.
  final RouteObserver<ModalRoute<void>> routeObserver;

  /// Opens links in the browser.
  final LinkOpener links;

  /// The build's version.
  final BuildInfo buildInfo;

  /// The nearest scope.
  static AppScope of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'no AppScope above this widget');
    return scope!;
  }

  @override
  bool updateShouldNotify(AppScope old) =>
      old.controller != controller ||
      old.links != links ||
      old.buildInfo != buildInfo;
}
