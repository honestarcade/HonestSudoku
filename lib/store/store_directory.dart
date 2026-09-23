// Where the store lives: `honest_sudoku/` inside the app's private documents
// directory. The only place path_provider is used; everything else is handed
// the Directory this returns.

import 'dart:io';

import 'package:path_provider/path_provider.dart';

Future<Directory>? _directory;

/// The store's directory, created on first use. Resolved once per launch;
/// a failure is rethrown to the caller (the loading screen shows it).
Future<Directory> storeDirectory() => _directory ??= _resolve();

Future<Directory> _resolve() async {
  final docs = await getApplicationDocumentsDirectory();
  final dir = Directory('${docs.path}/honest_sudoku');
  await dir.create(recursive: true);
  return dir;
}
