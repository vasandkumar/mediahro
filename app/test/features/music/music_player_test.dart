import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediahro/core/db/library_database.dart';
import 'package:mediahro/core/library/playlists.dart';
import 'package:mediahro/core/library/progress.dart';
import 'package:mediahro/core/library/queues.dart';
import 'package:mediahro/core/providers.dart';
import 'package:mediahro/engine/engine_pool.dart';
import 'package:mediahro/features/music/library/artwork_store.dart';
import 'package:mediahro/features/music/library/music_library.dart';
import 'package:mediahro/features/music/music_providers.dart';
import 'package:mediahro/features/music/player/music_player.dart';
import 'package:mediahro/features/music/player/music_session.dart';
import 'package:mediahro/platform/platform_facades.dart';
import 'package:mediahro_engine/mediahro_engine.dart';

import 'music_test_support.dart';

void main() {
  late LibraryDatabase db;
  late MusicSeed seed;
  late MusicLibrary lib;
  late ScriptedMusicEngine engine;
  late MusicPlayer player;
  late List<MusicTrack> album;

  Future<void> settle() => Future<void>.delayed(Duration.zero);

  /// Waits for async work that does real I/O (cover file reads). Waits for
  /// the state itself, however slow the machine, and fails clearly if it
  /// never comes.
  Future<void> eventually(bool Function() done) async {
    final deadline = DateTime.now().add(const Duration(seconds: 30));
    while (!done()) {
      if (DateTime.now().isAfter(deadline)) fail('state never reached');
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
  }

  MusicPlayer newPlayer() => MusicPlayer(
    engine: engine,
    queues: QueueRepository(db),
    library: lib,
    files: localMusicFiles(db),
    progress: ProgressRepository(db),
    openTimeout: const Duration(milliseconds: 200),
  );

  setUp(() async {
    db = LibraryDatabase.memory();
    seed = MusicSeed(db);
    lib = MusicLibrary(db);
    engine = ScriptedMusicEngine();
    for (var i = 1; i <= 3; i++) {
      await seed.song(
        'al/$i.flac',
        title: 'T$i',
        album: 'Al',
        albumArtist: 'A',
        track: i,
      );
    }
    await seed.song(
      'other/x.mp3',
      title: 'X',
      album: 'Other',
      albumArtist: 'B',
    );
    album = await lib.albumTracks((await lib.albums()).first.groupKey);
    player = newPlayer();
    await player.init();
  });
  tearDown(() async {
    await player.dispose();
    await db.close();
  });

  String opened(int i) => uriOf(engine.opened[i]).split('/').last;

  group('MUS-007 queue and gapless playback', () {
    test('MUS-007 playTracks opens the start track and prepares the next as '
        'same-album gapless', () async {
      await player.playTracks(album, start: 1);
      expect(player.state.current!.title, 'T2');
      expect(opened(0), '2.flac');
      expect(uriOf(engine.next!), endsWith('3.flac'));
      expect(engine.nextSameAlbum, isTrue);
      expect(player.state.playing, isTrue);
    });

    test('MUS-007 a natural gapless advance moves the queue and prepares '
        'the following track', () async {
      await player.playTracks(album);
      engine
        ..at(const Duration(minutes: 3))
        ..finishTrack();
      await settle();
      await settle();
      expect(player.state.index, 1);
      expect(player.state.current!.title, 'T2');
      expect(uriOf(engine.next!), endsWith('3.flac'));
      // The finished track counts as played (LIB-015).
      final row = await (db.select(
        db.items,
      )..where((i) => i.id.equals(album[0].itemId))).getSingle();
      expect(row.playCount, 1);
    });

    test('MUS-007 next uses the prepared item, previous restarts or goes '
        'back', () async {
      await player.playTracks(album);
      await player.next();
      expect(engine.calls, contains('skipToNext'));
      expect(player.state.index, 1);
      engine.at(const Duration(seconds: 10));
      await settle();
      await player.previous();
      expect(player.state.index, 1);
      expect(engine.current.position, Duration.zero);
      await player.previous();
      expect(player.state.index, 0);
      expect(opened(engine.opened.length - 1), '1.flac');
    });

    test('MUS-007 end of queue without repeat stops; repeat all wraps; '
        'repeat one prepares the same track', () async {
      await player.playTracks(album, start: 2);
      expect(engine.next, isNull);
      await player.setRepeat(RepeatMode.all);
      expect(uriOf(engine.next!), endsWith('1.flac'));
      await player.setRepeat(RepeatMode.one);
      expect(uriOf(engine.next!), endsWith('3.flac'));
    });

    test('AUD-043 a DSD item has no gapless join: the player opens the next '
        'queue entry itself when it ends', () async {
      engine.joinsGapless = false;
      await player.playTracks(album);
      expect(engine.current.nextPrepared, isFalse);
      engine
        ..at(const Duration(minutes: 3))
        ..finishTrack();
      expect(engine.current.status, PlaybackStatus.ended);
      await settle();
      await settle();
      await settle();
      expect(player.state.index, 1);
      expect(opened(engine.opened.length - 1), '2.flac');
      expect(engine.current.status, PlaybackStatus.playing);
      // The finished track still counts as played (LIB-015).
      final row = await (db.select(
        db.items,
      )..where((i) => i.id.equals(album[0].itemId))).getSingle();
      expect(row.playCount, 1);
    });

    test('AUD-043 the end of the queue still stops; repeat all wraps; hold '
        'opens the next item paused', () async {
      engine.joinsGapless = false;
      await player.playTracks(album, start: 2);
      engine.finishTrack();
      await settle();
      await settle();
      expect(player.state.index, 2);
      expect(engine.current.status, PlaybackStatus.ended);

      await player.setRepeat(RepeatMode.all);
      await player.playTracks(album, start: 2);
      engine.finishTrack();
      await settle();
      await settle();
      await settle();
      expect(player.state.index, 0);
      expect(engine.current.status, PlaybackStatus.playing);

      player.holdAtEnd = true;
      engine.finishTrack();
      await settle();
      await settle();
      await settle();
      expect(player.state.index, 1);
      expect(engine.current.status, PlaybackStatus.paused);
    });

    test('MUS-007 play next and add to queue; reorder and remove', () async {
      final other = (await lib.songs()).firstWhere((t) => t.title == 'X');
      await player.playTracks(album);
      await player.playNext([other]);
      expect(player.state.queue.map((t) => t.title), ['T1', 'X', 'T2', 'T3']);
      expect(uriOf(engine.next!), endsWith('x.mp3'));
      expect(engine.nextSameAlbum, isFalse);
      await player.addToQueue([other]);
      expect(player.state.queue.length, 5);
      await player.move(4, 0);
      expect(player.state.queue.first.title, 'X');
      expect(player.state.current!.title, 'T1');
      await player.removeAt(0);
      expect(player.state.queue.map((t) => t.title), ['T1', 'X', 'T2', 'T3']);
      await player.jumpTo(3);
      expect(player.state.current!.title, 'T3');
    });

    test(
      'MUS-007 the queue survives a restart and resumes at its position',
      () async {
        await player.playTracks(album, start: 1);
        engine.at(const Duration(seconds: 42));
        await settle();
        await player.stop();
        await player.dispose();
        engine = ScriptedMusicEngine();
        player = newPlayer();
        await player.init();
        expect(player.state.current!.title, 'T2');
        expect(player.state.position, const Duration(seconds: 42));
        expect(player.state.playing, isFalse);
        await player.play();
        expect(opened(0), '2.flac');
        expect(engine.current.position, const Duration(seconds: 42));
      },
    );

    test('MUS-007 shuffle keeps the current track first', () async {
      await player.playTracks(album, start: 2, shuffle: true);
      expect(player.state.shuffle, isTrue);
      expect(player.state.index, 0);
      expect(player.state.current!.title, 'T3');
      expect(player.state.queue.map((t) => t.title).toSet(), {
        'T1',
        'T2',
        'T3',
      });
    });
  });

  group('MUS-007 named queues, playlists and history', () {
    test('MUS-007 multiple named queues: add to another queue and switch '
        'back and forth at the saved positions', () async {
      final other = (await lib.songs()).firstWhere((t) => t.title == 'X');
      await player.playTracks(album, start: 1);
      engine.at(const Duration(seconds: 30));
      await settle();
      final road = await player.createQueue('Road trip');
      expect(player.state.queues.map((q) => q.name), ['default', 'Road trip']);
      await player.addToQueueId(road, [other]);
      // The playing queue is untouched.
      expect(player.state.queue.map((t) => t.title), ['T1', 'T2', 'T3']);
      await player.switchQueue(road);
      expect(player.state.queueId, road);
      expect(player.state.queue.map((t) => t.title), ['X']);
      expect(player.state.playing, isFalse);
      final first = player.state.queues.first.id;
      await player.switchQueue(first);
      expect(player.state.current!.title, 'T2');
      expect(player.state.position, const Duration(seconds: 30));
      await player.renameQueue(road, 'Trip');
      expect(player.state.queues.last.name, 'Trip');
      await player.deleteQueue(road);
      expect(player.state.queues.length, 1);
    });

    test('MUS-007 save the queue as a playlist', () async {
      final playlists = PlaylistRepository(db);
      final p = MusicPlayer(
        engine: engine,
        queues: QueueRepository(db),
        library: lib,
        files: localMusicFiles(db),
        playlists: playlists,
        openTimeout: const Duration(milliseconds: 200),
      );
      await p.init();
      await p.playTracks(album);
      final id = await p.saveAsPlaylist('Mine');
      final items =
          await (db.select(db.playlistItems)
                ..where((i) => i.playlistId.equals(id!))
                ..orderBy([(i) => OrderingTerm.asc(i.position)]))
              .get();
      expect(items.map((i) => i.itemId), [for (final t in album) t.itemId]);
      await p.dispose();
    });

    test('MUS-007 history lists finished songs newest first; short songs '
        'count when they play to the end', () async {
      await player.playTracks(album);
      engine.finishTrack();
      await settle();
      await settle();
      engine.finishTrack();
      await settle();
      await settle();
      final h = await lib.history();
      expect(h.map((e) => e.$1.title), ['T2', 'T1']);
      // A manual skip right away is not a play.
      await player.next();
      expect((await lib.history()).length, 2);
    });
  });

  group('MUS-006 media session', () {
    test('MUS-006 session shows the track and lock-screen commands control '
        'the player', () async {
      final session = _FakeSession();
      final dir = await Directory.systemTemp.createTemp('c2_sess');
      addTearDown(() async {
        try {
          await dir.delete(recursive: true);
        } on FileSystemException {
          // Windows may still hold the cover open; the OS cleans temp.
        }
      });
      final art = ArtworkStore(db, dir);
      await art.store(
        album[0].itemId,
        Uint8List.fromList([0xFF, 0xD8, 1]),
        mimeType: 'image/jpeg',
        source: ArtSource.embedded,
      );
      final bridge = MusicSessionBridge(
        player: player,
        session: session,
        art: art,
      )..start();
      await player.playTracks(album);
      await eventually(
        () =>
            session.nowPlaying?.artwork != null &&
            session.status?.state == SessionPlaybackState.playing,
      );
      expect(session.kind, MediaSessionKind.music);
      expect(session.nowPlaying!.title, 'T1');
      expect(session.nowPlaying!.album, 'Al');
      expect(session.nowPlaying!.artwork, isNotNull);
      expect(session.status!.state, SessionPlaybackState.playing);
      expect(session.status!.canSkipNext, isTrue);
      session.send(const PauseCommand());
      await eventually(() => engine.current.status == PlaybackStatus.paused);
      expect(engine.current.status, PlaybackStatus.paused);
      session.send(const NextCommand());
      await eventually(() => player.state.current?.title == 'T2');
      expect(player.state.current!.title, 'T2');
      await bridge.dispose();
    });

    test(
      'MUS-006 the session follows its owner: a playing film takes it '
      'over and music ignores lock-screen commands until it plays again',
      () async {
        final session = _FakeSession();
        final owners = StreamController<MediaSessionKind?>.broadcast();
        var claims = 0;
        var releases = 0;
        final dir = await Directory.systemTemp.createTemp('c2_own');
        addTearDown(() async {
          await owners.close();
          try {
            await dir.delete(recursive: true);
          } on FileSystemException {
            // Best effort on Windows.
          }
        });
        final bridge = MusicSessionBridge(
          player: player,
          session: session,
          art: ArtworkStore(db, dir),
          owner: SessionOwnerLink(
            claim: () => claims++,
            release: () => releases++,
            changes: owners.stream,
          ),
        )..start();
        await player.playTracks(album);
        await eventually(() => session.status != null);
        expect(bridge.owns, isTrue);
        expect(claims, 1);

        // A film starts: music pauses and lets go of the session.
        owners.add(MediaSessionKind.video);
        await eventually(() => engine.current.status == PlaybackStatus.paused);
        expect(bridge.owns, isFalse);
        session
          ..send(const TogglePlayPauseCommand())
          ..send(const NextCommand());
        await settle();
        await settle();
        expect(engine.current.status, PlaybackStatus.paused);
        expect(player.state.current!.title, 'T1');

        // Music plays again: it takes the session back.
        final activations = session.activations;
        await player.play();
        await eventually(() => session.activations > activations);
        expect(bridge.owns, isTrue);
        expect(claims, 2);
        session.send(const PauseCommand());
        await eventually(() => engine.current.status == PlaybackStatus.paused);
        expect(releases, 0);

        // Stopping gives the session back.
        session.send(const StopCommand());
        await eventually(() => releases == 1);
        expect(bridge.owns, isFalse);
        expect(session.kind, isNull);
        await bridge.dispose();
      },
    );

    test('MUS-006 ADR-029 music claims the shared session owner, and a '
        'video claim pauses it', () async {
      final session = _FakeSession();
      final dir = await Directory.systemTemp.createTemp('c2_owner');
      final c = ProviderContainer(
        overrides: [
          libraryDatabaseProvider.overrideWithValue(db),
          appDataDirectoryProvider.overrideWithValue(dir),
          sourceResolverProvider.overrideWithValue(
            localMusicFiles(db).resolver,
          ),
          playbackEngineFactoryProvider.overrideWithValue((_) => engine),
          mediaSessionProvider.overrideWithValue(session),
        ],
      );
      addTearDown(() async {
        c.dispose();
        try {
          await dir.delete(recursive: true);
        } on FileSystemException {
          // Best effort on Windows.
        }
      });
      final player = c.read(musicPlayerProvider);
      await player.init();
      await player.playTracks(album);
      await eventually(() => session.kind != null);
      expect(c.read(mediaSessionOwnerProvider), MediaSessionKind.music);
      c.read(mediaSessionOwnerProvider.notifier).claim(MediaSessionKind.video);
      await eventually(() => engine.current.status == PlaybackStatus.paused);
      expect(engine.current.status, PlaybackStatus.paused);
    });
  });
}

final class _FakeSession implements MediaSessionFacade {
  MediaSessionKind? kind;
  NowPlaying? nowPlaying;
  SessionPlaybackStatus? status;
  final _commands = StreamController<RemoteCommand>.broadcast();

  void send(RemoteCommand c) => _commands.add(c);

  int activations = 0;

  @override
  Future<void> activate(MediaSessionKind kind) async {
    activations++;
    this.kind = kind;
  }

  @override
  Future<void> setNowPlaying(NowPlaying item) async => nowPlaying = item;

  @override
  Future<void> setPlaybackStatus(SessionPlaybackStatus status) async =>
      this.status = status;

  @override
  Stream<RemoteCommand> get commands => _commands.stream;

  @override
  Future<void> deactivate() async => kind = null;
}
