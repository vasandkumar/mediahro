import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mediahro/core/db/library_database.dart';
import 'package:mediahro/core/library/queues.dart';
import 'package:mediahro/core/parsers/playlist_parser.dart';
import 'package:mediahro/features/music/library/artwork_store.dart';
import 'package:mediahro/features/music/library/music_library.dart';
import 'package:mediahro/features/music/player/music_player.dart';
import 'package:mediahro/features/music/player/music_prefs.dart';
import 'package:mediahro/features/music/player/music_session.dart';
import 'package:mediahro/features/music/radio/radio_stations.dart';
import 'package:mediahro/platform/platform_facades.dart';

import 'music_test_support.dart';

void main() {
  late LibraryDatabase db;

  setUp(() => db = LibraryDatabase.memory());
  tearDown(() => db.close());

  group('MUS-014 stations', () {
    test('MUS-014 add, edit, favourite, delete; persisted', () async {
      final r = RadioStations(MusicPrefs(db));
      final s = RadioStation(
        id: r.newId(),
        name: 'Jazz FM',
        url: Uri.parse('https://stream.example/jazz'),
        headers: const {'User-Agent': 'x'},
      );
      await r.save(s);
      await r.save(s.copyWith(favourite: true));
      final again = await RadioStations(MusicPrefs(db)).all();
      expect(again.single.favourite, isTrue);
      expect(again.single.headers, {'User-Agent': 'x'});
      await r.delete(s.id);
      expect(await RadioStations(MusicPrefs(db)).all(), isEmpty);
    });

    test('MUS-014 only stream URLs; import M3U/PLS skips files and '
        'duplicates; export M3U', () async {
      expect(isStreamUrl(Uri.parse('http://a.b/x')), isTrue);
      expect(isStreamUrl(Uri.parse('file:///x.mp3')), isFalse);
      expect(isStreamUrl(Uri.parse('javascript:alert(1)')), isFalse);
      final r = RadioStations(MusicPrefs(db), nonPublic: (_) async => false);
      final m3u = parsePlaylist(
        '#EXTM3U\n#EXTINF:-1,One\nhttp://one.example/live\n'
        '#EXTINF:-1,Local file\n/sdcard/song.mp3\n'
        'https://two.example/hls.m3u8\nhttp://one.example/live\n',
        PlaylistFormat.m3u,
      );
      expect(await r.importPlaylist(m3u), 2);
      final pls = parsePlaylist(
        '[playlist]\nFile1=http://three.example:8000/;\nTitle1=Three\nNumberOfEntries=1\n',
        PlaylistFormat.pls,
      );
      expect(await r.importPlaylist(pls), 1);
      final all = await r.all();
      expect(all.map((s) => s.name), ['One', 'two.example', 'Three']);
      final out = await r.exportM3u();
      expect(out, startsWith('#EXTM3U'));
      expect(out, contains('#EXTINF:-1,Three'));
      expect(parsePlaylist(out, PlaylistFormat.m3u).entries.length, 3);
    });
  });

  group('MUS-014 live playback', () {
    late ScriptedMusicEngine engine;
    late MusicPlayer player;
    late List<MusicTrack> songs;

    setUp(() async {
      final seed = MusicSeed(db);
      await seed.song(
        'a/1.flac',
        title: 'One',
        album: 'A',
        albumArtist: 'X',
        track: 1,
      );
      await seed.song(
        'a/2.flac',
        title: 'Two',
        album: 'A',
        albumArtist: 'X',
        track: 2,
      );
      songs = await MusicLibrary(db)
          .albumTracks((await MusicLibrary(db).albums()).single.groupKey);
      engine = ScriptedMusicEngine();
      player = MusicPlayer(
        engine: engine,
        queues: QueueRepository(db),
        library: MusicLibrary(db),
        files: localMusicFiles(db),
        openTimeout: const Duration(milliseconds: 100),
      );
      await player.init();
    });
    tearDown(() => player.dispose());

    test('MUS-014 a station plays as a stream: no queue hand-off, no skip; '
        'the queue resumes from where it was', () async {
      await player.playTracks(songs);
      expect(engine.next, isNotNull);
      final st = RadioStation(
        id: 's1',
        name: 'News',
        url: Uri.parse('http://news.example/live'),
      );
      await player.playStation(st);
      expect(player.state.live, isTrue);
      expect(uriOf(engine.opened.last), 'http://news.example/live');
      expect(engine.next, isNull);
      expect(player.state.hasNext, isFalse);
      // Stream metadata changes bump the item counter: no queue advance.
      engine.finishTrack();
      await Future<void>.delayed(Duration.zero);
      expect(player.state.index, 0);
      await player.next();
      expect(uriOf(engine.opened.last), 'http://news.example/live');
      // Pause, then play reopens a stopped stream.
      await player.pause();
      await engine.stop();
      await player.play();
      expect(uriOf(engine.opened.last), 'http://news.example/live');
      // Back to the queue.
      await player.jumpTo(1);
      expect(player.state.live, isFalse);
      expect(player.state.current!.title, 'Two');
    });

    test('MUS-014 the media session shows a live item', () async {
      final session = _Session();
      final dir = Directory.systemTemp.createTempSync('c2_radio');
      addTearDown(() {
        try {
          dir.deleteSync(recursive: true);
        } on FileSystemException {
          // Best effort.
        }
      });
      final bridge = MusicSessionBridge(
        player: player,
        session: session,
        art: ArtworkStore(db, dir),
      )..start();
      await player.playStation(
        RadioStation(id: 's', name: 'Live One', url: Uri.parse('http://x.y/z')),
      );
      for (var i = 0; i < 50 && session.now == null; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(session.now!.title, 'Live One');
      expect(session.now!.isLive, isTrue);
      expect(session.now!.duration, isNull);
      await bridge.dispose();
    });
  });
}

final class _Session implements MediaSessionFacade {
  NowPlaying? now;

  @override
  Future<void> activate(MediaSessionKind kind) async {}

  @override
  Stream<RemoteCommand> get commands => const Stream.empty();

  @override
  Future<void> deactivate() async {}

  @override
  Future<void> setNowPlaying(NowPlaying item) async => now = item;

  @override
  Future<void> setPlaybackStatus(SessionPlaybackStatus status) async {}
}
