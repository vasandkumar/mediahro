import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mediahro/core/db/library_database.dart';
import 'package:mediahro/core/library/queues.dart';
import 'package:mediahro/features/music/library/music_library.dart';
import 'package:mediahro/features/music/player/music_dsp.dart';
import 'package:mediahro/features/music/player/music_player.dart';
import 'package:mediahro/features/music/player/music_prefs.dart';
import 'package:mediahro/features/music/podcasts/episode_downloads.dart';
import 'package:mediahro/features/music/podcasts/feed_parser.dart';
import 'package:mediahro/features/music/podcasts/podcast_http.dart';
import 'package:mediahro/features/music/podcasts/podcast_player.dart';
import 'package:mediahro/features/music/podcasts/podcast_service.dart';
import 'package:mediahro/features/music/podcasts/podcast_store.dart';
import 'package:mediahro_engine/mediahro_engine.dart';
import 'package:mediahro_ffi/mediahro_ffi.dart'
    show VirtualFile, VirtualFileError, VirtualFileException;

import 'music_test_support.dart';
import 'podcast_test_support.dart' show FakeNet, StubFile;

/// POD-002: playing episodes: where the listener left off, the speed and
/// silence of each show, played marks, carrying on, and ending podcast mode.
void main() {
  late LibraryDatabase db;
  late ScriptedMusicEngine engine;
  late MusicPlayer player;
  late MusicDsp dsp;
  late PodcastStore store;
  late _Downloads downloads;
  late PodcastService service;
  late PodcastPlayer pod;
  late PodcastShow show;
  var now = DateTime.utc(2026, 10, 22, 12);
  var hold = false;

  ParsedEpisode ep(int n) => ParsedEpisode(
    guid: 'g$n',
    title: 'Episode $n',
    url: 'https://cdn.example/e$n.mp3',
    published: DateTime.utc(2025, 6, n),
  );

  Future<void> settle() async {
    for (var i = 0; i < 8; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  PodcastPlayer newPlayer() => PodcastPlayer(
    player: player,
    engine: engine,
    dsp: dsp,
    service: service,
    holdAtEnd: () => hold,
    clock: () => now,
  );

  setUp(() async {
    now = DateTime.utc(2026, 10, 22, 12);
    hold = false;
    db = LibraryDatabase.memory();
    engine = ScriptedMusicEngine();
    player = MusicPlayer(
      engine: engine,
      queues: QueueRepository(db),
      library: MusicLibrary(db),
      files: localMusicFiles(db),
      openTimeout: const Duration(milliseconds: 100),
    );
    await player.init();
    dsp = MusicDsp(engine: engine, prefs: MusicPrefs(db), db: db);
    store = PodcastStore(MusicPrefs(db));
    downloads = _Downloads();
    service = PodcastService(
      store: store,
      http: PodcastHttp(
        send: (r, {maxRedirects = 5}) => throw StateError('no network'),
        beginChain: () =>
            ChainAllowance(allow: (_) {}, close: () {}, run: <T>(b) => b()),
      ),
      downloads: downloads,
      clock: () => now,
    );
    show = PodcastShow(
      id: 'show1',
      url: 'https://show.example/rss',
      title: 'The Show',
      subscribedAt: now,
      // Newest first: 3, 2, 1.
      episodes: [ep(3), ep(2), ep(1)],
    );
    await store.save(show);
    pod = newPlayer();
  });
  tearDown(() async {
    await pod.dispose();
    await service.dispose();
    await player.dispose();
    await db.close();
  });

  String opened() => uriOf(engine.opened.last);

  test('POD-002 an episode streams from its address at normal speed, and '
      'the player shows an episode, not a song', () async {
    await pod.play(show, show.episodes[1]);
    expect(opened(), 'https://cdn.example/e2.mp3');
    // Never an address handed to the engine, which would fetch it with no
    // checks: a file read through the network checks.
    expect(engine.opened.last, isA<VirtualFileSource>());
    expect(engine.current.status, PlaybackStatus.playing);
    expect(player.state.episode?.title, 'Episode 2');
    expect(player.state.episode?.show, 'The Show');
    expect(player.state.spoken, isTrue);
    expect(pod.state.show?.id, 'show1');
    expect(pod.state.offline, isFalse);
    expect(pod.state.speed, 1);
    expect(engine.rates.last, 1);
  });

  test('POD-002 the stream of an episode is closed when the player moves '
      'on, and when it is disposed', () async {
    await pod.play(show, show.episodes[1]);
    await pod.play(show, show.episodes[2]);
    expect(downloads.streamed.map((f) => f.closed), [true, false]);
    await pod.dispose();
    expect(downloads.streamed.last.closed, isTrue);
    pod = newPlayer();
  });

  test('POD-002 an episode that may not be played is refused, nothing is '
      'opened, and the one before keeps playing', () async {
    await pod.play(show, show.episodes[1]);
    final before = engine.opened.length;
    downloads.streamError = VirtualFileException(
      VirtualFileError.permissionDenied,
      Uri.parse('https://cdn.example/e1.mp3'),
    );
    await expectLater(
      pod.play(show, show.episodes[2]),
      throwsA(
        isA<PodcastException>().having(
          (e) => e.reason,
          'reason',
          PodcastFailure.privateAddress,
        ),
      ),
    );
    expect(engine.opened, hasLength(before));
    expect(pod.state.episode?.guid, show.episodes[1].guid);
    expect(downloads.streamed.single.closed, isFalse);
  });

  test('POD-002 pressing play on an episode whose address leads to the '
      "listener's own network fetches nothing there", () async {
    final net = FakeNet()
      ..redirect('https://cdn.example/e2.mp3', 'http://192.168.1.5/e2.mp3')
      ..serve('http://192.168.1.5/e2.mp3', 'AUDIO');
    final fs = HttpUrlFileSystem(net.http, trustedFor: store.feedHostFor);
    final svc = PodcastService(
      store: store,
      http: net.http,
      downloads: _FileSystemDownloads(fs),
    );
    final p = PodcastPlayer(
      player: player,
      engine: engine,
      dsp: dsp,
      service: svc,
      clock: () => now,
    );
    await expectLater(
      p.play(show, show.episodes[1]),
      throwsA(isA<PodcastException>()),
    );
    expect(net.requests.map((r) => r.uri.host), ['cdn.example']);
    expect(net.allowed, ['cdn.example']);
    expect(net.openChains, 0);
    expect(engine.opened, isEmpty);
    await p.dispose();
    await svc.dispose();
  });

  test('POD-002 a downloaded episode plays from the file', () async {
    final f = File('${Directory.systemTemp.path}/c2_pod_e3.mp3');
    downloads.files['https://cdn.example/e3.mp3'] = f;
    await pod.play(show, show.episodes.first);
    expect(opened(), f.uri.toString());
    expect(pod.state.offline, isTrue);
  });

  test('POD-002 it resumes where the listener left off; a played episode '
      'starts over', () async {
    await store.saveProgress(
      'show1',
      'g2',
      const EpisodeProgress(position: Duration(minutes: 1, seconds: 10)),
    );
    await store.saveProgress(
      'show1',
      'g1',
      const EpisodeProgress(played: true),
    );
    await pod.play(show, show.episodes[1]);
    expect(engine.current.position, const Duration(minutes: 1, seconds: 10));
    await pod.play(show, show.episodes[2]);
    expect(engine.current.position, Duration.zero);
  });

  test('POD-002 the place is saved when pausing and every few seconds '
      'while playing, not for the first few seconds', () async {
    await pod.play(show, show.episodes.first);
    engine.at(const Duration(seconds: 3));
    await settle();
    expect((await store.progress('show1')).containsKey('g3'), isFalse);
    now = now.add(const Duration(seconds: 6));
    engine.at(const Duration(seconds: 30));
    await settle();
    expect(
      (await store.progress('show1'))['g3']!.position,
      const Duration(seconds: 30),
    );
    engine.at(const Duration(seconds: 41));
    await player.pause();
    await settle();
    expect(
      (await store.progress('show1'))['g3']!.position,
      const Duration(seconds: 41),
    );
  });

  test('POD-002 speed and skip silence are remembered by the show; the '
      'next show starts at the last speed', () async {
    await pod.play(show, show.episodes.first);
    await pod.setSpeed(1.8);
    await pod.setSkipSilence(enabled: true);
    expect(engine.rates.last, 1.8);
    expect(engine.dsp?.skipSilence, isTrue);
    final saved = (await store.show('show1'))!;
    expect(saved.speed, 1.8);
    expect(saved.skipSilence, isTrue);
    expect(await store.lastSpeed(), 1.8);

    final other = PodcastShow(
      id: 'show2',
      url: 'https://other.example/rss',
      title: 'Other',
      subscribedAt: now,
      episodes: [ep(9)],
    );
    await store.save(other);
    await pod.play(other, other.episodes.single);
    expect(pod.state.speed, 1.8);
    expect(pod.state.skipSilence, isFalse);
    expect(engine.dsp?.skipSilence, isFalse);
    // And the first show comes back to its own settings.
    await pod.play(saved, saved.episodes.first);
    expect(pod.state.speed, 1.8);
    expect(pod.state.skipSilence, isTrue);
  });

  test('POD-002 near the end the episode is marked played; it starts over '
      'next time', () async {
    await pod.play(show, show.episodes[1]);
    // The scripted engine's episodes are 3 minutes long.
    engine.at(const Duration(minutes: 2, seconds: 45));
    await settle();
    expect((await store.progress('show1'))['g2']!.played, isTrue);
    expect(await service.unplayedCounts(), {'show1': 2});
    await pod.pause();
    await settle();
    final p = (await store.progress('show1'))['g2']!;
    expect(p.played, isTrue);
    expect(p.position, Duration.zero);
  });

  test("POD-002 when an episode ends the next unplayed one in the show's "
      'order starts', () async {
    await store.saveProgress(
      'show1',
      'g2',
      const EpisodeProgress(played: true),
    );
    await pod.play(show, show.episodes.first);
    engine.finishTrack();
    await settle();
    // Newest first: after 3 comes 2 (played), then 1.
    expect(opened(), 'https://cdn.example/e1.mp3');
    expect(pod.state.episode?.guid, 'g1');
    expect(player.state.episode?.title, 'Episode 1');
    expect((await store.progress('show1'))['g3']!.played, isTrue);
    engine.finishTrack();
    await settle();
    expect(opened(), 'https://cdn.example/e1.mp3');
    expect(engine.current.status, PlaybackStatus.ended);
  });

  test('POD-002 oldest-first shows carry on the other way; a sleep timer '
      'that stops at the end holds the next episode back', () async {
    await service.configure('show1', oldestFirst: true);
    final s = (await store.show('show1'))!;
    await pod.play(s, s.episodes[2]);
    hold = true;
    engine.finishTrack();
    await settle();
    expect(opened(), 'https://cdn.example/e1.mp3');
    expect(engine.current.status, PlaybackStatus.ended);
    hold = false;
    await pod.play(s, s.episodes[2]);
    engine.finishTrack();
    await settle();
    expect(opened(), 'https://cdn.example/e2.mp3');
  });

  test('POD-002 next and previous in an episode skip ahead and back, '
      'whatever the lock screen asks', () async {
    await pod.play(show, show.episodes.first);
    engine.at(const Duration(seconds: 100));
    await settle();
    await player.next();
    expect(engine.current.position, const Duration(seconds: 130));
    await player.previous();
    expect(engine.current.position, const Duration(seconds: 120));
    await pod.skip(const Duration(seconds: -200));
    expect(engine.current.position, Duration.zero);
  });

  test('POD-002 playing music ends podcast mode: the place is saved and '
      'the speed goes back to normal', () async {
    await MusicSeed(db).song('x/1.mp3', title: 'Song');
    final song = (await MusicLibrary(db).songs()).single;
    await pod.play(show, show.episodes.first);
    await pod.setSpeed(2);
    await pod.setSkipSilence(enabled: true);
    engine.at(const Duration(minutes: 1));
    await settle();
    await player.playTracks([song]);
    await settle();
    expect(pod.state.active, isFalse);
    expect(player.state.episode, isNull);
    expect(engine.rates.last, 1);
    expect(engine.dsp?.skipSilence, isFalse);
    expect(
      (await store.progress('show1'))['g3']!.position,
      const Duration(minutes: 1),
    );
  });

  test('POD-002 the speed belongs to the show: an engine that fell back to '
      'normal speed is put back', () async {
    await pod.play(show, show.episodes.first);
    await pod.setSpeed(1.5);
    await engine.setRate(1);
    await settle();
    expect(engine.current.rate, 1.5);
  });
}

/// Streams through a real file system, downloads nothing.
final class _FileSystemDownloads implements EpisodeDownloads {
  _FileSystemDownloads(this.fs);

  final HttpUrlFileSystem fs;

  @override
  Future<void> enqueue(Uri url, {required String title, int? size}) async {}

  @override
  Future<EpisodeDownload?> status(Uri url) async => null;

  @override
  Future<void> remove(Uri url) async {}

  @override
  Future<VirtualFile> openStream(Uri url) => fs.open(url);
}

final class _Downloads implements EpisodeDownloads {
  final files = <String, File>{};

  @override
  Future<void> enqueue(Uri url, {required String title, int? size}) async {}

  @override
  Future<EpisodeDownload?> status(Uri url) async {
    final f = files[url.toString()];
    return f == null ? null : EpisodeDownload(DownloadState.done, file: f);
  }

  @override
  Future<void> remove(Uri url) async {}

  final streamed = <StubFile>[];
  Exception? streamError;

  @override
  Future<VirtualFile> openStream(Uri url) async {
    final e = streamError;
    if (e != null) throw e;
    final f = StubFile(url);
    streamed.add(f);
    return f;
  }
}
