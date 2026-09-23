// The player's data on the device: three small versioned JSON documents in
// the app's private directory.
//
// Each file is `{"v": <version>, "data": {...}}`. Writes go to `<name>.tmp`
// first and are renamed into place, so a kill mid-write leaves the old file.
// A file that cannot be read is renamed to `<name>.corrupt-<millis>` and read
// as corrupt, so nothing is silently lost and one damaged document never
// takes the others down. A file from a newer app version is left untouched
// and never overwritten until the app restarts.

import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:honest_sudoku/game/game.dart';

import 'codecs.dart';
import 'migrations.dart';
import 'store_result.dart';

export 'store_result.dart';

/// The three documents.
enum StoreDocument {
  /// `settings.json`.
  settings('settings.json'),

  /// `game.json`.
  game('game.json'),

  /// `stats.json`.
  stats('stats.json');

  const StoreDocument(this.fileName);

  /// The file's name.
  final String fileName;
}

/// The format version this app writes, per document.
const Map<StoreDocument, int> kStoreVersions = {
  StoreDocument.settings: 1,
  StoreDocument.game: 1,
  StoreDocument.stats: 1,
};

/// The largest file the store will read.
const int kMaxDocumentBytes = 256 * 1024;

/// A write refused because a newer app version owns the document.
final class StoreNewerVersion implements Exception {
  /// Creates the exception.
  const StoreNewerVersion(this.document, this.version);

  /// The document.
  final StoreDocument document;

  /// The version found on disk.
  final int version;

  @override
  String toString() =>
      'StoreNewerVersion: ${document.fileName} is v$version, newer than this '
      'app writes';
}

/// The store.
final class AppStore {
  /// A store over [root]. Prefer [open], which also tidies up.
  AppStore(
    this.root, {
    DateTime Function()? clock,
    void Function(String message)? log,
    this._versions = kStoreVersions,
    this._migrations = kMigrations,
  }) : _clock = clock ?? DateTime.now,
       _log = log ?? _defaultLog;

  /// Opens a store over [root], deleting any `.tmp` file an interrupted
  /// write left behind.
  static Future<AppStore> open(
    Directory root, {
    DateTime Function()? clock,
    void Function(String message)? log,
  }) async {
    final store = AppStore(root, clock: clock, log: log);
    if (await root.exists()) {
      await for (final entity in root.list()) {
        if (entity is File && entity.path.endsWith('.tmp')) {
          await entity.delete();
        }
      }
    }
    return store;
  }

  /// Where the files live.
  final Directory root;

  final DateTime Function() _clock;
  final void Function(String) _log;
  final Map<StoreDocument, int> _versions;
  final Map<String, Map<int, Migration>> _migrations;
  final Map<StoreDocument, Future<void>> _queues = {};
  final Set<StoreDocument> _newer = {};

  static void _defaultLog(String message) =>
      developer.log(message, name: 'honest_sudoku.store');

  // ---- typed documents ----------------------------------------------------

  /// The settings.
  Future<StoreResult<AppSettings>> readSettings() =>
      _read(StoreDocument.settings, decodeSettings);

  /// Saves the settings.
  Future<void> writeSettings(AppSettings s) =>
      _write(StoreDocument.settings, encodeSettings(s));

  /// The game in progress.
  Future<StoreResult<SavedGame>> readGame() =>
      _read(StoreDocument.game, decodeGame);

  /// Saves the game in progress.
  Future<void> writeGame(SavedGame g) =>
      _write(StoreDocument.game, encodeGame(g));

  /// Forgets the game in progress.
  Future<void> deleteGame() => _serial(StoreDocument.game, () async {
    if (_newer.contains(StoreDocument.game)) {
      throw StoreNewerVersion(StoreDocument.game, -1);
    }
    final f = _file(StoreDocument.game);
    if (await f.exists()) await f.delete();
  });

  /// The statistics.
  Future<StoreResult<StatsBook>> readStats() =>
      _read(StoreDocument.stats, decodeStats);

  /// Saves the statistics.
  Future<void> writeStats(StatsBook b) =>
      _write(StoreDocument.stats, encodeStats(b));

  // ---- the machinery ------------------------------------------------------

  File _file(StoreDocument d) => File('${root.path}/${d.fileName}');

  Future<R> _serial<R>(StoreDocument d, Future<R> Function() op) {
    final previous = _queues[d] ?? Future<void>.value();
    final result = previous.then((_) => op());
    _queues[d] = result.then((_) {}, onError: (Object _) {});
    return result;
  }

  Future<StoreResult<T>> _read<T>(
    StoreDocument d,
    T Function(Map<String, Object?>) decode,
  ) => _serial(d, () async {
    final file = _file(d);
    if (await FileSystemEntity.type(file.path) ==
        FileSystemEntityType.notFound) {
      return StoreResult<T>.absent();
    }
    try {
      if (await FileSystemEntity.isDirectory(file.path)) {
        throw const FormatException('a directory stands where the file goes');
      }
      final bytes = await file.length();
      if (bytes > kMaxDocumentBytes) {
        throw FormatException(
          '$bytes bytes is over the $kMaxDocumentBytes cap',
        );
      }
      final envelope = jsonDecode(await file.readAsString());
      if (envelope is! Map<String, Object?>) {
        throw const FormatException('not an object');
      }
      final v = envelope['v'];
      final data = envelope['data'];
      if (v is! int || data is! Map<String, Object?>) {
        throw const FormatException('no version or data');
      }
      final current = _versions[d]!;
      if (v > current) {
        _newer.add(d);
        _log('${d.fileName} is v$v; this app reads v$current. Left alone.');
        return StoreResult<T>.newer(v);
      }
      var migrated = data;
      if (v < current) {
        for (var from = v; from < current; from++) {
          final step = _migrations[d.fileName]?[from];
          if (step == null) {
            throw FormatException('no migration from v$from');
          }
          migrated = step(migrated);
        }
      }
      final value = decode(migrated);
      if (v < current) await _writeFile(d, migrated);
      return StoreResult.present(value);
    } on Object catch (e) {
      final reason = '$e';
      await _quarantine(file);
      _log('${d.fileName} is unreadable ($reason); set aside');
      return StoreResult<T>.corrupt(reason);
    }
  });

  Future<void> _quarantine(File file) async {
    try {
      await file.rename(
        '${file.path}.corrupt-${_clock().millisecondsSinceEpoch}',
      );
    } on Object catch (e) {
      _log('could not set ${file.path} aside: $e');
    }
  }

  Future<void> _write(StoreDocument d, Map<String, Object?> data) =>
      _serial(d, () async {
        if (_newer.contains(d)) {
          throw StoreNewerVersion(d, _versions[d]! + 1);
        }
        await _writeFile(d, data);
      });

  Future<void> _writeFile(StoreDocument d, Map<String, Object?> data) async {
    await root.create(recursive: true);
    final target = _file(d);
    final tmp = File('${target.path}.tmp');
    final sink = tmp.openWrite();
    sink.write(jsonEncode({'v': _versions[d], 'data': data}));
    await sink.flush();
    await sink.close();
    await tmp.rename(target.path);
  }
}
