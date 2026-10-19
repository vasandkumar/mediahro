import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:mediahro/core/db/library_database.dart';
import 'package:mediahro/core/metadata/filename_parser.dart';
import 'package:mediahro/core/scanner/scan_model.dart';

/// Counts written by [IndexWriter.apply].
final class ApplyResult {
  const ApplyResult({
    this.added = 0,
    this.updated = 0,
    this.moved = 0,
    this.removed = 0,
  });

  final int added;
  final int updated;
  final int moved;
  final int removed;
}

/// Media facts from the prober (engine/image pipeline), applied per item.
final class ProbeResult {
  const ProbeResult({
    this.durationMs,
    this.width,
    this.height,
    this.videoCodec,
    this.audioCodec,
    this.hdrType,
    this.audioLayout,
    this.audioTracks = 0,
    this.subtitleTracks = 0,
    this.contentHash,
    this.title,
    this.takenAt,
    this.artist,
    this.albumArtist,
    this.album,
    this.genre,
    this.composer,
    this.year,
    this.trackNumber,
    this.discNumber,
    this.frameRate,
  });

  final int? durationMs;
  final int? width;
  final int? height;
  final String? videoCodec;
  final String? audioCodec;
  final String? hdrType;
  final String? audioLayout;
  final int audioTracks;
  final int subtitleTracks;
  final String? contentHash;

  /// Embedded title tag; replaces the file-name title when present.
  final String? title;
  final DateTime? takenAt;
  final String? artist;
  final String? albumArtist;
  final String? album;
  final String? genre;
  final String? composer;
  final int? year;
  final int? trackNumber;
  final int? discNumber;
  final double? frameRate;

  bool get hasAudioTags =>
      artist != null ||
      album != null ||
      albumArtist != null ||
      genre != null ||
      composer != null;
}

