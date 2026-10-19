import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:mediahro/core/db/tables.dart';
import 'package:sqlite3/sqlite3.dart' show Database;

export 'tables.dart';

part 'library_database.g.dart';

/// The local library index (LIB-001, ADR-006): SQLite through drift, WAL,
/// FTS5 for search, versioned migrations, one database file per profile.
///
/// Opened with [LibraryDatabase.open], drift runs every statement on a
/// background isolate so the UI isolate never touches SQLite (docs/05 §7).
@DriftDatabase(
  tables: [
    Sources,
    Items,
    VideoMeta,
    AudioMeta,
    ImageMeta,
    Tracks,
    Chapters,
    Artworks,
    Tags,
    ItemTags,
    Labels,
    Playlists,
    PlaylistItems,
    Queues,
    QueueItems,
    Progress,
    Ratings,
    PlayEvents,
    People,
    ItemPeople,
    Places,
    Albums,
    Artists,
    SeriesTable,
    Seasons,
    Collections,
    ServerAccounts,
    ServerItemMap,
    Downloads,
    ScanJobs,
    ThumbCache,
    SettingsTable,
    ShaderPresets,
    EqPresets,
    SubtitleCache,
    ScrobbleQueue,
    UrlHistory,
    LockedFolders,
  ],
)
class LibraryDatabase extends _$LibraryDatabase {
  LibraryDatabase(super.e);

  /// In-memory database for tests and previews.
  factory LibraryDatabase.memory() => LibraryDatabase(NativeDatabase.memory());

  /// Opens (creating if needed) the database for [profileId] in [directory].
  factory LibraryDatabase.open(
    Directory directory, {
    String profileId = 'default',
  }) {
    final file = File(fileNameFor(directory, profileId));
    return LibraryDatabase(
      NativeDatabase.createInBackground(file, setup: _setup),
    );
  }

  /// File path of a profile's database (one DB per profile, docs/05 §6).
  static String fileNameFor(Directory directory, String profileId) {
    if (!RegExp(r'^[A-Za-z0-9_-]{1,64}$').hasMatch(profileId)) {
      throw ArgumentError.value(profileId, 'profileId');
    }
    return '${directory.path}${Platform.pathSeparator}library-$profileId.sqlite';
  }

  static void _setup(Database db) {
    db
      ..execute('PRAGMA journal_mode = WAL')
      ..execute('PRAGMA synchronous = NORMAL');
  }

  /// Bumped with every schema change; each step has a migration below and a
  /// test in `test/core/db/migration_test.dart`.
  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
      await createFts(this);
    },
    onUpgrade: (m, from, to) async {
      // Stepwise migrations: for (var v = from; v < to; v++) { ... }.
    },
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );

  /// Current SQLite journal mode (`wal` for file databases).
  Future<String> journalMode() async {
    final row = await customSelect('PRAGMA journal_mode').getSingle();
    return row.data.values.first.toString();
  }
}

/// The FTS5 index over searchable text (LIB-005). `rowid` is `items.id`.
/// Prefix indexes on 2 and 3 characters keep prefix queries under budget.
Future<void> createFts(GeneratedDatabase db) => db.customStatement('''
CREATE VIRTUAL TABLE IF NOT EXISTS item_fts USING fts5(
  title, name, tags, artist, album, people, places,
  tokenize = 'unicode61 remove_diacritics 2',
  prefix = '2 3'
)''');
