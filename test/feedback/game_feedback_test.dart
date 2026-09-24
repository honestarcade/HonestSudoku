import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:honest_sudoku/engine/engine.dart';
import 'package:honest_sudoku/feedback/game_feedback.dart';
import 'package:honest_sudoku/game/game.dart';
import 'package:honest_sudoku/store/app_store.dart';
import 'package:honest_sudoku/ui/board/game_controller.dart';

import '../game/fixtures.dart';
import '../ui/stub_generator.dart';

/// Records what would have played.
final class RecordingPlayer implements SoundPlayer {
  final loaded = <Map<FeedbackEvent, String>>[];
  final played = <FeedbackEvent>[];

  @override
  Future<void> load(Map<FeedbackEvent, String> assets) async =>
      loaded.add(assets);

  @override
  void play(FeedbackEvent e) => played.add(e);

  @override
  Future<void> dispose() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final controllers = <GameController>[];
  tearDown(() {
    for (final c in controllers) {
      c.dispose();
    }
    controllers.clear();
  });

  /// A controller on the 9×9 fixture (givens on even cells) with the
  /// feedback attached, and the player it plays through.
  Future<(GameController, GameFeedback, RecordingPlayer)> playing({
    StrikeMode strike = StrikeMode.three,
    AnnounceMode announce = AnnounceMode.now,
    bool sfx = true,
    Future<AppStore?> Function()? store,
  }) async {
    final c = GameController(
      generator: StubGenerator().call,
      seeds: CountingSeeds(),
      store: store,
      settings: AppSettings(
        sfx: sfx,
        lastSetup: LastSetup(strikeMode: strike, announce: announce),
      ),
      log: (_) {},
    );
    controllers.add(c);
    final player = RecordingPlayer();
    final feedback = GameFeedback(player: player, log: (_) {});
    await feedback.attach(c);
    if (store == null) {
      c.startNew(GridShape.classic, Difficulty.medium);
      await c.generationDone;
    }
    return (c, feedback, player);
  }

  void enter(GameController c, int cell, int value) {
    c.select(cell);
    c.place(value);
  }

  int wrong(GameController c, int cell) => c.state!.solution[cell] % 9 + 1;

  test('a correct placement clicks', () async {
    final (c, f, p) = await playing();
    enter(c, 1, c.state!.solution[1]);
    expect(p.played, [FeedbackEvent.place]);
    expect(f.lastEvent, FeedbackEvent.place);
  });

  test('a wrong placement, announced at once, thuds and only thuds', () async {
    final (c, f, p) = await playing();
    enter(c, 1, wrong(c, 1));
    expect(p.played, [FeedbackEvent.mistake]);
    expect(f.clash, isTrue);
  });

  test('At the end: a wrong placement clicks, never thuds', () async {
    final (c, _, p) = await playing(announce: AnnounceMode.atEnd);
    enter(c, 1, wrong(c, 1));
    expect(c.state!.mistakes, 1, reason: 'the mistake still counts');
    expect(p.played, [FeedbackEvent.place]);
  });

  test('Zen: a wrong placement clicks', () async {
    final (c, _, p) = await playing(strike: StrikeMode.zen);
    enter(c, 1, wrong(c, 1));
    expect(p.played, [FeedbackEvent.place]);
  });

  test('the winning placement plays only the solve cue', () async {
    final (c, _, p) = await playing();
    final empty = [for (var i = 1; i < 81; i += 2) i];
    for (final i in empty) {
      enter(c, i, c.state!.solution[i]);
    }
    expect(c.state!.won, isTrue);
    expect(p.played.last, FeedbackEvent.solve);
    expect(
      p.played.where((e) => e == FeedbackEvent.place),
      hasLength(empty.length - 1),
      reason: 'the last entry does not click as well',
    );
  });

  test('the last strike plays only its cue', () async {
    final (c, _, p) = await playing();
    for (final i in [1, 3, 5]) {
      enter(c, i, wrong(c, i));
    }
    expect(c.state!.lost, isTrue);
    expect(p.played, [
      FeedbackEvent.mistake,
      FeedbackEvent.mistake,
      FeedbackEvent.lastStrike,
    ]);
    expect(FeedbackEvent.lastStrike.clip, 'lose');
  });

