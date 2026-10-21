import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mediahro/core/db/library_database.dart';
import 'package:mediahro/core/library/queues.dart';
import 'package:mediahro/features/music/library/music_library.dart';
import 'package:mediahro/features/music/player/music_player.dart';
import 'package:mediahro/features/music/player/music_prefs.dart';
import 'package:mediahro/features/music/radio/radio_stations.dart';
import 'package:mediahro/features/music/scrobble/scrobble_services.dart';
import 'package:mediahro/features/music/scrobble/scrobbler.dart';
import 'package:mediahro_engine/mediahro_engine.dart';

import '../test/features/music/music_test_support.dart';

/// Lane C2 on real devices (MUS-014, MUS-009): a user station streams over
/// HTTP through libmpv in live mode, and scrobbles wait in the on-disk
/// queue across a restart until the service can be reached.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late Directory data;

  setUp(() async {
    data = await Directory.systemTemp.createTemp('c2rs_data');
  });
  tearDown(() async {
    try {
      await data.delete(recursive: true);
    } on FileSystemException {
      // Best effort.
    }
  });

  /// 60 s of a quiet 440 Hz tone, 8 kHz mono WAV.
  Uint8List wav() {
    const rate = 8000;
    const frames = rate * 60;
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
      final v = (math.sin(2 * math.pi * 440 * i / rate) * 2000).round();
      b.setInt16(44 + i * 2, v, Endian.little);
    }
    return b.buffer.asUint8List();
  }

  testWidgets('MUS-014 a station streams over HTTP in live mode; skip keeps '
      'the station', (tester) async {
    if (!MpvEngine.isAvailable) {
      return markTestSkipped('blocked: libmpv is not bundled in this build');
    }
    await tester.runAsync(() async {
      final body = wav();
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((r) async {
        r.response.headers
          ..contentType = ContentType('audio', 'wav')
          ..set('icy-name', 'Loopback FM');
        r.response.add(body);
        await r.response.close();
      });
      final db = LibraryDatabase.open(data);
      final engine = MpvEngine(EngineRole.music);
      final player = MusicPlayer(
        engine: engine,
        queues: QueueRepository(db),
        library: MusicLibrary(db),
        files: localMusicFiles(db),
      );
      await player.init();
      final station = RadioStation(
        id: 'loop',
        name: 'Loopback FM',
        url: Uri.parse('http://127.0.0.1:${server.port}/live'),
      );
      await RadioStations(MusicPrefs(db)).save(station);
      await player.playStation(station);
      for (
        var i = 0;
        i < 100 && engine.current.status != PlaybackStatus.playing;
        i++
      ) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      expect(engine.current.status, PlaybackStatus.playing);
      expect(engine.current.error, isNull);
      expect(player.state.live, isTrue);
      expect(player.state.station?.name, 'Loopback FM');
      await player.next();
      expect(player.state.station?.id, 'loop');
      await player.pause();
      // `pause()` returns once mpv has accepted the command; the snapshot
      // follows with mpv's own `pause` property event. Wait for that event
      // instead of reading the snapshot in the same turn (a live stream
      // pauses like a file: c2_music_test does the same on a local track).
      await engine.state
          .firstWhere((s) => s.status == PlaybackStatus.paused)
          .timeout(const Duration(seconds: 5));
      expect(engine.current.status, PlaybackStatus.paused);
      await player.dispose();
      await engine.dispose();
      await server.close(force: true);
      await db.close();
    });
  });

  testWidgets('MUS-009 listens survive a restart in the on-disk queue and '
      'go out once the service is reachable', (tester) async {
    await tester.runAsync(() async {
      var db = LibraryDatabase.open(data);
      await MusicSeed(db).song(
        'a/1.flac',
        title: 'Kept',
        artist: 'A',
        album: 'X',
        albumArtist: 'A',
        track: 1,
        durationMs: 60000,
      );
      final lib = MusicLibrary(db);
      final songs = await lib.albumTracks((await lib.albums()).single.groupKey);
      final engine = ScriptedMusicEngine();
      final player = MusicPlayer(
        engine: engine,
        queues: QueueRepository(db),
        library: lib,
        files: localMusicFiles(db),
        openTimeout: const Duration(milliseconds: 100),
      );
      await player.init();
      final offline = _Service()..fail = true;
      var scrobbler = Scrobbler(
        db: db,
        prefs: MusicPrefs(db),
        player: player,
        services: [offline],
      );
      await scrobbler.setEnabled('fake', enabled: true);
      scrobbler.start();
      await player.playTracks(songs);
      for (var p = 0; p <= 40; p += 2) {
        engine.at(Duration(seconds: p));
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(await scrobbler.pending(), {'fake': 1});
      await scrobbler.dispose();
      await player.dispose();
      await db.close();

      db = LibraryDatabase.open(data);
      final online = _Service();
      scrobbler = Scrobbler(
        db: db,
        prefs: MusicPrefs(db),
        player: MusicPlayer(
          engine: ScriptedMusicEngine(),
          queues: QueueRepository(db),
          library: MusicLibrary(db),
          files: localMusicFiles(db),
        ),
        services: [online],
      );
      await scrobbler.flush();
      expect(online.sent.single.title, 'Kept');
      expect(await scrobbler.pending(), isEmpty);
      await scrobbler.dispose();
      await db.close();
    });
  });
}

final class _Service implements ScrobbleService {
  final sent = <ScrobbleTrack>[];
  bool fail = false;

  @override
  String get id => 'fake';

  @override
  int get batchSize => 10;

  @override
  Future<bool> connected() async => true;

  @override
  Future<void> nowPlaying(ScrobbleTrack t) async {}

  @override
  Future<void> signOut() async {}

  @override
  Future<void> submit(List<ScrobbleTrack> listens) async {
    if (fail) throw const ScrobbleError('offline');
    sent.addAll(listens);
  }
}
