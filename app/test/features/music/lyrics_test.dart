import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mediahro/core/db/library_database.dart';
import 'package:mediahro/core/net/network_policy.dart';
import 'package:mediahro/features/music/library/music_library.dart';
import 'package:mediahro/features/music/lyrics/lrc.dart';
import 'package:mediahro/features/music/lyrics/lyrics_service.dart';
import 'package:mediahro/features/music/tags/audio_tags.dart';
import 'package:mediahro/features/music/tags/tag_reader.dart';
import 'package:mediahro_servers/mediahro_servers.dart';

import 'music_test_support.dart';
import 'tag_fixtures.dart';

void main() {
  group('MUS-005 LRC', () {
    test('MUS-005 parses timestamps, repeats, metadata and offset', () {
      final l = parseLyrics('''
[ti:Song]
[ar:Artist]
[offset:500]
[00:12.00]First line
[00:05.5][01:00.25]Chorus
not timed comment
''');
      expect(l.synced, isTrue);
      expect(l.title, 'Song');
      expect(l.artist, 'Artist');
      expect(l.lines.map((x) => (x.time, x.text)), [
        (const Duration(seconds: 5), 'Chorus'),
        (const Duration(milliseconds: 11500), 'First line'),
        (const Duration(milliseconds: 59750), 'Chorus'),
      ]);
      expect(l.lineAt(const Duration(seconds: 4)), -1);
      expect(l.lineAt(const Duration(seconds: 30)), 1);
    });

    test('MUS-005 enhanced LRC word timings and round trip', () {
      final l = parseLyrics(
        '[00:01.00]<00:01.00>Hello <00:01.50>big <00:02.00>world',
      );
      expect(l.wordSynced, isTrue);
      expect(l.lines.single.text, 'Hello big world');
      expect(l.lines.single.words.map((w) => w.time.inMilliseconds), [
        1000,
        1500,
        2000,
      ]);
      final again = parseLyrics(toLrc(l));
      expect(again.lines, l.lines);
    });

    test('MUS-005 plain text stays unsynced; blank edges trimmed', () {
      final l = parseLyrics('\n\nOne\n\nTwo\n\n');
      expect(l.synced, isFalse);
      expect(l.lines.map((x) => x.text), ['One', '', 'Two']);
      expect(toLrc(l).trim(), 'One\n\nTwo');
    });

    test('MUS-005 hostile input is bounded', () {
      final big = List.filled(50000, '[99:99.999]x').join('\n');
      expect(parseLyrics(big).lines.length, 20000);
      expect(parseLyrics('[abc][::]<>').lines, isNotEmpty);
    });

    test('MUS-005 tap-to-time editor stamps, skips blanks, undoes, nudges', () {
      final e = LrcEditorModel(parseLyrics('One\n\nTwo\nThree'))
        ..tap(const Duration(seconds: 1))
        ..tap(const Duration(seconds: 3));
      expect(e.lines[0].time, const Duration(seconds: 1));
      expect(e.lines[1].time, isNull); // blank skipped
      expect(e.lines[2].time, const Duration(seconds: 3));
      e.back();
      expect(e.lines[2].time, isNull);
      e
        ..tap(const Duration(seconds: 4))
        ..nudge(0, const Duration(milliseconds: -2000));
      expect(e.lines[0].time, Duration.zero);
      e.tap(const Duration(seconds: 6));
      expect(e.done, isTrue);
      final r = e.result();
      expect(r.synced, isTrue);
      expect(r.origin, LyricsOrigin.edited);
      expect(r.lines.map((x) => x.text), ['One', 'Two', 'Three']);
    });
  });

  group('MUS-005 sources', () {
    late Directory dir;
    late LibraryDatabase db;
    late MusicTrack track;
    late _FakeHttp http;
    var online = false;

    LyricsService service() => LyricsService(
      files: localMusicFiles(db),
      cacheDir: Directory('${dir.path}/cache'),
      readTags: TagReader.readVirtualFile,
      transport: http,
      onlineEnabled: () => online,
    );

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('c2_lyrics');
      db = LibraryDatabase.memory();
      http = _FakeHttp();
      online = false;
      final seed = MusicSeed(db);
      await seed.source(dir.uri.toString());
      Directory('${dir.path}/a').createSync();
      File('${dir.path}/a/song.mp3').writeAsBytesSync(
        bytesOf([
          id3v2(4, [id3Uslt(4, 'Embedded words')]),
          mpegAudio,
        ]),
      );
      await seed.song(
        'a/song.mp3',
        title: 'Song',
        artist: 'Amy',
        album: 'Al',
        durationMs: 200000,
      );
      track = (await MusicLibrary(db).songs()).single;
    });
    tearDown(() async {
      await db.close();
      try {
        await dir.delete(recursive: true);
      } on FileSystemException {
        // Windows may hold a file briefly.
      }
    });

    test('MUS-005 embedded, then sidecar wins, then edited wins', () async {
      final s = service();
      expect((await s.forTrack(track))!.toPlainText(), 'Embedded words');
      File('${dir.path}/a/song.lrc').writeAsStringSync('[00:01.00]Sidecar');
      final side = await s.forTrack(track);
      expect(side!.origin, LyricsOrigin.sidecar);
      expect(side.synced, isTrue);
      await s.saveEdited(
        track,
        const Lyrics([LyricLine('Mine', time: Duration(seconds: 2))]),
      );
      final edited = await s.forTrack(track);
      expect(edited!.origin, LyricsOrigin.edited);
      expect(edited.lines.single.text, 'Mine');
      await s.deleteEdited(track);
      expect((await s.forTrack(track))!.origin, LyricsOrigin.sidecar);
    });

    test('MUS-005 SYLT synced lyrics are used as synced', () async {
      File('${dir.path}/a/song.mp3').writeAsBytesSync(
        bytesOf([
          id3v2(4, [
            id3Sylt(4, [(1000, 'a'), (2000, 'b')]),
          ]),
          mpegAudio,
        ]),
      );
      final l = await service().forTrack(track);
      expect(l!.synced, isTrue);
      expect(l.lines.map((x) => x.text), ['a', 'b']);
    });

    test('MUS-005 LRCLIB only when switched on; exact match, then search; '
        'results are cached', () async {
      File('${dir.path}/a/song.mp3').writeAsBytesSync(bytesOf([mpegAudio]));
      http.responses['/api/get'] = (404, '{"message":"not found"}');
      http.responses['/api/search'] = (
        200,
        jsonEncode([
          {'duration': 150, 'syncedLyrics': '[00:01.00]wrong'},
          {
            'duration': 201,
            'syncedLyrics': '[00:01.00]right',
            'plainLyrics': 'right',
          },
        ]),
      );
      expect(await service().forTrack(track), isNull);
      expect(http.requests, isEmpty);
      online = true;
      final l = await service().forTrack(track);
      expect(l!.origin, LyricsOrigin.online);
      expect(l.lines.single.text, 'right');
      final get = http.requests.first;
      expect(get.host, 'lrclib.net');
      expect(get.queryParameters, {
        'track_name': 'Song',
        'artist_name': 'Amy',
        'album_name': 'Al',
        'duration': '200',
      });
      // Cached: no second request, also with the endpoint off.
      online = false;
      http.requests.clear();
      expect((await service().forTrack(track))!.origin, LyricsOrigin.online);
      expect(http.requests, isEmpty);
    });

    test('MUS-005 a blocked endpoint surfaces as NetworkBlocked', () async {
      File('${dir.path}/a/song.mp3').writeAsBytesSync(bytesOf([mpegAudio]));
      http.blocked = true;
      online = true;
      await expectLater(
        service().forTrack(track),
        throwsA(isA<NetworkBlocked>()),
      );
      expect(isEndpointOff(const NetworkBlocked('lrclib.net', 'off')), isTrue);
    });
  });

  test('MUS-005 AudioTags exposes plain lyrics', () {
    expect(
      const AudioTags(
        fields: {
          TagField.lyrics: ['x'],
        },
      ).lyrics,
      'x',
    );
  });
}

final class _FakeHttp implements HttpTransport {
  final requests = <Uri>[];
  final responses = <String, (int, String)>{};
  bool blocked = false;

  @override
  Future<HttpResponseData> send(HttpRequestData request) async {
    if (blocked) throw NetworkBlocked(request.uri.host, 'endpoint off');
    requests.add(request.uri);
    final r = responses[request.uri.path] ?? (404, '');
    return HttpResponseData(statusCode: r.$1, body: utf8.encode(r.$2));
  }
}