  test('erase, undo, redo, a note, a same-value clear and a given tap are '
      'silent', () async {
    final (c, f, p) = await playing();
    enter(c, 1, c.state!.solution[1]);
    p.played.clear();
    c.erase();
    c.undo();
    c.redo();
    c.undo();
    expect(c.state!.selected, 1);
    c.place(c.state!.values[1]); // the same value clears
    expect(c.state!.values[1], 0);
    c.toggleNotes();
    c.select(3);
    c.place(2); // a pencil mark
    expect(c.state!.notes[3], [2]);
    c.toggleNotes();
    c.select(0);
    c.place(wrong(c, 0)); // a given refuses
    expect(p.played, isEmpty);
    expect(f.lastEvent, isNull);
  });

  test('with Sound effects off nothing plays, but the event is still '
      'derived', () async {
    final (c, f, p) = await playing(sfx: false);
    enter(c, 1, wrong(c, 1));
    expect(p.played, isEmpty);
    expect(f.lastEvent, FeedbackEvent.mistake);
  });

  test('switching Sound effects on clicks once; off plays nothing', () async {
    final (c, _, p) = await playing(sfx: false);
    c.updateSettings(c.settings.copyWith(sfx: true));
    expect(p.played, [FeedbackEvent.place]);
    c.updateSettings(c.settings.copyWith(sfx: false));
    c.updateSettings(c.settings.copyWith(themeKey: 'paper'));
    expect(p.played, [FeedbackEvent.place]);
  });

  test('restoring a saved game at launch is silent', () async {
    final dir = Directory.systemTemp.createTempSync('hs-feedback-');
    addTearDown(() => dir.deleteSync(recursive: true));
    final store = await AppStore.open(dir, log: (_) {});
    final s = GameState.start(classic).select(1).place(classic.solution[1]);
    await store.writeGame(SavedGame.fromState(s));
    final (c, f, p) = await playing(store: () async => store);
    await c.load();
    expect(c.state!.moves, 1, reason: 'the game was restored');
    expect(p.played, isEmpty);
    expect(f.lastEvent, isNull);
  });

  group('clips', () {
    test('the real clip beats its placeholder; neither is logged', () {
      final logged = <String>[];
      final clips = resolveClips({
        'assets/audio/place.wav',
        'assets/audio/placeholder-place.wav',
        'assets/audio/placeholder-mistake.wav',
        'assets/audio/placeholder-solve.wav',
      }, logged.add);
      expect(clips, {
        FeedbackEvent.place: 'assets/audio/place.wav',
        FeedbackEvent.mistake: 'assets/audio/placeholder-mistake.wav',
        FeedbackEvent.solve: 'assets/audio/placeholder-solve.wav',
      });
      expect(logged.single, contains('lose'));
    });

    test('attach loads what the manifest resolves', () async {
      final c = GameController(generator: StubGenerator().call, log: (_) {});
      controllers.add(c);
      final player = RecordingPlayer();
      await GameFeedback(
        player: player,
        manifest: () async => {'assets/audio/placeholder-lose.wav'},
        log: (_) {},
      ).attach(c);
      expect(player.loaded.single, {
        FeedbackEvent.lastStrike: 'assets/audio/placeholder-lose.wav',
      });
    });
  });

  group('the channel player', () {
    const channel = MethodChannel('test/sound');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    tearDown(() => messenger.setMockMethodCallHandler(channel, null));

    test('sends load, then play by clip name; release on dispose', () async {
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return call.method == 'load' ? 1 : null;
      });
      final player = ChannelSoundPlayer(channel: channel, log: (_) {});
      player.play(FeedbackEvent.place); // before load: dropped
      await player.load({
        FeedbackEvent.lastStrike: 'assets/audio/placeholder-lose.wav',
      });
      player.play(FeedbackEvent.lastStrike);
      await player.dispose();
      await Future<void>.delayed(Duration.zero);
      expect(calls.map((c) => c.method), ['load', 'play', 'release']);
      expect(calls[0].arguments, {'lose': 'assets/audio/placeholder-lose.wav'});
      expect(calls[1].arguments, 'lose');
    });

    test(
      'a load that throws leaves a silent player that never throws',
      () async {
        var plays = 0;
        messenger.setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'load') throw PlatformException(code: 'none');
          plays++;
          return null;
        });
        final logged = <String>[];
        final player = ChannelSoundPlayer(channel: channel, log: logged.add);
        await player.load({FeedbackEvent.place: 'x'});
        player.play(FeedbackEvent.place);
        await player.dispose();
        expect(plays, 0);
        expect(logged, hasLength(1));
      },
    );

    test('no handler at all (tests, no Android) is the same silence', () async {
      final logged = <String>[];
      final player = ChannelSoundPlayer(channel: channel, log: logged.add);
      await player.load({FeedbackEvent.place: 'x'});
      player.play(FeedbackEvent.place);
      expect(logged.single, contains('no player'));
    });
  });
}
