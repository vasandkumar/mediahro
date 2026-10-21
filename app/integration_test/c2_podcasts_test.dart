import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mediahro/core/db/library_database.dart';
import 'package:mediahro/core/files/file_systems.dart';
import 'package:mediahro/core/library/queues.dart';
import 'package:mediahro/core/net/network_policy.dart';
import 'package:mediahro/core/sources/downloads.dart';
import 'package:mediahro/features/music/library/music_library.dart';
import 'package:mediahro/features/music/player/music_dsp.dart';
import 'package:mediahro/features/music/player/music_player.dart';
import 'package:mediahro/features/music/player/music_prefs.dart';
import 'package:mediahro/features/music/podcasts/episode_downloads.dart';
import 'package:mediahro/features/music/podcasts/podcast_http.dart';
import 'package:mediahro/features/music/podcasts/podcast_player.dart';
import 'package:mediahro/features/music/podcasts/podcast_service.dart';
import 'package:mediahro/features/music/podcasts/podcast_store.dart';
import 'package:mediahro_engine/mediahro_engine.dart';

import '../test/features/music/music_test_support.dart';

/// Lane C2 on real devices (POD-002): a feed on a loopback server is
/// subscribed to through the network gateway (conditional refresh), an
/// episode is downloaded with the download manager over HTTP range
/// requests, and libmpv plays the downloaded file and the streamed one,
/// with the place saved.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('c2pod');
  });
  tearDown(() async {
    try {
      await dir.delete(recursive: true);
    } on FileSystemException {
      // Best effort.
    }
  });

  /// [seconds] of a quiet 330 Hz tone, 8 kHz mono WAV.
  Uint8List tone(int seconds) {
    const rate = 8000;
    final frames = rate * seconds;
    final b = ByteData(44 + frames * 2);
    void str(int at, String s) {
      for (var i = 0; i < s.length; i++) {
        b.setUint8(at + i, s.codeUnitAt(i));
      }
    }

    str(0, 'RIFF');
    b.setUint32(4, 36 + frames * 2, Endian.little);
    str(8, 'WAVE');
    str(12, 'fmt ');
    b
      ..setUint32(16, 16, Endian.little)
      ..setUint16(20, 1, Endian.little)
      ..setUint16(22, 1, Endian.little)
      ..setUint32(24, rate, Endian.little)
      ..setUint32(28, rate * 2, Endian.little)
      ..setUint16(32, 2, Endian.little)
      ..setUint16(34, 16, Endian.little);
    str(36, 'data');
    b.setUint32(40, frames * 2, Endian.little);
    for (var i = 0; i < frames; i++) {
      final v = (math.sin(2 * math.pi * 330 * i / rate) * 3000).round();
      b.setInt16(44 + i * 2, v, Endian.little);
    }
    return b.buffer.asUint8List();
  }

  testWidgets('POD-002 subscribe, refresh with ETag, download, and play '
      'both the file and the stream', (tester) async {
    if (!MpvEngine.isAvailable) {
      return markTestSkipped('blocked: libmpv is not bundled in this build');
    }
    await tester.runAsync(() async {
      final audio = tone(20);
      var feedHits = 0;
      var notModified = 0;
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final base = 'http://127.0.0.1:${server.port}';
      server.listen((r) async {
        final path = r.uri.path;
        if (path == '/rss') {
          feedHits++;
          if (r.headers.value('if-none-match') == '"v1"') {
            notModified++;
            r.response.statusCode = 304;
            await r.response.close();
            return;
          }
          r.response.headers
            ..set('etag', '"v1"')
            ..contentType = ContentType('application', 'rss+xml');
          r.response.write('''
<rss version="2.0" xmlns:itunes="http://www.itunes.com/dtds/podcast-1.0.dtd">
<channel><title>Loopback Cast</title>
<item><title>Pilot</title><guid>pilot</guid>
<pubDate>Tue, 10 Jun 2025 04:00:00 GMT</pubDate>
<enclosure url="$base/pilot.wav" length="${audio.length}" type="audio/wav"/>
<itunes:duration>20</itunes:duration></item>
</channel></rss>''');
          await r.response.close();
          return;
        }
        if (path == '/pilot.wav') {
          final range = RegExp(r'bytes=(\d+)-(\d*)')
              .firstMatch(r.headers.value('range') ?? '');
          r.response.headers
            ..set('accept-ranges', 'bytes')
            ..contentType = ContentType('audio', 'wav');
          if (range == null) {
            r.response.add(audio);
          } else {
            final from = int.parse(range.group(1)!);
            final to = range.group(2)!.isEmpty
                ? audio.length - 1
                : math.min(int.parse(range.group(2)!), audio.length - 1);
            r.response
              ..statusCode = 206
              ..headers.set('content-range', 'bytes $from-$to/${audio.length}')
              ..add(audio.sublist(from, to + 1));
          }
          await r.response.close();
          return;
        }
        r.response.statusCode = 404;
        await r.response.close();
      });

      final db = LibraryDatabase.memory();
      final gateway = NetworkGateway(_AllowAll());
      final http = PodcastHttp(
        send: gateway.sendStreamed,
        beginChain: () =>
            ChainAllowance(allow: (_) {}, close: () {}, run: <T>(b) => b()),
      );
      final mounts = MountedFileSystems();
      final manager = DownloadManager(
        db: db,
        directory: Directory('${dir.path}/downloads'),
        opener: (uri) => mounts.forUri(uri).open(uri),
      );
      final downloads = ManagerEpisodeDownloads(
        manager: manager,
        mounts: mounts,
        // The feed is on the loopback server the test started, so its
        // enclosure there is its own host.
        fileSystem: HttpUrlFileSystem(
          http,
          trustedFor: (_) async => {InternetAddress.loopbackIPv4.host},
        ),
      );
      final store = PodcastStore(MusicPrefs(db));
      final service = PodcastService(
        store: store,
        http: http,
        downloads: downloads,
      );

      final show = await service.subscribe('$base/rss');
      expect(show.title, 'Loopback Cast');
      expect(show.episodes.single.duration, const Duration(seconds: 20));
      final again = await service.refresh(show.id);
      expect(again.ok, isTrue);
      expect(again.added, 0);
      expect(feedHits, 2);
      expect(notModified, 1, reason: 'the second check used the ETag');

      final episode = show.episodes.single;
      await service.download(show, episode);
      for (var i = 0; i < 100; i++) {
        final d = await downloads.status(Uri.parse(episode.url));
        if (d != null && d.done) break;
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      final file = await service.localFile(episode);
      expect(file, isNotNull, reason: 'the download finished');
      expect(file!.lengthSync(), audio.length);

      final engine = MpvEngine(EngineRole.music);
      final player = MusicPlayer(
        engine: engine,
        queues: QueueRepository(db),
        library: MusicLibrary(db),
        files: localMusicFiles(db),
      );
      await player.init();
      final pod = PodcastPlayer(
        player: player,
        engine: engine,
        dsp: MusicDsp(engine: engine, prefs: MusicPrefs(db), db: db),
        service: service,
      );
      Future<void> until(bool Function() done) async {
        for (var i = 0; i < 100 && !done(); i++) {
          await Future<void>.delayed(const Duration(milliseconds: 50));
        }
      }

      // The downloaded copy first.
      await pod.play(show, episode);
      await until(() => engine.current.status == PlaybackStatus.playing);
      expect(pod.state.offline, isTrue);
      expect(engine.current.status, PlaybackStatus.playing);
      await pod.setSpeed(1.5);
      await until(() => engine.current.rate == 1.5);
      expect(engine.current.rate, 1.5);
      await pod.seek(const Duration(seconds: 8));
      await pod.pause();
      await until(() => engine.current.status == PlaybackStatus.paused);
      final saved = (await store.progress(show.id))[episode.guid]!;
      expect(saved.position, greaterThanOrEqualTo(const Duration(seconds: 7)));
      expect(saved.played, isFalse);

      // Without the file it streams, resuming where it was left.
      await service.removeDownload(episode);
      expect(await service.localFile(episode), isNull);
      await pod.play((await store.show(show.id))!, episode);
      await until(() => engine.current.status == PlaybackStatus.playing);
      expect(pod.state.offline, isFalse);
      expect(engine.current.error, isNull);
      expect(
        engine.current.position,
        greaterThanOrEqualTo(const Duration(seconds: 6)),
      );
      expect(pod.state.speed, 1.5);

      await pod.dispose();
      await player.dispose();
      await engine.dispose();
      await service.dispose();
      await server.close(force: true);
      await db.close();
    });
  });
}

/// Every address is allowed: the test talks to its own loopback server.
final class _AllowAll implements NetworkPolicy {
  @override
  bool isEnabled(NetworkEndpoint endpoint) => true;

  @override
  bool isUserConfiguredHost(String host) => true;

  @override
  void recordUse(NetworkEndpoint endpoint, DateTime at) {}
}
