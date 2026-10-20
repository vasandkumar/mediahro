import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mediahro_engine/mediahro_engine.dart';
import 'package:mediahro_engine/src/mpv/audio_tapper.dart'
    show tapBands, tapSampleRate;

import 'cpu_time.dart';
import 'support.dart';

/// ADR-027 on real libmpv: the visualiser tap (AUD-046) and stream metadata
/// for internet radio (MUS-014).
void adr027Suite() {
  final skip = ffiSkipReason;
  prepareCorpus();

  group('AUD-046 visualiser tap', () {
    test(
      'AUD-046 the tap analyses the playing audio and stops with its listener',
      () async {
        final e = headlessEngine(
          role: EngineRole.music,
          extraOptions: {'loop-file': 'inf'},
        );
        addTearDown(e.dispose);
        // A 440 Hz sine (the gapless album), looped.
        await e.open(UriSource(Uri.file(corpusPath('gapless_flac_1.flac'))));
        await waitPlaying(e);
        expect(e.audioTapActive, isFalse, reason: 'no cost without listener');
        final frames = <AudioTapFrame>[];
        final sub = e.audioTap().listen(frames.add);
        final deadline = DateTime.now().add(const Duration(seconds: 10));
        while (frames.length < 5 && DateTime.now().isBefore(deadline)) {
          await Future<void>.delayed(const Duration(milliseconds: 50));
        }
        expect(frames.length, greaterThanOrEqualTo(5));
        expect(e.audioTapActive, isTrue);
        final f = frames.last;
        expect(f.sampleRate, tapSampleRate);
        expect(f.samples, hasLength(1024));
        expect(f.rms, hasLength(2));
        expect(f.rms.first, greaterThan(0.1));
        expect(f.peak.first, greaterThan(0.2));
        final bands = f.bands!;
        expect(bands, hasLength(tapBands));
        var top = 0;
        for (var b = 1; b < bands.length; b++) {
          if (bands[b] > bands[top]) top = b;
        }
        final nyquist = f.sampleRate / 2;
        final lo = 20 * math.pow(nyquist / 20, top / tapBands);
        final hi = 20 * math.pow(nyquist / 20, (top + 1) / tapBands);
        expect(
          440,
          inInclusiveRange(lo * 0.85, hi * 1.15),
          reason: 'strongest band $top ($lo–$hi Hz) holds the 440 Hz tone',
        );
        // Frames follow playback.
        expect(f.position, greaterThan(frames.first.position));
        await sub.cancel();
        final off = DateTime.now().add(const Duration(seconds: 5));
        while (e.audioTapActive && DateTime.now().isBefore(off)) {
          await Future<void>.delayed(const Duration(milliseconds: 50));
        }
        expect(e.audioTapActive, isFalse, reason: 'stopped with the listener');
      },
      skip: skip,
      timeout: const Timeout(Duration(minutes: 1)),
    );
  });

  group('AUD-046 cost', () {
    test(
      'AUD-046 the tap costs nothing unlistened; its cost while listened',
      () async {
        final mp3 = await File(corpusPath('mp3_lame.mp3')).readAsBytes();
        // A long local file: MP3 frames concatenate into a valid stream.
        final dir = await Directory.systemTemp.createTemp('mh-tapcost');
        addTearDown(() => dir.delete(recursive: true));
        final long = File('${dir.path}${Platform.pathSeparator}long.mp3');
        await long.writeAsBytes([for (var i = 0; i < 40; i++) ...mp3]);
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        addTearDown(() => server.close(force: true));
        server.listen((req) => unawaited(_icy(req, mp3)));
        final report = <String, Object?>{'platform': env.platformName};
        for (final (name, src) in [
          ('local', UriSource(long.uri)),
          (
            'network',
            UriSource(Uri.parse('http://127.0.0.1:${server.port}/stream')),
          ),
        ]) {
          report[name] = await _measureTap(src);
        }
        // The cost figures belong in the PR record (ADR-027); print reaches
        // the host from device runs, stdout does not.
        // ignore: avoid_print
        print('AUD-046 tap cost: ${jsonEncode(report)}');
        File(
          '${Directory.systemTemp.path}${Platform.pathSeparator}'
          'mediahro-audio-tap-cost.json',
        ).writeAsStringSync(jsonEncode(report));
      },
      skip: skip,
      timeout: const Timeout(Duration(minutes: 3)),
    );
  });

  group('AUD-046 network sources', () {
    test(
      'AUD-046 network sources are analysed from the playback cache, never '
      'fetched twice',
      () async {
        final mp3 = await File(corpusPath('mp3_lame.mp3')).readAsBytes();
        var requests = 0;
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        addTearDown(() => server.close(force: true));
        server.listen((req) {
          requests++;
          unawaited(_icy(req, mp3));
        });
        final e = headlessEngine(role: EngineRole.music);
        addTearDown(e.dispose);
        await e.open(
          UriSource(Uri.parse('http://127.0.0.1:${server.port}/stream')),
        );
        await waitPlaying(e, reason: 'http stream playing');
        final before = requests;
        final frames = <AudioTapFrame>[];
        final sub = e.audioTap().listen(frames.add);
        addTearDown(sub.cancel);
        final deadline = DateTime.now().add(const Duration(seconds: 15));
        while (frames.length < 10 && DateTime.now().isBefore(deadline)) {
          await Future<void>.delayed(const Duration(milliseconds: 50));
        }
        expect(frames.length, greaterThanOrEqualTo(10));
        expect(frames.last.rms.first, greaterThan(0.01));
        expect(e.audioTapActive, isTrue);
        expect(requests, before, reason: 'the tap opened no connection');
      },
      skip: skip,
      timeout: const Timeout(Duration(minutes: 1)),
    );
  });

  group('MUS-014 internet radio metadata', () {
    test(
      'MUS-014 ICY stream titles reach mediaTitle and mediaMetadata',
      () async {
        final mp3 = await File(corpusPath('mp3_lame.mp3')).readAsBytes();
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        addTearDown(() => server.close(force: true));
        server.listen((req) => unawaited(_icy(req, mp3)));
        final e = headlessEngine(role: EngineRole.music);
        addTearDown(e.dispose);
        await e.open(
          UriSource(Uri.parse('http://127.0.0.1:${server.port}/radio')),
        );
        final first = await waitFor(
          e,
          (s) => s.mediaTitle == 'Song A' || s.mediaTitle == 'Song B',
          timeout: const Duration(seconds: 20),
          reason: 'ICY StreamTitle',
        );
        expect(first.error, isNull);
        final second = await waitFor(
          e,
          (s) => s.mediaTitle == 'Song B',
          timeout: const Duration(seconds: 20),
          reason: 'the next ICY StreamTitle',
        );
        final icy = second.mediaMetadata.entries
            .where((m) => m.key.toLowerCase() == 'icy-title')
            .map((m) => m.value);
        expect(icy, contains('Song B'));
      },
      skip: skip,
      timeout: const Timeout(Duration(minutes: 1)),
    );
  });
}

