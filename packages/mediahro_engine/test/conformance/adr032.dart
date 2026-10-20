import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mediahro_engine/mediahro_engine.dart';
import 'package:mediahro_engine/src/mpv/audio_decoder.dart';

import 'support.dart';

/// ADR-032 on real libmpv: offline audio decode for SUB-050 auto-sync,
/// SUB-052 auto-captions and MUS-010 fingerprints.
void adr032Suite() {
  final skip = ffiSkipReason;
  prepareCorpus();

  Future<(Float32List, Duration)> decodeAll(
    PlaybackEngine e,
    MediaSource src, {
    int? trackId,
    bool mono = true,
    Duration? start,
    Duration? end,
  }) async {
    final sw = Stopwatch()..start();
    final chunks = await e
        .decodeAudio(src, trackId: trackId, mono: mono, start: start, end: end)
        .toList();
    final out = Float32List(chunks.fold(0, (n, c) => n + c.length));
    var o = 0;
    for (final c in chunks) {
      out.setAll(o, c);
      o += c.length;
    }
    return (out, sw.elapsed);
  }

  group('ADR-032 decodeAudio', () {
    test(
      'SUB-050 decodeAudio decodes the chosen track to 16 kHz mono faster '
      'than real time',
      () async {
        final e = headlessEngine();
        addTearDown(e.dispose);
        final src = UriSource(Uri.file(corpusPath('mkv_multitrack.mkv')));
        // Track 1 is a 440 Hz tone, track 2 660 Hz; 6 s each.
        final (first, took) = await decodeAll(e, src);
        expect(first.length, closeTo(6 * 16000, 16000 * 0.1));
        expect(_tone(first, 16000), closeTo(440, 10));
        expect(took, lessThan(const Duration(seconds: 3)), reason: '≥ 2×');
        final (second, _) = await decodeAll(e, src, trackId: 2);
        expect(_tone(second, 16000), closeTo(660, 10));
      },
      skip: skip,
      timeout: const Timeout(Duration(minutes: 1)),
    );

    test(
      'SUB-052 decodeAudio honours start, end and stereo',
      () async {
        final e = headlessEngine();
        addTearDown(e.dispose);
        final src = UriSource(Uri.file(corpusPath('mkv_multitrack.mkv')));
        final (part, _) = await decodeAll(
          e,
          src,
          start: const Duration(seconds: 1),
          end: const Duration(seconds: 3),
        );
        expect(part.length, closeTo(2 * 16000, 16000 * 0.1));
        final (stereo, _) = await decodeAll(e, src, mono: false);
        expect(stereo.length, closeTo(2 * 6 * 16000, 2 * 16000 * 0.1));
        expect(stereo.length.isEven, isTrue);
      },
      skip: skip,
      timeout: const Timeout(Duration(minutes: 1)),
    );

    test(
      'SUB-050 the consumer sets the pace and nothing is lost',
      () async {
        final mp3 = await File(corpusPath('mp3_lame.mp3')).readAsBytes();
        final dir = await Directory.systemTemp.createTemp('mh-decode');
        addTearDown(() => dir.delete(recursive: true));
        final long = File('${dir.path}${Platform.pathSeparator}long.mp3');
        await long.writeAsBytes([for (var i = 0; i < 40; i++) ...mp3]);
        final e = headlessEngine();
        addTearDown(e.dispose);
        final src = UriSource(long.uri);
        // One window for the whole file: the reference.
        final sw = Stopwatch()..start();
        final whole = await AudioDecoder(
          src,
          libmpvPath: env.libmpvPath,
          window: const Duration(hours: 1),
        ).stream.fold(0, (n, c) => n + c.length);
        final seconds = whole / 16000;
        // The figure belongs in the PR record (SUB-050: ≥ 2× real time on a
        // phone); print reaches the host from device runs.
        // ignore: avoid_print
        print(
          'ADR-032 decode speed: ${env.platformName} '
          '${(seconds / (sw.elapsedMicroseconds / 1e6)).round()}x real time '
          '(${seconds.round()} s of mp3 to 16 kHz mono)',
        );
        expect(seconds / (sw.elapsedMicroseconds / 1e6), greaterThan(2));
        AudioDecoder.peakBacklogBytes = 0;
        var paced = 0;
        final done = Completer<void>();
        late StreamSubscription<Float32List> sub;
        sub = e
            .decodeAudio(src)
            .listen(
              (c) {
                paced += c.length;
                // A slow consumer: hold the stream for a while after each chunk.
                sub.pause(
                  Future<void>.delayed(const Duration(milliseconds: 5)),
                );
              },
              onDone: done.complete,
              onError: done.completeError,
            );
        await done.future;
        await sub.cancel();
        // 30 s windows join without losing or doubling more than a few ms.
        expect(paced, closeTo(whole, 16000 * 0.02 * (whole / 16000 / 30)));
        expect(paced, closeTo(whole, 16000 * 0.1));
        // Decoding stays about one 30 s window ahead of the consumer.
        expect(AudioDecoder.peakBacklogBytes, lessThan(32 * 16000 * 4));
      },
      skip: skip,
      timeout: const Timeout(Duration(minutes: 2)),
    );

    test(
      'MUS-010 network sources are read once',
      () async {
        final mp3 = await File(corpusPath('mp3_lame.mp3')).readAsBytes();
        var requests = 0;
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        addTearDown(() => server.close(force: true));
        server.listen((req) async {
          requests++;
          req.response
            ..headers.contentType = ContentType('audio', 'mpeg')
            ..contentLength = mp3.length
            ..add(mp3);
          await req.response.close();
        });
        final e = headlessEngine();
        addTearDown(e.dispose);
        final (pcm, _) = await decodeAll(
          e,
          UriSource(Uri.parse('http://127.0.0.1:${server.port}/a.mp3')),
        );
        expect(pcm, isNotEmpty);
        expect(requests, 1);
      },
      skip: skip,
      timeout: const Timeout(Duration(minutes: 1)),
    );

    test(
      'SUB-050 cancelling stops the decoder; bad input is an EngineException',
      () async {
        final e = headlessEngine();
        addTearDown(e.dispose);
        final first = Completer<void>();
        final sub = e
            .decodeAudio(UriSource(Uri.file(corpusPath('mkv_multitrack.mkv'))))
            .listen((_) {
              if (!first.isCompleted) first.complete();
            });
        await first.future.timeout(const Duration(seconds: 10));
        await sub.cancel();
        expect(AudioDecoder.active, 0);
        await expectLater(
          e.decodeAudio(UriSource(Uri.file(corpusPath('zero_bytes.mkv')))),
          emitsError(isA<EngineException>()),
        );
        expect(AudioDecoder.active, 0);
      },
      skip: skip,
      timeout: const Timeout(Duration(minutes: 1)),
    );
  });
}

// Dominant frequency from zero crossings (a clean tone).
double _tone(Float32List pcm, int rate) {
  // Skip the codec's start-up.
  final from = math.min(rate ~/ 10, pcm.length);
  var crossings = 0;
  for (var i = from + 1; i < pcm.length; i++) {
    if ((pcm[i - 1] < 0) != (pcm[i] < 0)) crossings++;
  }
  return crossings / 2 / ((pcm.length - from) / rate);
}
