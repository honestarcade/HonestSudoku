// A short tick when a number lands or clashes (#55), through Flutter's own
// haptic calls: no plugin and no permission. On Android they go through
// performHapticFeedback, which follows the phone's touch-feedback setting.

import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/services.dart';

/// The two ticks the game uses.
abstract class HapticsPort {
  /// A light tick: a number landed.
  Future<void> light();

  /// A firmer tick: a clash, a mistake, a solve or the last strike.
  Future<void> medium();
}

/// No ticks.
class NoHaptics implements HapticsPort {
  /// Creates the silent port.
  const NoHaptics();

  @override
  Future<void> light() async {}

  @override
  Future<void> medium() async {}
}

/// Ticks through [HapticFeedback]. A platform without haptics logs one line,
/// once, and stays quiet.
class FlutterHaptics implements HapticsPort {
  /// Creates the port.
  FlutterHaptics({void Function(String message)? log})
    : _log = log ?? _defaultLog;

  final void Function(String) _log;
  var _logged = false;

  static void _defaultLog(String message) =>
      developer.log(message, name: 'honest_sudoku.haptics');

  Future<void> _call(Future<void> Function() tick) async {
    try {
      await tick();
    } on MissingPluginException catch (e) {
      _once('no haptics: $e');
    } on PlatformException catch (e) {
      _once('haptics failed: $e');
    }
  }

  void _once(String message) {
    if (_logged) return;
    _logged = true;
    _log(message);
  }

  @override
  Future<void> light() => _call(HapticFeedback.lightImpact);

  @override
  Future<void> medium() => _call(HapticFeedback.mediumImpact);
}
