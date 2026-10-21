import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

/// The page each comic was left at (IMG-017). A file name and folder say what
/// a person reads, so the books are not named here: each is kept under the
/// SHA-256 of its address, in a file of its own that is not part of the
/// settings (so not in a settings export) and sits in a folder Android leaves
/// out of backups and device transfers (`photos-private`).
class ReaderPositions {
  ReaderPositions({Future<Directory> Function()? directory})
    : _directory = directory ?? getApplicationSupportDirectory;

  final Future<Directory> Function() _directory;

  /// Folder under the app's files that backups skip.
  static const String folder = 'photos-private';

  /// How many books keep their place.
  static const int remembered = 50;

  /// What a book is called in the file.
  static String keyOf(String book) =>
      sha256.convert(utf8.encode(book)).toString();

  Future<File> _file() async => File(
    '${(await _directory()).path}${Platform.pathSeparator}$folder'
    '${Platform.pathSeparator}reader-positions.json',
  );

  // One write at a time, in order.
  Future<void> _queue = Future<void>.value();

  Future<Map<String, int>> _read() async {
    try {
      final f = await _file();
      if (!f.existsSync()) return {};
      final j = jsonDecode(await f.readAsString());
      if (j is! Map) return {};
      return {
        for (final e in j.entries)
          if (e.key is String && e.value is int)
            e.key as String: e.value as int,
      };
    } on Object {
      return {};
    }
  }

  /// The page [book] was left at, or 0.
  Future<int> page(String book) async {
    await _queue;
    return (await _read())[keyOf(book)] ?? 0;
  }

  /// Remembers [page] for [book]; the oldest places are forgotten.
  Future<void> save(String book, int page) => _queue = _queue.then((_) async {
    try {
      final all = await _read()
        ..remove(keyOf(book))
        ..[keyOf(book)] = page;
      while (all.length > remembered) {
        all.remove(all.keys.first);
      }
      final f = await _file();
      await f.parent.create(recursive: true);
      final tmp = File('${f.path}.tmp');
      await tmp.writeAsString(jsonEncode(all), flush: true);
      await tmp.rename(f.path);
    } on Object {
      // A place that is not remembered costs a page turn, nothing more.
    }
  });
}

/// Where comic positions are kept; tests replace it.
final Provider<ReaderPositions> readerPositionsProvider =
    Provider<ReaderPositions>((ref) => ReaderPositions());
