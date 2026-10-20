import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mediahro_engine/mediahro_engine.dart';

import 'support.dart';

/// Engine API added before the Phase B freeze, against real libmpv:
/// ducking (AUD-045), devices (AUD-040…042), pre-roll (AUD-044), video
/// targets (VID-031) and export (VID-042).
void apiAdditionsSuite() {
  final skip = ffiSkipReason;
  prepareCorpus();

  group('AUD-045 audio focus', () {
    test(
      'AUD-045 ducking lowers the output without touching the user volume',
      () async {
        final e = await openItem('mp3_lame.mp3', role: EngineRole.music);
        await waitPlaying(e);
        await e.setVolume(0.8);
        await e.setDucking(0.25);
        final ducked = await waitFor(e, (s) => s.ducked);
        expect(ducked.volume, closeTo(0.8, 1e-9), reason: 'user volume');
        expect(await prop(e, 'volume'), closeTo(80, 1e-6));
        expect(await prop(e, 'volume-gain'), closeTo(-12.04, 0.01));
        await e.setDucking(1);
        final restored = await waitFor(e, (s) => !s.ducked);
        expect(restored.volume, closeTo(0.8, 1e-9));
        expect(await prop(e, 'volume-gain'), closeTo(0, 1e-6));
      },
      skip: skip,
    );
  });

  group('AUD-040…042 devices', () {
    test('AUD-040 audio devices start with the default output', () async {
      final e = await openItem('mp3_lame.mp3', role: EngineRole.music);
      final devices = await e.audioDevices();
      expect(devices, isNotEmpty);
      expect(devices.first.id, 'auto');
      expect(devices.first.isDefault, isTrue);
    }, skip: skip);
  });

  group('AUD-044 Bluetooth', () {
    test('AUD-044 pre-roll reaches the audio output', () async {
      final e = await openItem('mp3_lame.mp3', role: EngineRole.music);
      await e.setAudioOutput(
        const AudioOutputConfig(preRoll: Duration(milliseconds: 500)),
      );
      expect(await prop(e, 'audio-wait-open'), closeTo(0.5, 1e-6));
      expect(await prop(e, 'audio-stream-silence'), isTrue);
    }, skip: skip);
  });

  group('VID-031 video targets', () {
    test('VID-031 a platform view needs the render bridge', () async {
      final e = await openItem('mkv_multitrack.mkv');
      await e.setVideoTarget(const VideoTarget.texture());
      await expectLater(
        e.setVideoTarget(const VideoTarget.platformView(1)),
        throwsA(
          isA<EngineException>().having(
            (x) => x.error.code,
            'code',
            EngineErrorCode.notSupported,
          ),
        ),
      );
      expect(e.current.video.hdrOutput, HdrOutput.sdrToneMapped);
    }, skip: skip);
  });

  group('VID-042 export', () {
    final blocked = blockedOn(appleBootstrap, appleBootstrapBlocker);
    Future<File> export(ExportFormat format, String ext) async {
      final e = await openItem('avi_mjpeg.avi');
      await waitPlaying(e);
      final dir = await Directory.systemTemp.createTemp('mh-export');
      addTearDown(() => dir.delete(recursive: true));
      final out = File('${dir.path}${Platform.pathSeparator}clip.$ext');
      await e.export(
        const Duration(milliseconds: 500),
        const Duration(milliseconds: 1500),
        format,
        out.uri,
      );
      return out;
    }

    test('VID-042 animated GIF of a range', () async {
      final out = await export(ExportFormat.gif, 'gif');
      final head = String.fromCharCodes(out.readAsBytesSync().take(6));
      expect(head, 'GIF89a');
    }, skip: blocked);

    test('VID-042 animated WebP of a range', () async {
      final out = await export(ExportFormat.webp, 'webp');
      final b = out.readAsBytesSync();
      expect(String.fromCharCodes(b.take(4)), 'RIFF');
      expect(String.fromCharCodes(b.skip(8).take(4)), 'WEBP');
    }, skip: blocked);

    test('VID-042 lossless clip copies the range', () async {
      final out = await export(ExportFormat.clipCopy, 'mkv');
      final e = headlessEngine();
      addTearDown(e.dispose);
      await e.open(UriSource(out.uri));
      final s = await waitPlaying(e, reason: 'clip plays');
      expect(s.error, isNull);
      expect(s.tracks.where((t) => t.type == TrackType.video), isNotEmpty);
      final d = s.duration ?? Duration.zero;
      expect(
        d.inMilliseconds,
        inInclusiveRange(800, 1700),
        reason: 'about one second (intra-only source)',
      );
    }, skip: blocked);
  });
}
