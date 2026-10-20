import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mediahro/core/db/library_database.dart';
import 'package:mediahro/core/index/index_writer.dart';
import 'package:mediahro/core/library/library_views.dart';
import 'package:mediahro/core/library/playlists.dart';
import 'package:mediahro/core/library/queues.dart';
import 'package:mediahro/core/rules/smart_rule.dart';
import 'package:mediahro/core/sources/source_access.dart';
import 'package:mediahro/features/music/car/music_browse_tree.dart';
import 'package:mediahro/features/music/library/artwork_store.dart';
import 'package:mediahro/features/music/library/music_files.dart';
import 'package:mediahro/features/music/library/music_library.dart';
import 'package:mediahro/features/music/library/music_playlists.dart';
import 'package:mediahro/features/music/player/music_player.dart';
import 'package:mediahro_engine/mediahro_engine.dart';
import 'package:mediahro_engine/testing.dart';
import 'package:mediahro_ffi/mediahro_ffi.dart';

/// Lane C2 on real devices (MUS-008, MUS-013): smart playlist rules on the
/// platform's SQLite, and the car browse tree with paging and voice search.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late Directory data;
  late LibraryDatabase db;

  setUp(() async {
    data = await Directory.systemTemp.createTemp('c2pc_data');
    db = LibraryDatabase.open(data);
    final sid = await db
        .into(db.sources)
        .insert(
          SourcesCompanion.insert(
            kind: SourceKind.local,
            name: 'Car',
            rootUri: data.uri.toString(),
            addedAt: DateTime.now().toUtc(),
          ),
        );
    final w = IndexWriter(db);
    for (var i = 0; i < 250; i++) {
      final rel = 'Album ${i ~/ 10}/${i.toString().padLeft(3, '0')}.flac';
      final id = await db
          .into(db.items)
          .insert(
            ItemsCompanion.insert(
              sourceId: sid,
              relPath: rel,
              parentPath: 'Album ${i ~/ 10}',
              name: rel.split('/').last,
              ext: 'flac',
              kind: ItemKind.audio,
              size: 1000,
              mtime: DateTime.utc(2026),
              addedAt: DateTime.utc(2026),
              scannedAt: DateTime.utc(2026),
              title: 'Song $i',
              sortTitle: 'song $i',
            ),
          );
      await w.applyProbe(
        id,
        ProbeResult(
          durationMs: 60000 + i * 1000,
          title: 'Song $i',
          artist: i.isEven ? 'Even Artist' : 'Odd Artist',
          albumArtist: i.isEven ? 'Even Artist' : 'Odd Artist',
          album: 'Album ${i ~/ 10}',
          genre: i % 3 == 0 ? 'Jazz' : 'Rock',
          trackNumber: i % 10 + 1,
        ),
      );
    }
  });
  tearDown(() async {
    await db.close();
    try {
      await data.delete(recursive: true);
    } on FileSystemException {
      // The OS cleans temp.
    }
  });

  testWidgets('MUS-008 smart playlist rules on the platform SQLite', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final lib = MusicLibrary(db);
      final pl = MusicPlaylists(db, PlaylistRepository(db), lib);
      const rule = SmartRule(
        root: RuleGroup(
          children: [
            RuleCondition(RuleField.genre, RuleOp.equals, 'Jazz'),
            RuleCondition(RuleField.durationMs, RuleOp.greaterThan, 200000),
            RuleGroup(
              matchAll: false,
              children: [
                RuleCondition(RuleField.artist, RuleOp.contains, 'Even'),
                RuleCondition(RuleField.trackNumber, RuleOp.atMost, 2),
              ],
            ),
          ],
        ),
        sort: RuleSort(RuleField.durationMs, descending: true),
        limit: 30,
        limitUnit: RuleLimitUnit.minutes,
      );
      final id = await pl.createSmart('Long jazz', rule);
      final tracks = await pl.tracks(id);
      expect(tracks, isNotEmpty);
      expect(tracks.every((t) => t.genre == 'Jazz'), isTrue);
      final minutes = tracks.fold<Duration>(
        Duration.zero,
        (a, t) => a + t.duration!,
      );
      expect(minutes, lessThanOrEqualTo(const Duration(minutes: 30)));
      expect(tracks.first.duration! >= tracks.last.duration!, isTrue);
    });
  });

  testWidgets('MUS-013 car tree pages through a large library and finds by '
      'voice', (tester) async {
    await tester.runAsync(() async {
      final lib = MusicLibrary(db);
      final player = MusicPlayer(
        engine: FakePlaybackEngine(role: EngineRole.music),
        queues: QueueRepository(db),
        library: lib,
        files: MusicFiles(
          db,
          DefaultSourceResolver(
            builders: {SourceKind.local: (_) => const LocalFileSystem()},
          ),
        ),
        openTimeout: const Duration(milliseconds: 100),
      );
      await player.init();
      final tree = MusicBrowseTree(
        db: db,
        library: lib,
        playlists: MusicPlaylists(db, PlaylistRepository(db), lib),
        views: LibraryViews(db),
        player: player,
        art: ArtworkStore(db, Directory('${data.path}/art')),
        labels: const MusicBrowseLabels(
          queue: 'Queue',
          playlists: 'Playlists',
          albums: 'Albums',
          artists: 'Artists',
          folders: 'Folders',
          songs: 'Songs',
          unknownArtist: '?',
        ),
      );
      final albums = await tree.children(MusicBrowseTree.albumsId);
      // Album + album artist: each folder holds two artists.
      expect(albums.length, 50);
      final sw = Stopwatch()..start();
      final folders = await tree.children(MusicBrowseTree.foldersId);
      final top = await tree.children(folders.single.id);
      expect(top.length, 25);
      final hits = await tree.search('song 12 by even');
      expect(hits.map((h) => h.title), contains('Song 12'));
      expect(sw.elapsedMilliseconds, lessThan(2000));
      await tree.play(hits.first.id);
      expect(player.state.current, isNotNull);
      await player.dispose();
    });
  });
}
