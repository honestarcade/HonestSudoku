// The shipped app with the Flutter Driver extension, for the end-to-end
// suite (#66): lib/main.dart's own main(), so the real store under the app's
// sandbox, the isolate generator, random seeds, the sound channel and the
// platform's lifecycle are all the composition root's defaults — nothing is
// injected. test_driver/app_flow_test.dart drives it through tools/e2e.sh;
// never shipped (the release build's target is lib/main.dart).
//
// The handler only reads: the running game as the controller holds it, the
// colours the board's cells were built with, and the text under a key.
// Every change the suite makes is a tap.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_driver/driver_extension.dart';
import 'package:honest_sudoku/main.dart' as app;
import 'package:honest_sudoku/ui/app_scope.dart';
import 'package:honest_sudoku/ui/board/game_controller.dart';
import 'package:honest_sudoku/ui/theme/board_theme.dart';

/// The app's controller, found in the element tree (no seam in lib/).
GameController? _controller() {
  GameController? found;
  void visit(Element e) {
    if (found != null) return;
    final w = e.widget;
    if (w is AppScope) {
      found = w.controller;
      return;
    }
    e.visitChildren(visit);
  }

  WidgetsBinding.instance.rootElement?.visitChildren(visit);
  return found;
}

/// The first mounted element whose widget has [key].
Element? _keyed(Key key) {
  Element? found;
  void visit(Element e) {
    if (found != null) return;
    if (e.widget.key == key) {
      found = e;
      return;
    }
    e.visitChildren(visit);
  }

  WidgetsBinding.instance.rootElement?.visitChildren(visit);
  return found;
}

/// Every string drawn under the widget keyed [key], in tree order.
List<String> _texts(String key) {
  final out = <String>[];
  void visit(Element e) {
    final w = e.widget;
    if (w is Text) {
      out.add(w.data ?? w.textSpan?.toPlainText() ?? '');
    } else if (w is RichText) {
      out.add(w.text.toPlainText());
    }
    e.visitChildren(visit);
  }

  final root = _keyed(ValueKey<String>(key));
  if (root != null) visit(root);
  return out;
}

/// The background each listed cell was built with, as ARGB.
Map<String, int?> _cellColours(List<int> cells) => {
  for (final i in cells)
    '$i': switch (_keyed(ValueKey<String>('cell-$i'))?.widget) {
      DecoratedBox(:final BoxDecoration decoration) =>
        decoration.color?.toARGB32(),
      _ => null,
    },
};

Map<String, Object?> _theme(BoardTheme t) => {
  'key': t.key,
  'cellBg': t.cellBg.toARGB32(),
  'peerBg': t.peerBg.toARGB32(),
  'selBg': t.selBg.toARGB32(),
};

Map<String, Object?> _state() {
  final c = _controller();
  final s = c?.state;
  return {
    'ready': c != null,
    'loading': c?.loading != null,
    'themeKey': c?.themeKey,
    'hlUnit': c?.settings.game.hlUnit,
    'unfinished': c?.hasUnfinishedGame,
    if (s != null) ...{
      'shape': s.shape.label,
      'difficulty': s.difficulty.key,
      'seed': s.puzzle.seed,
      'n': s.n,
      'values': s.values,
      'solution': s.solution,
      'givens': s.puzzle.givens,
      'notes': s.notes,
      'selected': s.selected,
      'noteMode': s.noteMode,
      'mistakes': s.mistakes,
      'elapsed': s.elapsedSeconds,
      'paused': s.paused,
      'won': s.won,
      'lost': s.lost,
    },
  };
}

/// `generated:<seconds>` waits on the controller's own generationDone.
Future<Map<String, Object?>> _generated(int seconds) async {
  final c = _controller();
  if (c == null) return {'ok': false, 'error': 'no controller'};
  try {
    await c.generationDone.timeout(Duration(seconds: seconds));
    return {'ok': true};
  } on TimeoutException {
    return {'ok': false, 'error': 'no board within $seconds s'};
  } on Object catch (e) {
    return {'ok': false, 'error': '$e'};
  }
}

Future<String> _answer(String? request) async {
  final r = request ?? '';
  final arg = r.contains(':') ? r.substring(r.indexOf(':') + 1) : '';
  return jsonEncode(switch (r.split(':').first) {
    'state' => _state(),
    'generated' => await _generated(int.parse(arg)),
    'texts' => _texts(arg),
    'cells' => _cellColours([for (final i in arg.split(',')) int.parse(i)]),
    'themes' => {
      'navy': _theme(BoardTheme.navy),
      'paper': _theme(BoardTheme.paper),
    },
    _ => throw ArgumentError.value(request, 'request', 'unknown'),
  });
}

Future<void> main() async {
  enableFlutterDriverExtension(handler: _answer);
  await app.main();
}
