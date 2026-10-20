import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mediahro_engine/mediahro_engine.dart';

import 'support.dart';

/// CAST-005 engine side: local transcoding (OS H.264 encoders, VP8
/// fallback), the cast HTTP server with byte ranges, WebVTT subtitles.
void castSuite() {
  final skip = ffiSkipReason;
  prepareCorpus();

  group('CAST-005 local transcoding and serving', () {
    late CastServer server;
    setUp(() async {
      server = await CastServer.start(address: InternetAddress.loopbackIPv4);
    });
    tearDown(() => server.close());

    test(
      'CAST-005 transcode produces a stream the engine can play',
      () async {
        const plan = CastPlan(
          kind: CastPlanKind.transcode,
          container: CastContainer.hls,
          video: StreamAction.encode,
          audio: StreamAction.encode,
        );
        final t = await CastTranscoder.start(
          UriSource(Uri.file(corpusPath('mkv_multitrack.mkv'))),
          plan,
          libmpvPath: env.libmpvPath,
        );
        addTearDown(t.stop);
        await t.ready();
        await t.done.timeout(const Duration(minutes: 2));
        final url = server.publishDirectory(t.directory, t.entry);
        // Played back over HTTP from the cast server, like a receiver would.
        final e = headlessEngine();
        addTearDown(e.dispose);
        await e.open(UriSource(url));
        final s = await waitPlaying(e, reason: 'transcoded stream over HTTP');
        expect(s.error, isNull);
        final v = s.tracks.firstWhere((t) => t.type == TrackType.video);
        expect(v.codec, anyOf('h264', 'vp8'));
        final a = s.tracks.firstWhere((t) => t.type == TrackType.audio);
        expect(a.codec, anyOf('aac', 'opus'));
      },
      skip: blockedOn(appleBootstrap, appleBootstrapBlocker),
      timeout: const Timeout(Duration(minutes: 3)),
    );

    test('CAST-005 H.264 comes from the OS hardware encoder', () async {
      final t = await CastTranscoder.start(
        UriSource(Uri.file(corpusPath('mkv_multitrack.mkv'))),
        const CastPlan(
          kind: CastPlanKind.transcode,
          container: CastContainer.hls,
          video: StreamAction.encode,
          audio: StreamAction.encode,
        ),
        libmpvPath: env.libmpvPath,
      );
      addTearDown(t.stop);
      await t.ready();
      if (t.encoder == 'libvpx') {
        markTestSkipped('no OS H.264 encoder on this host; VP8 fallback used');
        return;
      }
      expect(t.encoder, castVideoEncoders(EnginePlatform.current).first);
      expect(t.entry, 'index.m3u8');
    }, skip: blockedOn(appleBootstrap, appleBootstrapBlocker));

    test('CAST-005 passthrough serves byte ranges', () async {
      final file = File(corpusPath('mp4_h264_aac.mp4'));
      if (!file.existsSync()) {
        markTestSkipped('no H.264 encoder on the corpus host');
        return;
      }
      final url = server.publishFile(file);
      final client = HttpClient();
      addTearDown(client.close);
      final req = await client.getUrl(url);
      req.headers.set('range', 'bytes=100-199');
      final res = await req.close();
      expect(res.statusCode, 206);
      expect(
        res.headers.value('content-range'),
        'bytes 100-199/${file.lengthSync()}',
      );
      final body = await res.fold<List<int>>([], (a, b) => a..addAll(b));
      expect(body, file.readAsBytesSync().sublist(100, 200));
      expect(res.headers.value('access-control-allow-origin'), '*');
      // The engine plays the passthrough URL with seeking.
      final e = headlessEngine();
      addTearDown(e.dispose);
      await e.open(UriSource(url));
      await waitPlaying(e);
      await e.seek(const Duration(seconds: 3), mode: SeekMode.exact);
      final s = await waitFor(
        e,
        (s) => s.position >= const Duration(seconds: 3),
      );
      expect(s.error, isNull);
    }, skip: skip);

    test('CAST-005 unknown tokens and traversal are refused', () async {
      final client = HttpClient();
      addTearDown(client.close);
      final base = Uri(scheme: 'http', host: '127.0.0.1', port: server.port);
      final res = await (await client.getUrl(base.resolve('/nope/x.mp4')))
          .close();
      expect(res.statusCode, 404);
      final dir = server.publishDirectory(Directory(env.corpusDir), 'x');
      final bad = await (await client.getUrl(dir.resolve('../../etc/passwd')))
          .close();
      expect(bad.statusCode, anyOf(403, 404));
    }, skip: skip);

    test('CAST-005 embedded subtitles are served as WebVTT', () async {
      final cues = await extractSubtitleCues(
        UriSource(Uri.file(corpusPath('mkv_multitrack.mkv'))),
        trackId: 1,
        libmpvPath: env.libmpvPath,
      );
      expect(
        cues.map((c) => c.text),
        containsAll(['Hello subtitle', 'Second line']),
      );
      expect(cues.first.start, const Duration(milliseconds: 500));
      final url = server.publishText('subs.vtt', toWebVtt(cues));
      final client = HttpClient();
      addTearDown(client.close);
      final res = await (await client.getUrl(url)).close();
      expect(res.headers.contentType?.mimeType, 'text/vtt');
      final text = await res.transform(const SystemEncoding().decoder).join();
      expect(text, startsWith('WEBVTT'));
      expect(text, contains('00:00:00.500 --> 00:00:02.000'));
    }, skip: skip);
  });
}
