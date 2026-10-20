import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mediahro/core/db/library_database.dart';
import 'package:mediahro/core/library/library_views.dart';
import 'package:mediahro/core/library/playlists.dart';
import 'package:mediahro/core/library/queues.dart';
import 'package:mediahro/core/rules/smart_rule.dart';
import 'package:mediahro/features/music/car/music_browse_tree.dart';
import 'package:mediahro/features/music/library/artwork_store.dart';
import 'package:mediahro/features/music/library/music_library.dart';
import 'package:mediahro/features/music/library/music_playlists.dart';
import 'package:mediahro/features/music/player/music_player.dart';
import 'package:mediahro/features/music/player/music_session.dart';
import 'package:mediahro/platform/platform_facades.dart';

import 'music_test_support.dart';

void main() {
  late LibraryDatabase db;
  late MusicLibrary lib;
  late MusicPlaylists playlists;
  late Directory dir;

  setUp(() async {
    db = LibraryDatabase.memory();
    lib = MusicLibrary(db);
    playlists = MusicPlaylists(db, PlaylistRepository(db), lib);
    dir = Directory.systemTemp.createTempSync('c2_pl');
    final seed = MusicSeed(db);
    await seed.song(
      'j/1.flac',
      title: 'Blue',
      artist: 'Miles',
      albumArtist: 'Miles',
      album: 'Kind',
      genre: 'Jazz',
      track: 1,
      durationMs: 300000,
    );
    await seed.song(
      'j/2.flac',
      title: 'So What',
      artist: 'Miles',
      albumArtist: 'Miles',
      album: 'Kind',
      genre: 'Jazz',
      track: 2,
      durationMs: 120000,
    );
    await seed.song(
      'r/1.mp3',
      title: 'Rock On',
      artist: 'Band',
      albumArtist: 'Band',
      album: 'Loud',
      genre: 'Rock',
      durationMs: 200000,
    );
    await db.customStatement(
      "UPDATE item SET play_count = 5, last_played_at = strftime('%s','now') WHERE rel_path = 'j/2.flac'",
    );
  });
  tearDown(() async {
    await db.close();
    try {
      dir.deleteSync(recursive: true);
    } on FileSystemException {
      // Best effort.
    }
  });

  group('MUS-008 smart playlists', () {
    test('MUS-008 rules over tags, play count, last played, length and path; '
        'sort and limit; live preview', () async {
      const jazzLong = SmartRule(
        root: RuleGroup(
          children: [
            RuleCondition(RuleField.genre, RuleOp.equals, 'Jazz'),
            RuleCondition(RuleField.durationMs, RuleOp.greaterThan, 180000),
          ],
        ),
      );
      expect(await playlists.preview(jazzLong), 1);
      final id = await playlists.createSmart('Long jazz', jazzLong);
      expect((await playlists.tracks(id)).single.title, 'Blue');

      const played = SmartRule(
        root: RuleGroup(
          matchAll: false,
          children: [
            RuleCondition(RuleField.playCount, RuleOp.atLeast, 1),
            RuleCondition(RuleField.lastPlayed, RuleOp.inLastDays, 7),
          ],
        ),
      );
      expect(
        (await playlists.tracks(await playlists.createSmart('Played', played)))
            .single
            .title,
        'So What',
      );

      const byPath = SmartRule(
        root: RuleGroup(
          children: [RuleCondition(RuleField.path, RuleOp.startsWith, 'j/')],
        ),
        sort: RuleSort(RuleField.title, descending: true),
        limit: 1,
      );
      final top = await playlists.tracks(
        await playlists.createSmart('Path', byPath),
      );
      expect(top.single.title, 'So What');

      // Nested group: Jazz AND (title contains "Blue" OR played).
      const nested = SmartRule(
        root: RuleGroup(
          children: [
            RuleCondition(RuleField.genre, RuleOp.equals, 'Jazz'),
            RuleGroup(
              matchAll: false,
              children: [
                RuleCondition(RuleField.title, RuleOp.contains, 'Blue'),
                RuleCondition(RuleField.playCount, RuleOp.greaterThan, 3),
              ],
            ),
          ],
        ),
      );
      expect(await playlists.preview(nested), 2);
      final all = await playlists.all();
      expect(
        all.map((p) => (p.name, p.smart, p.count)),
        contains(('Long jazz', true, 1)),
      );
    });

    test('MUS-008 smart rules from music never match other kinds', () async {
      final sid = await MusicSeed(db).source();
      await db
          .into(db.items)
          .insert(
            ItemsCompanion.insert(
              sourceId: sid,
              relPath: 'j/clip.mkv',
              parentPath: 'j',
              name: 'clip.mkv',
              ext: 'mkv',
              kind: ItemKind.video,
              size: 1,
              mtime: DateTime.utc(2026),
              addedAt: DateTime.utc(2026),
              scannedAt: DateTime.utc(2026),
              title: 'Blue video',
              sortTitle: 'blue video',
            ),
          );
      const r = SmartRule(
        root: RuleGroup(
          children: [RuleCondition(RuleField.title, RuleOp.contains, 'Blue')],
        ),
      );
      expect(await playlists.preview(r), 1);
    });

    test('MUS-001 manual playlists keep their order', () async {
      final id = await playlists.createManual('Mix');
      final songs = await lib.songs();
      await playlists.add(id, songs.reversed.toList());
      expect(
        (await playlists.tracks(id)).map((t) => t.title),
        songs.reversed.map((t) => t.title),
      );
      await playlists.move(id, 0, 2);
      await playlists.removeAt(id, 0);
      expect((await playlists.tracks(id)).length, 2);
    });
  });

  group('MUS-013 car browse tree', () {
    late ScriptedMusicEngine engine;
    late MusicPlayer player;
    late MusicBrowseTree tree;

    setUp(() async {
      engine = ScriptedMusicEngine();
      player = MusicPlayer(
        engine: engine,
        queues: QueueRepository(db),
        library: lib,
        files: localMusicFiles(db),
        openTimeout: const Duration(milliseconds: 100),
      );
      await player.init();
      tree = MusicBrowseTree(
        db: db,
        library: lib,
        playlists: playlists,
        views: LibraryViews(db),
        player: player,
        art: ArtworkStore(db, Directory('${dir.path}/art')),
        labels: const MusicBrowseLabels(
          queue: 'Queue',
          playlists: 'Playlists',
          albums: 'Albums',
          artists: 'Artists',
          folders: 'Folders',
          songs: 'Songs',
          unknownArtist: 'Unknown artist',
        ),
        pageSize: 3,
      );
    });
    tearDown(() => player.dispose());

    test('MUS-013 root, albums, artists, folders and paging', () async {
      final root = await tree.children(MediaBrowseNode.rootId);
      expect(root.map((n) => n.title), ['Queue', 'Playlists', 'Albums']);
      final root2 = await tree.children(MediaBrowseNode.rootId, page: 1);
      expect(root2.map((n) => n.title), ['Artists', 'Folders']);
      final albums = await tree.children(MusicBrowseTree.albumsId);
      expect(albums.map((n) => n.title), ['Kind', 'Loud']);
      expect(albums.first.browsable && albums.first.playable, isTrue);
      final kind = await tree.children(albums.first.id);
      expect(kind.map((n) => n.title), ['Blue', 'So What']);
      expect(kind.first.playable, isTrue);
      final artists = await tree.children(MusicBrowseTree.artistsId);
      expect(artists.map((n) => n.title), ['Band', 'Miles']);
      final folders = await tree.children(MusicBrowseTree.foldersId);
      final inside = await tree.children(folders.single.id);
      expect(inside.map((n) => n.title), ['j', 'r']);
      final j = await tree.children(inside.first.id);
      expect(j.map((n) => n.title), ['Blue', 'So What']);
    });

    test('MUS-013 playing a song plays its list from there; the queue node '
        'follows', () async {
      final albums = await tree.children(MusicBrowseTree.albumsId);
      final kind = await tree.children(albums.first.id);
      await tree.play(kind.last.id);
      expect(player.state.current!.title, 'So What');
      expect(player.state.queue.length, 2);
      final queue = await tree.children(MusicBrowseTree.queueId);
      expect(queue.map((n) => n.title), ['Blue', 'So What']);
      await tree.play(queue.first.id);
      expect(player.state.current!.title, 'Blue');
      await tree.play(albums.last.id);
      expect(player.state.current!.title, 'Rock On');
    });

    test('MUS-013 voice search: "title", "title by artist"', () async {
      expect((await tree.search('so what')).single.title, 'So What');
      expect((await tree.search('blue by miles')).single.title, 'Blue');
      expect(await tree.search('blue by band'), isEmpty);
      final hit = (await tree.search('rock')).single;
      await tree.play(hit.id);
      expect(player.state.current!.title, 'Rock On');
    });
  });

  test('MUS-012 widgets follow the track and play/pause', () async {
    final engine = ScriptedMusicEngine();
    final player = MusicPlayer(
      engine: engine,
      queues: QueueRepository(db),
      library: lib,
      files: localMusicFiles(db),
      openTimeout: const Duration(milliseconds: 100),
    );
    await player.init();
    final widgets = _FakeWidgets();
    final bridge = MusicSessionBridge(
      player: player,
      session: _NullSession(),
      art: ArtworkStore(db, Directory('${dir.path}/art2')),
      widgets: widgets,
    )..start();
    await player.playTracks(await lib.songs());
    for (var i = 0; i < 50 && widgets.updates.isEmpty; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(widgets.updates.last.$1!.title, 'Blue');
    expect(widgets.updates.last.$2, isTrue);
    await player.pause();
    for (var i = 0; i < 50 && widgets.updates.last.$2; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(widgets.updates.last.$2, isFalse);
    await bridge.dispose();
    await player.dispose();
  });
}

final class _FakeWidgets implements HomeWidgetsFacade {
  final updates = <(NowPlaying?, bool)>[];

  @override
  Future<void> update(NowPlaying? item, {required bool playing}) async =>
      updates.add((item, playing));
}

final class _NullSession implements MediaSessionFacade {
  @override
  Future<void> activate(MediaSessionKind kind) async {}

  @override
  Stream<RemoteCommand> get commands => const Stream.empty();

  @override
  Future<void> deactivate() async {}

  @override
  Future<void> setNowPlaying(NowPlaying item) async {}

  @override
  Future<void> setPlaybackStatus(SessionPlaybackStatus status) async {}
}
