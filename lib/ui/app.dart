// The app's root: the controller, the route table, and what every screen
// shares. The loading screen covers the store opening at launch, then hands
// over to the menu.

import 'package:flutter/material.dart';
import 'package:honest_sudoku/game/game.dart';
import 'package:honest_sudoku/store/app_store.dart';
import 'package:honest_sudoku/store/store_directory.dart';

import '../build_info.dart';
import 'app_scope.dart';
import 'board/board_screen.dart';
import 'board/game_controller.dart';
import 'link_opener.dart';
import 'routes.dart';
import 'screens/about_app_screen.dart';
import 'screens/about_studio_screen.dart';
import 'screens/howto_screen.dart';
import 'screens/loading_screen.dart';
import 'screens/menu_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/setup_screen.dart';
import 'screens/stats_screen.dart';
import 'theme/tokens.dart';

Future<AppStore> _openStore() async => AppStore.open(await storeDirectory());

/// The app.
class HonestSudokuApp extends StatefulWidget {
  /// Creates the app. Every parameter replaces a real dependency, for tests.
  const HonestSudokuApp({
    this.store,
    this.generator,
    this.seeds,
    this.links,
    this.buildInfo,
    this.initialRoute = Routes.loading,
    super.key,
  });

  /// Opens the store; production resolves the app's private directory. A
  /// factory that yields null runs without persistence (widget tests).
  final Future<AppStore?> Function()? store;

  /// Replaces the isolate generator.
  final BoardGenerator? generator;

  /// Replaces the random seed source.
  final SeedSource? seeds;

  /// Replaces the browser link opener.
  final LinkOpener? links;

  /// Replaces the build's version.
  final BuildInfo? buildInfo;

  /// Where the app opens: the launch splash.
  final String initialRoute;

  @override
  State<HonestSudokuApp> createState() => _HonestSudokuAppState();
}

class _HonestSudokuAppState extends State<HonestSudokuApp> {
  late final GameController _controller = GameController(
    generator: widget.generator,
    seeds: widget.seeds,
    store: widget.store ?? _openStore,
  );
  final _routeNames = RouteNames();
  final _routeObserver = RouteObserver<ModalRoute<void>>();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Route<void> _page(RouteSettings settings, Widget screen) =>
      PageRouteBuilder<void>(
        settings: settings,
        transitionDuration: const Duration(milliseconds: 150),
        reverseTransitionDuration: const Duration(milliseconds: 150),
        pageBuilder: (_, _, _) => screen,
        transitionsBuilder: (_, animation, _, child) =>
            FadeTransition(opacity: animation, child: child),
      );

  Route<void> _route(RouteSettings settings) => switch (settings.name) {
    Routes.loading => _page(
      settings,
      LoadingScreen(
        mode: settings.arguments as LoadingMode? ?? LoadingMode.launch,
      ),
    ),
    Routes.setup => _page(settings, const SetupScreen()),
    // No game to show: the board route is setup instead.
    Routes.board when _controller.state == null => _page(
      const RouteSettings(name: Routes.setup),
      const SetupScreen(),
    ),
    Routes.board => _page(
      settings,
      BoardScreen(controller: _controller, routeObserver: _routeObserver),
    ),
    Routes.stats => _page(settings, const StatsScreen()),
    Routes.settings => _page(settings, const SettingsScreen()),
    Routes.howto => _page(settings, const HowToScreen()),
    Routes.aboutApp => _page(settings, const AboutAppScreen()),
    Routes.aboutStudio => _page(settings, const AboutStudioScreen()),
    _ => _page(const RouteSettings(name: Routes.menu), const MenuScreen()),
  };

  // Outfit for any text without a style of its own, with the system font
  // behind it for the symbols Outfit lacks.
  static final _theme = () {
    final base = ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: HsColors.navy,
      fontFamily: kFontOutfit,
    );
    return base.copyWith(
      textTheme: base.textTheme.apply(fontFamilyFallback: kFontFallback),
    );
  }();

  @override
  Widget build(BuildContext context) => AppScope(
    controller: _controller,
    routeNames: _routeNames,
    routeObserver: _routeObserver,
    links: widget.links ?? const UrlLauncherLinkOpener(),
    buildInfo: widget.buildInfo ?? BuildInfo.current,
    child: MaterialApp(
      title: 'Honest Sudoku',
      debugShowCheckedModeBanner: false,
      theme: _theme,
      navigatorObservers: [_routeNames, _routeObserver],
      onGenerateInitialRoutes: (_) => [
        _route(
          RouteSettings(
            name: widget.initialRoute,
            arguments: widget.initialRoute == Routes.loading
                ? LoadingMode.launch
                : null,
          ),
        ),
      ],
      onGenerateRoute: _route,
      onUnknownRoute: (settings) =>
          _route(const RouteSettings(name: Routes.menu)),
    ),
  );
}
