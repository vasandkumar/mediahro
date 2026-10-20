import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:mediahro/core/db/library_database.dart';
import 'package:mediahro/features/music/tags/audio_tags.dart';

/// Where a cover came from (MUS-004: embedded first, then folder art; the
/// online lookup is opt-in and arrives with the network features).
enum ArtSource { embedded, folder }

/// Cover art cache for music (MUS-004). Each distinct image is stored once
/// (content-addressed), so an album's tracks share one file; the `artwork`
/// table maps items to it (`owner_type = 'item'`, `role = 'cover'`).
final class ArtworkStore {
  ArtworkStore(this.db, this.directory);

  final LibraryDatabase db;

  /// `<app data>/music/art`.
  final Directory directory;
  final _memo = <int, String?>{};

  /// Folder-art file names, most specific first.
  static final folderArtPattern = RegExp(
    r'^(cover|folder|front|albumart|album|albumartsmall|thumb)\.(jpe?g|png|webp)$',
    caseSensitive: false,
  );

  /// Picks the best folder-art file name among [names], or null.
  static String? pickFolderArt(Iterable<String> names) {
    final matches = names.where(folderArtPattern.hasMatch).toList()
      ..sort((a, b) => _rank(a).compareTo(_rank(b)));
    return matches.isEmpty ? null : matches.first;
  }

  static int _rank(String name) {
    const order = ['cover', 'folder', 'front', 'albumart', 'album', 'thumb'];
    final stem = name.toLowerCase().split('.').first;
    final i = order.indexWhere(stem.startsWith);
    return i < 0 ? order.length : i;
  }

  /// Cached cover file path for [itemId], if any.
  Future<String?> coverPath(int itemId) async {
    if (_memo.containsKey(itemId)) return _memo[itemId];
    final row =
        await (db.select(db.artworks)
              ..where(
                (a) =>
                    a.ownerType.equals('item') &
                    a.ownerId.equals(itemId) &
                    a.role.equals('cover'),
              )
              ..limit(1))
            .getSingleOrNull();
    final path = row?.cachePath;
    final ok = path != null && File(path).existsSync();
    return _memo[itemId] = ok ? path : null;
  }

  Future<bool> hasCover(int itemId) async => await coverPath(itemId) != null;

  /// Stores [bytes] as [itemId]'s cover.
  Future<String> store(
    int itemId,
    Uint8List bytes, {
    required String mimeType,
    required ArtSource source,
  }) async {
    final ext = switch (mimeType) {
      'image/png' => 'png',
      'image/webp' => 'webp',
      'image/gif' => 'gif',
      'image/bmp' => 'bmp',
      _ => 'jpg',
    };
    final name = '${sha1.convert(bytes)}.$ext';
    final file = File('${directory.path}${Platform.pathSeparator}$name');
    if (!file.existsSync()) {
      await directory.create(recursive: true);
      final tmp = File('${file.path}.tmp');
      await tmp.writeAsBytes(bytes, flush: true);
      await tmp.rename(file.path);
    }
    await db.transaction(() async {
      await (db.delete(db.artworks)..where(
            (a) =>
                a.ownerType.equals('item') &
                a.ownerId.equals(itemId) &
                a.role.equals('cover'),
          ))
          .go();
      await db
          .into(db.artworks)
          .insert(
            ArtworksCompanion.insert(
              ownerType: 'item',
              ownerId: itemId,
              role: 'cover',
              uri: '${source.name}:$name',
              cachePath: Value(file.path),
            ),
          );
    });
    _memo[itemId] = file.path;
    return file.path;
  }

  Future<String?> storeEmbedded(int itemId, AudioTags tags) async {
    final cover = tags.cover;
    if (cover == null) return null;
    return await store(
      itemId,
      cover.bytes,
      mimeType: cover.mimeType,
      source: ArtSource.embedded,
    );
  }

  void forget(int itemId) => _memo.remove(itemId);
}
