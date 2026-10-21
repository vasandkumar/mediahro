import 'package:flutter_test/flutter_test.dart';
import 'package:mediahro/core/db/library_database.dart';
import 'package:mediahro/core/library/playlists.dart';
import 'package:mediahro/core/library/queues.dart';
import 'package:mediahro/features/music/library/music_library.dart';
import 'package:mediahro/features/music/library/music_playlists.dart';
import 'package:mediahro/features/music/music_incoming.dart';
import 'package:mediahro/features/music/player/music_player.dart';
import 'package:mediahro_engine/mediahro_engine.dart';
import 'package:mediahro_ffi/mediahro_ffi.dart';

import 'music_test_support.dart';
import 'podcast_test_support.dart' show StubFile;

/// CORE-003, SYS-003, SYS-004: what other apps hand to Music.
void main() {
  late LibraryDatabase db;
  late ScriptedMusicEngine engine;
  late MusicPlayer player;
  late MusicPlaylists playlists;
  late MusicIncoming incoming;
  late List<StubFile> opened;
  var refuse = false;

  setUp(() async {
    refuse = false;
    opened = [];
    db = LibraryDatabase.memory();
    engine = ScriptedMusicEngine();
    final lib = MusicLibrary(db);
    player = MusicPlayer(
      engine: engine,
      queues: QueueRepository(db),
      library: lib,
      files: localMusicFiles(db),
      openTimeout: const Duration(milliseconds: 100),
    );
    await player.init();
    playlists = MusicPlaylists(db, PlaylistRepository(db), lib);
    incoming = MusicIncoming(
      player: player,
      playlists: playlists,
      open: (uri) async {
        if (refuse) {
          throw VirtualFileException(VirtualFileError.notFound, uri);
        }
        final f = StubFile(uri);
        opened.add(f);
        return f;
      },
    );
    final seed = MusicSeed(db);
    await seed.song('a/1.flac', title: 'One', artist: 'A', album: 'X');
    await seed.song('a/2.flac', title: 'Two', artist: 'A', album: 'X');
  });
  tearDown(() async {
    await player.dispose();
    await db.close();
  });

  group('playExternalAudio', () {
    test('SYS-004 a file plays as its own item: titled by its name, not in '
        'the library, at normal speed', () async {
      await engine.setRate(1.5);
      final ok = await incoming.playExternalAudio(
        Uri.parse('file:///music/dir/My%20Song.mp3'),
      );
      expect(ok, isTrue);
      expect(engine.opened.last, isA<UriSource>());
      expect(uriOf(engine.opened.last), 'file:///music/dir/My%20Song.mp3');
      expect(player.state.episode?.title, 'My Song');
      expect(player.state.spoken, isTrue);
      expect(engine.rates.last, 1);
      expect(player.state.queue, isEmpty);
    });

    test(
      'SYS-004 a web link is left to the video player, which checks it '
      'like any link, and never handed to the engine as an address',
      () async {
        // Nothing the listener added serves it.
        refuse = true;
        expect(
          await incoming.playExternalAudio(
            Uri.parse('https://example.org/a.mp3'),
          ),
          isFalse,
        );
        expect(
          await incoming.playExternalAudio(
            Uri.parse('http://example.org/a.mp3'),
          ),
          isFalse,
        );
        expect(engine.opened, isEmpty);
      },
    );

    test('CORE-003 a content address plays through the file that serves it, '
        'and the file is let go when the next one starts', () async {
      expect(
        await incoming.playExternalAudio(
          Uri.parse(
            'content://com.android.externalstorage.documents/document/'
            'primary%3AMusic%2FSong.mp3',
          ),
        ),
        isTrue,
      );
      expect(engine.opened.last, isA<VirtualFileSource>());
      expect(player.state.episode?.title, 'Song');
      expect(opened.single.closed, isFalse);
      await incoming.playExternalAudio(Uri.parse('content://x/y/Other.flac'));
      expect(opened.first.closed, isTrue);
      expect(opened.last.closed, isFalse);
    });

    test(
      'SYS-004 an address nothing serves is left to the video player',
      () async {
        refuse = true;
        expect(
          await incoming.playExternalAudio(Uri.parse('smb://nas/share/a.mp3')),
          isFalse,
        );
        expect(engine.opened, isEmpty);
        expect(player.state.episode, isNull);
      },
    );

    test('the queue keeps its place while a file plays', () async {
      final tracks = await MusicLibrary(db).songs();
      await player.playTracks(tracks);
      final before = player.state.queue.length;
      await incoming.playExternalAudio(Uri.parse('file:///music/x.mp3'));
      expect(player.state.queue, hasLength(before));
      expect(player.state.episode?.title, 'x');
    });

    test('titles read well', () {
      String t(String u) => MusicIncoming.titleOf(Uri.parse(u));
      expect(t('file:///a/b/Track.01.flac'), 'Track.01');
      expect(t('content://media/external/audio/media/1234'), '1234');
      expect(t('https://example.org/'), 'example.org');
      expect(t('content://x/document/primary%3AMusic%2FA%20B.m4a'), 'A B');
    });
  });

  group('playPlaylistByName', () {
    test(
      'SYS-003 starts the playlist called exactly that, in any case',
      () async {
        final songs = await MusicLibrary(db).songs();
        final mix = await playlists.createManual('Morning Mix');
        await playlists.add(mix, songs.reversed.toList());
        final other = await playlists.createManual('Morning');
        await playlists.add(other, [songs.first]);
        expect(await incoming.playPlaylistByName('  morning MIX '), isTrue);
        expect(player.state.queue.map((t) => t.title), ['Two', 'One']);
        expect(await incoming.playPlaylistByName('MORNING'), isTrue);
        expect(player.state.queue.map((t) => t.title), ['One']);
        // A part of a name is not the name.
        engine.opened.clear();
        expect(await incoming.playPlaylistByName('mix'), isFalse);
        expect(await incoming.playPlaylistByName('Morn'), isFalse);
        expect(engine.opened, isEmpty);
      },
    );

    test('SYS-003 no such playlist, an empty one or no name: false, nothing '
        'played', () async {
      await playlists.createManual('Empty');
      expect(await incoming.playPlaylistByName('nope'), isFalse);
      expect(await incoming.playPlaylistByName('Empty'), isFalse);
      expect(await incoming.playPlaylistByName('  '), isFalse);
      expect(engine.opened, isEmpty);
    });

    test('LIB-013 hidden songs never play from a request, and a playlist of '
        'only hidden songs is not started', () async {
      final songs = await MusicLibrary(db).songs();
      final mix = await playlists.createManual('Mix');
      await playlists.add(mix, songs);
      final secret = await playlists.createManual('Secret');
      await playlists.add(secret, [songs.last]);
      await db.customStatement(
        "UPDATE item SET hidden = 1 WHERE rel_path = 'a/2.flac'",
      );
      expect(await incoming.playPlaylistByName('mix'), isTrue);
      expect(player.state.queue.map((t) => t.title), ['One']);
      engine.opened.clear();
      expect(await incoming.playPlaylistByName('secret'), isFalse);
      expect(engine.opened, isEmpty);
    });
  });
}
