import 'dart:io';

import 'package:drift/drift.dart' hide isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:mediahro/core/db/library_database.dart';

void main() {
  // Two profiles open at once use two files, not one executor.
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  test('LIB-001 every docs/05 §6 core table exists in the index', () async {
    final db = LibraryDatabase.memory();
    addTearDown(db.close);
    final rows = await db
        .customSelect("SELECT name FROM sqlite_master WHERE type = 'table'")
        .get();
    final names = rows.map((r) => r.read<String>('name')).toSet();
    const required = [
      'source',
      'item',
      'video_meta',
      'audio_meta',
      'image_meta',
      'track',
      'chapter',
      'artwork',
      'tag',
      'item_tag',
      'playlist',
      'playlist_item',
      'queue',
      'queue_item',
      'progress',
      'rating',
      'label',
      'person',
      'place',
      'album',
      'artist',
      'series',
      'season',
      'collection',
      'server_account',
      'server_item_map',
      'download',
      'scan_job',
      'thumb_cache',
      'setting',
      'shader_preset',
      'eq_preset',
      'subtitle_cache',
      'scrobble_queue',
      'item_fts',
    ];
    for (final t in required) {
      expect(names, contains(t), reason: t);
    }
  });

  test('LIB-001 FTS5 is compiled in and supports prefix queries', () async {
    final db = LibraryDatabase.memory();
    addTearDown(db.close);
    await db.customStatement(
      "INSERT INTO item_fts(rowid, title, name) VALUES (1, 'Blade Runner', 'br.mkv')",
    );
    final hit = await db
        .customSelect("SELECT rowid FROM item_fts WHERE item_fts MATCH 'bla*'")
        .get();
    expect(hit.single.read<int>('rowid'), 1);
  });

  test('LIB-001 file databases use WAL, one file per profile', () async {
    final dir = await Directory.systemTemp.createTemp('mediahro_db');
    addTearDown(() => dir.delete(recursive: true));
    final a = LibraryDatabase.open(dir, profileId: 'alice');
    final b = LibraryDatabase.open(dir, profileId: 'kids');
    expect(await a.journalMode(), 'wal');
    await a
        .into(a.sources)
        .insert(
          SourcesCompanion.insert(
            kind: SourceKind.local,
            name: 'Films',
            rootUri: 'file:///films/',
            addedAt: DateTime.utc(2026),
          ),
        );
    expect(await a.select(a.sources).get(), hasLength(1));
    expect(await b.select(b.sources).get(), isEmpty);
    await a.close();
    await b.close();
    expect(
      File(LibraryDatabase.fileNameFor(dir, 'alice')).existsSync(),
      isTrue,
    );
    expect(() => LibraryDatabase.fileNameFor(dir, '../x'), throwsArgumentError);
  });

  test('LIB-001 deleting a source cascades to its items', () async {
    final db = LibraryDatabase.memory();
    addTearDown(db.close);
    final now = DateTime.utc(2026);
    final sid = await db
        .into(db.sources)
        .insert(
          SourcesCompanion.insert(
            kind: SourceKind.local,
            name: 's',
            rootUri: 'file:///s/',
            addedAt: now,
          ),
        );
    await db
        .into(db.items)
        .insert(
          ItemsCompanion.insert(
            sourceId: sid,
            relPath: 'a.mkv',
            parentPath: '',
            name: 'a.mkv',
            ext: 'mkv',
            kind: ItemKind.video,
            size: 1,
            mtime: now,
            addedAt: now,
            scannedAt: now,
            title: 'a',
            sortTitle: 'a',
          ),
        );
    await (db.delete(db.sources)..where((s) => s.id.equals(sid))).go();
    expect(await db.select(db.items).get(), isEmpty);
  });
}
