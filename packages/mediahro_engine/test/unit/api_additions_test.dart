import 'package:flutter_test/flutter_test.dart';
import 'package:mediahro_engine/mediahro_engine.dart';
import 'package:mediahro_engine/src/mpv/mpv_engine.dart'
    show audioOutputProperties, duckingGainDb, parseAudioDevices;
import 'package:mediahro_engine/testing.dart';

/// API additions before the Phase B freeze: ducking (AUD-045), audio devices
/// (AUD-040…042), Bluetooth pre-roll (AUD-044), video targets (VID-031) and
/// export (VID-042).
void main() {
  final src = UriSource(Uri.parse('https://example.test/a.flac'));

  group('AUD-045 ducking', () {
    test('AUD-045 ducking gain maps to mpv volume-gain in dB', () {
      expect(duckingGainDb(1), '0');
      expect(duckingGainDb(1.5), '0');
      expect(duckingGainDb(0.5), '-6.02');
      expect(duckingGainDb(0.25), '-12.04');
      expect(duckingGainDb(0), '-96');
      expect(duckingGainDb(0.000001), '-96.00');
    });

    test('AUD-045 crossfading engine ducks both cores and keeps the user '
        'volume', () async {
      final cores = <FakePlaybackEngine>[];
      final e = CrossfadingEngine(() {
        final c = FakePlaybackEngine(
          role: EngineRole.music,
          mediaDuration: const Duration(seconds: 10),
        );
        cores.add(c);
        return c;
      }, fadeStep: const Duration(milliseconds: 1));
      addTearDown(e.dispose);
      await e.setTransition(
        const TransitionConfig(naturalEnd: Duration(seconds: 2)),
      );
      await e.open(src);
      await e.setVolume(0.8);
      await e.setDucking(0.2);
      expect(e.current.ducked, isTrue);
      expect(e.current.volume, 0.8, reason: 'user volume untouched');
      expect(cores.first.calls, contains('setDucking'));
      // The standby core gets the ducking before it plays the next item.
      await e.setNext(UriSource(Uri.parse('https://example.test/b.flac')));
      expect(cores[1].calls.take(2), contains('setDucking'));
      expect(cores[1].current.ducked, isTrue);
      await e.setDucking(1);
      expect(e.current.ducked, isFalse);
      expect(e.current.volume, 0.8);
    });
  });

  group('AUD-040…042 audio devices', () {
    test('AUD-040 mpv audio-device-list maps to engine devices', () {
      final devices = parseAudioDevices([
        {'name': 'auto', 'description': 'Autoselect device'},
        {'name': 'wasapi/{1234}', 'description': 'Speakers (USB DAC)'},
        {'name': 'coreaudio/Built-in', 'description': ''},
        {'description': 'no name'},
      ]);
      expect(devices, const [
        EngineAudioDevice(
          id: 'auto',
          name: 'Autoselect device',
          isDefault: true,
        ),
        EngineAudioDevice(id: 'wasapi/{1234}', name: 'Speakers (USB DAC)'),
        EngineAudioDevice(id: 'coreaudio/Built-in', name: 'coreaudio/Built-in'),
      ]);
      expect(parseAudioDevices(null), isEmpty);
    });
  });

  group('AUD-044 Bluetooth', () {
    test(
      'AUD-044 pre-roll feeds silence and waits before the first sample',
      () {
        final off = audioOutputProperties(
          const AudioOutputConfig(),
          EnginePlatform.android,
        );
        expect(off['audio-stream-silence'], 'no');
        expect(off['audio-wait-open'], '0');
        final on = audioOutputProperties(
          const AudioOutputConfig(preRoll: Duration(milliseconds: 750)),
          EnginePlatform.android,
        );
        expect(on['audio-stream-silence'], 'yes');
        expect(on['audio-wait-open'], '0.75');
      },
    );
  });

  group('VID-031 video targets', () {
    test('VID-031 targets compare by kind and handle', () {
      expect(const VideoTarget.texture(), const VideoTarget.texture());
      expect(
        const VideoTarget.platformView(7),
        const VideoTarget.platformView(7),
      );
      expect(
        const VideoTarget.platformView(7),
        isNot(const VideoTarget.platformView(8)),
      );
      expect(const VideoStats().hdrOutput, HdrOutput.sdrToneMapped);
    });

    test('VID-031 the fake engine records the target', () async {
      final e = FakePlaybackEngine();
      addTearDown(e.dispose);
      await e.setVideoTarget(const VideoTarget.platformView(3));
      expect(e.videoTarget, const VideoTarget.platformView(3));
    });
  });

  group('VID-042 export', () {
    test('VID-042 export needs an open item and a non-empty range', () async {
      final e = FakePlaybackEngine();
      addTearDown(e.dispose);
      final out = Uri.file('/tmp/clip.gif');
      await expectLater(
        e.export(
          Duration.zero,
          const Duration(seconds: 1),
          ExportFormat.gif,
          out,
        ),
        throwsA(isA<EngineException>()),
      );
      await e.open(src);
      await expectLater(
        e.export(
          const Duration(seconds: 2),
          const Duration(seconds: 1),
          ExportFormat.gif,
          out,
        ),
        throwsA(isA<EngineException>()),
      );
      await e.export(
        const Duration(seconds: 1),
        const Duration(seconds: 2),
        ExportFormat.clipCopy,
        out,
      );
      expect(e.exports.single.$3, ExportFormat.clipCopy);
    });
  });
}
