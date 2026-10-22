import 'dart:io';

import 'package:drift/drift.dart' hide isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:mediahro/core/db/library_database.dart';
import 'package:sqlite3/sqlite3.dart' as raw;

/// Each schema version has a step in `LibraryDatabase.migration` and a test
/// here.
void main() {
  // Two databases on one file in sequence.
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('c2_migration'));
  tearDown(() {
    try {
      dir.deleteSync(recursive: true);
    } on FileSystemException {
      // Best effort.
    }
  });

  List<String> columns(raw.Database db, String table) => [
    for (final r in db.select('PRAGMA table_info($table)')) r['name'] as String,
  ];

  test('ADR-048 version 1 to 2: the film-database ids and cloud sources go, '
      'everything else stays', () async {
    // A current database, taken back to what version 1 looked like.
    final created = LibraryDatabase.open(dir);
    await created.customSelect('SELECT 1').get();
    await created.close();
    final file = File(LibraryDatabase.fileNameFor(dir, 'default'));
    final v1 = raw.sqlite3.open(file.path);
    // The statements below are not one chain: the checks sit between them.
    // ignore: cascade_invocations
    v1
      ..execute('ALTER TABLE video_meta ADD COLUMN tmdb_id TEXT')
      ..execute('ALTER TABLE video_meta ADD COLUMN tvdb_id TEXT')
      ..execute('ALTER TABLE person ADD COLUMN tmdb_id TEXT')
      ..execute('ALTER TABLE series ADD COLUMN tmdb_id TEXT')
      ..execute('ALTER TABLE series ADD COLUMN tvdb_id TEXT')
      ..execute(
        'INSERT INTO source (kind, name, root_uri, added_at) '
        "VALUES ('local', 'Films', 'file:///Films/', 1), "
        "('cloud', 'Drive', 'cloud://drive/', 1)",
      )
      ..execute("INSERT INTO person (name, tmdb_id) VALUES ('Ana', '7')")
      ..execute("INSERT INTO series (title, tmdb_id) VALUES ('Show', '9')")
      ..execute('PRAGMA user_version = 1');
    expect(columns(v1, 'video_meta'), containsAll(['tmdb_id', 'tvdb_id']));
    v1.close();

    final db = LibraryDatabase.open(dir);
    addTearDown(db.close);
    final names = await db
        .customSelect('SELECT name FROM source ORDER BY id')
        .get();
    expect(names.map((r) => r.read<String>('name')), ['Films']);
    final people = await db.select(db.people).get();
    expect(people.single.name, 'Ana');
    expect((await db.select(db.seriesTable).get()).single.title, 'Show');
    final version = await db.customSelect('PRAGMA user_version').getSingle();
    expect(version.read<int>('user_version'), 2);
    for (final (table, column) in const [
      ('video_meta', 'tmdb_id'),
      ('video_meta', 'tvdb_id'),
      ('person', 'tmdb_id'),
      ('series', 'tmdb_id'),
      ('series', 'tvdb_id'),
    ]) {
      final info = await db.customSelect('PRAGMA table_info($table)').get();
      expect(
        info.map((r) => r.read<String>('name')),
        isNot(contains(column)),
        reason: '$table.$column',
      );
    }
    // The imdb id, which needs no key, is kept.
    final meta = await db.customSelect('PRAGMA table_info(video_meta)').get();
    expect(meta.map((r) => r.read<String>('name')), contains('imdb_id'));
  });

  test('a new database starts at the current version with no film-database '
      'columns', () async {
    final db = LibraryDatabase.memory();
    addTearDown(db.close);
    final version = await db.customSelect('PRAGMA user_version').getSingle();
    expect(version.read<int>('user_version'), db.schemaVersion);
    final info = await db.customSelect('PRAGMA table_info(video_meta)').get();
    expect(info.map((r) => r.read<String>('name')), isNot(contains('tmdb_id')));
  });
}