/// The only writer of `item` rows and the FTS index (LIB-001, LIB-005).
final class IndexWriter {
  IndexWriter(this.db, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final LibraryDatabase db;
  final DateTime Function() _clock;

  /// The stable keys the index holds for [sourceId].
  Future<Map<String, KnownItem>> known(int sourceId) async {
    final rows = await db
        .customSelect(
          'SELECT id, rel_path, size, mtime, content_hash, missing '
          'FROM item WHERE source_id = ?',
          variables: [Variable.withInt(sourceId)],
          readsFrom: {db.items},
        )
        .get();
    return {
      for (final r in rows)
        r.read<String>('rel_path'): KnownItem(
          id: r.read<int>('id'),
          relPath: r.read<String>('rel_path'),
          size: r.read<int>('size'),
          mtimeMs: _mtimeMs(r.read<int>('mtime')),
          contentHash: r.readNullable<String>('content_hash'),
          missing: r.read<bool>('missing'),
        ),
    };
  }

  /// Applies a scan diff in one transaction and refreshes the FTS rows.
  Future<ApplyResult> apply(int sourceId, ScanDiff diff) async {
    final now = _clock();
    return await db.transaction(() async {
      final maxBefore = await _maxId();
      if (diff.added.isNotEmpty) {
        await db.batch((b) {
          b.insertAll(db.items, [
            for (final f in diff.added) _insertRow(sourceId, f, now, diff),
          ]);
        });
      }
      for (final (id, f) in diff.changed) {
        await (db.update(db.items)..where((i) => i.id.equals(id))).write(
          ItemsCompanion(
            size: Value(f.size),
            mtime: Value(_mtime(f.mtimeMs)),
            scannedAt: Value(now),
            missing: const Value(false),
            probed: const Value(false),
            contentHash: const Value(null),
          ),
        );
      }
      for (final m in diff.moved) {
        await (db.update(db.items)..where((i) => i.id.equals(m.id))).write(
          ItemsCompanion(
            relPath: Value(m.to.relPath),
            parentPath: Value(m.to.parentPath),
            name: Value(m.to.name),
            mtime: Value(_mtime(m.to.mtimeMs)),
            scannedAt: Value(now),
            missing: const Value(false),
            contentHash: m.contentHash == null
                ? const Value.absent()
                : Value(m.contentHash),
          ),
        );
      }
      if (diff.missingIds.isNotEmpty) {
        await _setMissing(diff.missingIds, missing: true);
      }
      if (diff.reappearedIds.isNotEmpty) {
        await _setMissing(diff.reappearedIds, missing: false);
      }
      final addedIds = await _videoMetaForAdded(sourceId, maxBefore);
      await refreshFts([...addedIds, for (final m in diff.moved) m.id]);
      return ApplyResult(
        added: diff.added.length,
        updated: diff.changed.length,
        moved: diff.moved.length,
        removed: diff.missingIds.length,
      );
    });
  }

  /// Writes prober facts for [itemId] and refreshes its search row.
  Future<void> applyProbe(int itemId, ProbeResult p) async {
    await db.transaction(() async {
      await (db.update(db.items)..where((i) => i.id.equals(itemId))).write(
        ItemsCompanion(
          durationMs: Value(p.durationMs),
          width: Value(p.width),
          height: Value(p.height),
          videoCodec: Value(p.videoCodec),
          audioCodec: Value(p.audioCodec),
          hdrType: Value(p.hdrType),
          audioLayout: Value(p.audioLayout),
          audioTracks: Value(p.audioTracks),
          subtitleTracks: Value(p.subtitleTracks),
          probed: const Value(true),
          takenAt: Value(p.takenAt),
          contentHash: p.contentHash == null
              ? const Value.absent()
              : Value(p.contentHash),
          title: p.title == null ? const Value.absent() : Value(p.title!),
          sortTitle: p.title == null
              ? const Value.absent()
              : Value(sortTitle(p.title!)),
        ),
      );
      if (p.hasAudioTags) {
        await db
            .into(db.audioMeta)
            .insertOnConflictUpdate(
              AudioMetaCompanion.insert(
                itemId: Value(itemId),
                artist: Value(p.artist),
                albumArtist: Value(p.albumArtist),
                album: Value(p.album),
                genre: Value(p.genre),
                composer: Value(p.composer),
                year: Value(p.year),
                trackNumber: Value(p.trackNumber),
                discNumber: Value(p.discNumber),
              ),
            );
      }
      if (p.frameRate != null) {
        await (db.update(db.videoMeta)..where((v) => v.itemId.equals(itemId)))
            .write(VideoMetaCompanion(frameRate: Value(p.frameRate)));
      }
      await refreshFts([itemId]);
    });
  }

  /// Rebuilds the FTS rows of [ids] from the item, tag, audio, people and
  /// place tables (LIB-005 searches all of them).
  Future<void> refreshFts(Iterable<int> ids) async {
    final list = ids.toList();
    if (list.isEmpty) return;
    for (var i = 0; i < list.length; i += 5000) {
      final chunk = jsonEncode(
        list.sublist(i, (i + 5000).clamp(0, list.length)),
      );
      await db.customStatement(
        'DELETE FROM item_fts WHERE rowid IN (SELECT value FROM json_each(?))',
        [chunk],
      );
      await db.customStatement(_ftsInsert, [chunk]);
    }
  }

  /// Rebuilds the whole FTS index (after restore or migration).
  Future<void> rebuildFts() async {
    await db.customStatement('DELETE FROM item_fts');
    await db.customStatement(
      _ftsInsert.replaceFirst(
        'WHERE i.id IN (SELECT value FROM json_each(?))',
        '',
      ),
    );
  }

  /// Removes items marked missing before [olderThan] (they never re-linked).
  Future<int> purgeMissing({required DateTime olderThan}) =>
      (db.delete(db.items)..where(
            (i) =>
                i.missing.equals(true) &
                i.scannedAt.isSmallerThanValue(olderThan),
          ))
          .go();

  ItemsCompanion _insertRow(
    int sourceId,
    FoundFile f,
    DateTime now,
    ScanDiff diff,
  ) {
    final title = f.kind == ItemKind.video
        ? _videoTitle(f)
        : cleanTitle(f.name);
    return ItemsCompanion.insert(
      sourceId: sourceId,
      relPath: f.relPath,
      parentPath: f.parentPath,
      name: f.name,
      ext: _ext(f.name),
      kind: f.kind,
      size: f.size,
      mtime: _mtime(f.mtimeMs),
      addedAt: now,
      scannedAt: now,
      title: title,
      sortTitle: sortTitle(title),
      contentHash: Value(diff.addedHashes[f.relPath]),
    );
  }

  Future<List<int>> _videoMetaForAdded(int sourceId, int maxBefore) async {
    final rows =
        await (db.select(db.items)..where(
              (i) =>
                  i.sourceId.equals(sourceId) &
                  i.id.isBiggerThanValue(maxBefore),
            ))
            .get();
    final metas = <VideoMetaCompanion>[];
    for (final r in rows) {
      if (r.kind != ItemKind.video) continue;
      final p = _parse(r.relPath);
      metas.add(
        VideoMetaCompanion.insert(
          itemId: Value(r.id),
          parsedTitle: Value(p.title),
          year: Value(p.year),
          seasonNumber: Value(p.season),
          episodeNumber: Value(p.episode ?? p.absoluteEpisode),
          episodeTitle: Value(p.episodeTitle),
        ),
      );
    }
    if (metas.isNotEmpty) {
      await db.batch((b) => b.insertAllOnConflictUpdate(db.videoMeta, metas));
    }
    return [for (final r in rows) r.id];
  }

  Future<void> _setMissing(List<int> ids, {required bool missing}) async {
    for (var i = 0; i < ids.length; i += 5000) {
      final chunk = jsonEncode(ids.sublist(i, (i + 5000).clamp(0, ids.length)));
      await db.customStatement(
        'UPDATE item SET missing = ? WHERE id IN (SELECT value FROM json_each(?))',
        [if (missing) 1 else 0, chunk],
      );
    }
  }

  Future<int> _maxId() async {
    final r = await db
        .customSelect('SELECT coalesce(max(id), 0) AS m FROM item')
        .getSingle();
    return r.read<int>('m');
  }

  static String _videoTitle(FoundFile f) {
    final p = _parse(f.relPath);
    return p.title.isEmpty ? cleanTitle(f.name) : p.title;
  }

  static ParsedName _parse(String relPath) {
    final parts = relPath.split('/');
    return parseVideoFileName(
      parts.last,
      parentFolders: parts.reversed.skip(1).toList(),
    );
  }

  static String _ext(String name) {
    final i = name.lastIndexOf('.');
    return i <= 0 ? '' : name.substring(i + 1).toLowerCase();
  }

  // drift stores DateTime as unix seconds; keep millisecond keys exact by
  // comparing at second precision.
  static DateTime _mtime(int ms) =>
      DateTime.fromMillisecondsSinceEpoch(ms ~/ 1000 * 1000, isUtc: true);

  static int _mtimeMs(int storedSeconds) => storedSeconds * 1000;
}

const _ftsInsert = '''
INSERT INTO item_fts(rowid, title, name, tags, artist, album, people, places)
SELECT i.id, i.title, i.name,
  coalesce((SELECT group_concat(t.name, ' ') FROM item_tag it
            JOIN tag t ON t.id = it.tag_id WHERE it.item_id = i.id), ''),
  trim(coalesce(a.artist, '') || ' ' || coalesce(a.album_artist, '') || ' ' ||
       coalesce(a.composer, '')),
  coalesce(a.album, ''),
  coalesce((SELECT group_concat(p.name, ' ') FROM item_person ip
            JOIN person p ON p.id = ip.person_id WHERE ip.item_id = i.id), ''),
  coalesce((SELECT pl.name || ' ' || coalesce(pl.country, '') FROM image_meta im
            JOIN place pl ON pl.id = im.place_id WHERE im.item_id = i.id), '')
FROM item i LEFT JOIN audio_meta a ON a.item_id = i.id
WHERE i.id IN (SELECT value FROM json_each(?))''';