/// A minimal SHOUTcast/ICY server: the MP3 looped, with a metadata block
/// after every `metaint` bytes; the StreamTitle switches from "Song A" to
/// "Song B" after the first few blocks.
Future<void> _icy(HttpRequest req, Uint8List mp3) async {
  const metaint = 8192;
  final res = req.response
    ..statusCode = HttpStatus.ok
    ..headers.contentType = ContentType('audio', 'mpeg')
    ..headers.set('icy-name', 'Mediahro Radio');
  final icy = req.headers.value('icy-metadata') == '1';
  if (icy) res.headers.set('icy-metaint', '$metaint');
  res.bufferOutput = false;
  var sent = 0;
  var blocks = 0;
  try {
    for (var round = 0; round < 40; round++) {
      var off = 0;
      while (off < mp3.length) {
        final room = icy ? metaint - (sent % metaint) : mp3.length;
        final n = math.min(room, mp3.length - off);
        res.add(mp3.sublist(off, off + n));
        off += n;
        sent += n;
        if (icy && sent % metaint == 0) {
          final title = blocks < 3 ? 'Song A' : 'Song B';
          final text = utf8.encode("StreamTitle='$title';");
          final len = (text.length + 15) ~/ 16;
          res.add([len, ...text, ...List.filled(len * 16 - text.length, 0)]);
          blocks++;
        }
      }
      // About real time, so the player keeps reading.
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    await res.close();
  } on Object {
    // The player hung up.
  }
}

/// CPU (% of one core) while playing [src] without the tap, with it, and
/// after cancelling it, plus the tap's PCM write rate (AUD-046 cost).
Future<Map<String, Object?>> _measureTap(MediaSource src) async {
  final e = headlessEngine(role: EngineRole.music);
  try {
    await e.open(src);
    await waitPlaying(e);
    const window = Duration(seconds: 9);
    Future<double> cpuPercent() async {
      final cpu0 = processCpuTime();
      final sw = Stopwatch()..start();
      await Future<void>.delayed(window);
      return (processCpuTime() - cpu0).inMicroseconds /
          sw.elapsedMicroseconds *
          100;
    }

    final idle = await cpuPercent();
    var frames = 0;
    final sub = e.audioTap().listen((_) => frames++);
    // Let the tap start and settle.
    await Future<void>.delayed(const Duration(seconds: 2));
    final bytes0 = e.audioTapBytes;
    final frames0 = frames;
    final sw = Stopwatch()..start();
    final listened = await cpuPercent();
    final seconds = sw.elapsedMicroseconds / 1e6;
    final kbPerSecond = (e.audioTapBytes - bytes0) / 1024 / seconds;
    final framesPerSecond = (frames - frames0) / seconds;
    await sub.cancel();
    await Future<void>.delayed(const Duration(seconds: 1));
    expect(e.audioTapActive, isFalse, reason: 'no analysis core left');
    final after = await cpuPercent();
    expect(framesPerSecond, greaterThan(15));
    // Real time float32 stereo at 22.05 kHz is 172 KB/s; reading ahead adds
    // a little.
    expect(kbPerSecond, lessThan(400));
    return {
      'cpuPercentOfOneCore': {
        'playingNoTap': idle,
        'playingWithTap': listened,
        'afterCancel': after,
      },
      'tapWriteKBPerSecond': kbPerSecond,
      'framesPerSecond': framesPerSecond,
    };
  } finally {
    await e.dispose();
  }
}
