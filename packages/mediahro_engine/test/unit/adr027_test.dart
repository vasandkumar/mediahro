import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mediahro_engine/mediahro_engine.dart';
import 'package:mediahro_engine/src/mpv/audio_tapper.dart';
import 'package:mediahro_engine/src/mpv/state_mapping.dart';
import 'package:mediahro_engine/testing.dart';

/// ADR-027: visualiser tap analysis (AUD-046) and stream metadata (MUS-014).
void main() {
  group('AUD-046 tap analysis', () {
    Float32List sine(double hz, double amp, int frames, {int channels = 2}) {
      final out = Float32List(frames * channels);
      for (var i = 0; i < frames; i++) {
        final v = amp * math.sin(2 * math.pi * hz * i / tapSampleRate);
        for (var c = 0; c < channels; c++) {
          out[i * channels + c] = v;
        }
      }
      return out;
    }

    test('AUD-046 a sine shows its RMS, peak and band', () {
      final f = analyseWindow(
        sine(440, 0.5, 1024),
        channels: 2,
        sampleRate: tapSampleRate,
        position: const Duration(seconds: 3),
      );
      expect(f.samples, hasLength(1024));
      expect(f.position, const Duration(seconds: 3));
      expect(f.rms[0], closeTo(0.5 / math.sqrt2, 0.01));
      expect(f.peak[1], closeTo(0.5, 0.01));
      final bands = f.bands!;
      expect(bands, hasLength(tapBands));
      final top = bands.indexOf(bands.reduce(math.max));
      const nyquist = tapSampleRate / 2;
      final lo = 20 * math.pow(nyquist / 20, top / tapBands);
      final hi = 20 * math.pow(nyquist / 20, (top + 1) / tapBands);
      expect(440, inInclusiveRange(lo * 0.85, hi * 1.15));
      // A full-scale-normalised spectrum: a 0.5 sine reads about 0.5.
      expect(bands[top], closeTo(0.5, 0.15));
    });

    test('AUD-046 silence is all zeros', () {
      final f = analyseWindow(
        Float32List(2048),
        channels: 2,
        sampleRate: tapSampleRate,
        position: Duration.zero,
      );
      expect(f.rms, [0, 0]);
      expect(f.peak, [0, 0]);
      expect(f.bands!.every((b) => b == 0), isTrue);
    });

    test('AUD-046 the fake engine and the crossfader forward frames', () async {
      final cores = <FakePlaybackEngine>[];
      final e = CrossfadingEngine(() {
        final c = FakePlaybackEngine(role: EngineRole.music);
        cores.add(c);
        return c;
      });
      addTearDown(e.dispose);
      await e.open(UriSource(Uri.parse('https://example.test/a.flac')));
      final got = <AudioTapFrame>[];
      final sub = e.audioTap().listen(got.add);
      await Future<void>.delayed(Duration.zero);
      expect(cores.first.tapListened, isTrue);
      cores.first.emitTap(
        const AudioTapFrame(position: Duration(seconds: 1), sampleRate: 22050),
      );
      await Future<void>.delayed(Duration.zero);
      expect(got.single.position, const Duration(seconds: 1));
      await sub.cancel();
      expect(cores.first.tapListened, isFalse);
    });
  });

  group('MUS-014 stream metadata', () {
    test('MUS-014 media-title and filtered-metadata map to the state', () {
      var s = applyProperty(const PlaybackState(), 'media-title', 'Song A');
      s = applyProperty(s, 'filtered-metadata', {
        'icy-title': 'Song A',
        'Artist': 'Band',
        'Track': 3,
      });
      expect(s.mediaTitle, 'Song A');
      expect(s.mediaMetadata, {
        'icy-title': 'Song A',
        'Artist': 'Band',
        'Track': '3',
      });
      s = applyProperty(s, 'filtered-metadata', null);
      expect(s.mediaMetadata, isEmpty);
    });

    test('MUS-014 the fake engine reports radio metadata', () async {
      final e = FakePlaybackEngine(role: EngineRole.music);
      addTearDown(e.dispose);
      e.setMediaMetadata('Song B', const {'icy-title': 'Song B'});
      expect(e.current.mediaTitle, 'Song B');
      expect(e.current.mediaMetadata['icy-title'], 'Song B');
    });
  });
}
