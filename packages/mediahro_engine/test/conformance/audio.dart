import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mediahro_engine/mediahro_engine.dart';
import 'package:mediahro_engine/src/mpv/audio_dsp.dart' show loudnessGainDb;

import 'support.dart';

/// AUD-001…006 and the engine side of AUD-040…045: formats, gapless,
/// crossfade, loudness, DSP, output truthfulness, DSD conversion.
void audioSuite() {
  final skip = ffiSkipReason;
  prepareCorpus();

  group('AUD-001 formats', () {
    for (final item in corpusItems(category: 'audio')) {
      test('AUD-001 ${item.file} decodes', () async {
        final e = await openItem(item.file, role: EngineRole.music);
        final s = await waitPlaying(e, reason: item.file);
        expect(s.error, isNull, reason: '${item.file}: ${s.error}');
        final audio = s.tracks.where((t) => t.type == TrackType.audio);
        expect(audio, hasLength(item.expect['audio'] ?? 1));
        if (item.expect['audioCodec'] case final String c) {
          expect(audio.first.codec, c);
        }
        if (item.expect['chapters'] case final int n) {
          expect(s.chapters, hasLength(n), reason: 'CUE tracks');
        }
        if (item.expect['replayGainTrack'] case final num g) {
          expect(audio.first.replayGainTrackDb, closeTo(g, 0.01));
          expect(
            audio.first.replayGainAlbumDb,
            closeTo(item.expect['replayGainAlbum']! as num, 0.01),
          );
        }
      }, skip: skip);
    }
  });

  group('AUD-002 gapless', () {
    // m4a carries its delay and padding only in an iTunSMPB tag, framed as
    // iTunes writes it (whole frames) or as FFmpeg 6.x does (last frame
    // shortened); either way the padding is trimmed once.
    for (final (name, prefix, ext) in [
      ('AUD-002 flac album joins sample-accurately', 'gapless_flac', 'flac'),
      ('AUD-002 mp3 album joins sample-accurately', 'gapless_mp3', 'mp3'),
      ('AUD-002 gapless m4a (iTunes framing)', 'gapless_m4a', 'm4a'),
      ('AUD-002 gapless m4a (FFmpeg framing)', 'gapless_m4a_ff', 'm4a'),
    ]) {
      test(name, () async {
        final pcm = await _capture((e) async {
          await e.open(
            UriSource(Uri.file(corpusPath('${prefix}_1.$ext'))),
            opts: const OpenOptions(autoplay: false),
          );
          await e.setNext(
            UriSource(Uri.file(corpusPath('${prefix}_2.$ext'))),
            sameAlbum: true,
          );
          await e.play();
          await waitFor(
            e,
            (s) => s.item >= 2 && s.status == PlaybackStatus.ended,
            timeout: const Duration(seconds: 20),
            reason: 'both tracks played',
          );
        });
        // Two 2 s tracks of one continuous 440 Hz sine at 44.1 kHz.
        expect(
          pcm.frames,
          closeTo(2 * 88200, switch (ext) {
            'flac' => 2,
            'm4a' => 32,
            _ => 1152,
          }),
          reason: 'encoder delay and padding trimmed',
        );
        final jump = pcm.maxStep(channel: 0);
        expect(
          jump,
          lessThan(ext == 'flac' ? 2600 : 4500),
          reason: 'no click at the join (max step $jump)',
        );
      }, skip: skip);
    }

    test('AUD-002 only double-trimmed m4a files use the stream protocol, '
        'within the open budget (docs/11 §5)', () async {
      final e = headlessEngine(role: EngineRole.music);
      addTearDown(e.dispose);
      // Warm core: the budget is open → first audio, not core start-up.
      await e.open(UriSource(Uri.file(corpusPath('gapless_flac_1.flac'))));
      await waitPlaying(e);
      final budget = EnginePlatform.current.isMobile ? 500 : 300;
      for (final (file, viaProtocol) in [
        ('gapless_m4a_1.m4a', false),
        ('gapless_m4a_ff_1.m4a', true),
      ]) {
        final sw = Stopwatch()..start();
        await e.open(UriSource(Uri.file(corpusPath(file))));
        await waitPlaying(e, reason: '$file playing');
        final ms = sw.elapsedMilliseconds;
        final path = '${await prop(e, 'path')}';
        expect(
          path.startsWith('mhvf://'),
          viaProtocol,
          reason: '$file opened as $path',
        );
        expect(ms, lessThan(budget), reason: '$file open → playing');
      }
    }, skip: skip);

    test(
      'AUD-002 queue advances without an ended state between items',
      () async {
        final e = headlessEngine(role: EngineRole.music);
        addTearDown(e.dispose);
        final statuses = <PlaybackStatus>[];
        final sub = e.state.listen((s) => statuses.add(s.status));
        addTearDown(sub.cancel);
        await e.open(UriSource(Uri.file(corpusPath('gapless_flac_1.flac'))));
        await e.setNext(UriSource(Uri.file(corpusPath('gapless_flac_2.flac'))));
        await waitFor(
          e,
          (s) => s.item >= 2,
          timeout: const Duration(seconds: 10),
        );
        await e.setNext(UriSource(Uri.file(corpusPath('gapless_flac_3.flac'))));
        await waitFor(
          e,
          (s) => s.item >= 3,
          timeout: const Duration(seconds: 10),
        );
        final end = await waitFor(
          e,
          (s) => s.status == PlaybackStatus.ended,
          timeout: const Duration(seconds: 10),
        );
        expect(end.item, 3);
        final firstEnd = statuses.indexOf(PlaybackStatus.ended);
        expect(firstEnd, statuses.length - 1, reason: 'ended only at the end');
      },
      skip: skip,
    );
  });

  group('AUD-003 crossfade', () {
    CrossfadingEngine crossfader() {
      final e = CrossfadingEngine(() => headlessEngine(role: EngineRole.music));
      addTearDown(e.dispose);
      return e;
    }

    test('AUD-003 natural-end crossfade overlaps both tracks', () async {
      final e = crossfader();
      await e.setTransition(
        const TransitionConfig(naturalEnd: Duration(seconds: 1)),
      );
      await e.open(UriSource(Uri.file(corpusPath('flac_16_44.flac'))));
      await e.setNext(UriSource(Uri.file(corpusPath('vorbis.ogg'))));
      expect(e.current.nextPrepared, isTrue);
      final sawFade = waitFor(
        e,
        (_) => e.fading,
        timeout: const Duration(seconds: 10),
      );
      await sawFade;
      final after = await waitFor(
        e,
        (s) => s.item == 2 && !e.fading,
        timeout: const Duration(seconds: 10),
      );
      expect(after.status, PlaybackStatus.playing);
      expect(after.tracks.first.codec, 'vorbis');
    }, skip: skip);

    test('AUD-003 manual skip uses its own fade length', () async {
      final e = crossfader();
      await e.setTransition(
        const TransitionConfig(
          naturalEnd: Duration(seconds: 3),
          manualSkip: Duration(milliseconds: 300),
        ),
      );
      await e.open(UriSource(Uri.file(corpusPath('flac_16_44.flac'))));
      await e.setNext(UriSource(Uri.file(corpusPath('opus.opus'))));
      await waitPlaying(e);
      final sw = Stopwatch()..start();
      await e.skipToNext();
      expect(sw.elapsedMilliseconds, lessThan(2000));
      expect(e.current.item, 2);
      expect(e.current.tracks.first.codec, 'opus');
    }, skip: skip);

    test('AUD-003 gapless albums are not crossfaded unless opted in', () async {
      final e = crossfader();
      await e.setTransition(
        const TransitionConfig(naturalEnd: Duration(seconds: 1)),
      );
      await e.open(UriSource(Uri.file(corpusPath('gapless_flac_1.flac'))));
      await e.setNext(
        UriSource(Uri.file(corpusPath('gapless_flac_2.flac'))),
        sameAlbum: true,
      );
      var faded = false;
      final sub = e.state.listen((_) => faded |= e.fading);
      addTearDown(sub.cancel);
      await waitFor(
        e,
        (s) => s.item == 2,
        timeout: const Duration(seconds: 10),
      );
      expect(faded, isFalse, reason: 'sample-accurate gapless instead');
    }, skip: skip);
  });

  group('AUD-004 loudness', () {
    test('AUD-004 background R128 scan measures untagged files', () async {
      final m = await LoudnessScanner.measure(
        UriSource(Uri.file(corpusPath('gapless_flac_1.flac'))),
        libmpvPath: env.libmpvPath,
      );
      expect(m, isNotNull);
      // A full-scale stereo sine is about 0 LUFS with a 0 dBTP peak.
      expect(m!.integratedLufs, inInclusiveRange(-4, 1));
      expect(m.truePeakDbtp, inInclusiveRange(-1.5, 1.5));
      final gain = loudnessGainDb(
        integratedLufs: m.integratedLufs,
        targetLufs: -18,
        truePeakDbtp: m.truePeakDbtp,
      );
      Future<double> level({double? scanned}) async {
        final pcm = await _capture((e) async {
          await e.setAudioDsp(
            const AudioDspChain(loudness: LoudnessMode.ebuR128),
          );
          await e.open(
            UriSource(Uri.file(corpusPath('gapless_flac_1.flac'))),
            opts: OpenOptions(loudnessGainDb: scanned),
          );
          await waitFor(
            e,
            (s) => s.status == PlaybackStatus.ended,
            timeout: const Duration(seconds: 20),
          );
        });
        return pcm.rmsDb(channel: 0);
      }

      final before = await level();
      final after = await level(scanned: gain);
      expect(after - before, closeTo(gain, 0.6));
    }, skip: skip);

    test('AUD-004 ReplayGain track gain lowers the level by the tag', () async {
      Future<double> rms(LoudnessMode mode) async {
        final pcm = await _capture((e) async {
          await e.setAudioDsp(AudioDspChain(loudness: mode));
          await e.open(UriSource(Uri.file(corpusPath('replaygain.flac'))));
          await waitFor(
            e,
            (s) => s.status == PlaybackStatus.ended,
            timeout: const Duration(seconds: 20),
          );
        });
        return pcm.rmsDb(channel: 0);
      }

      final off = await rms(LoudnessMode.off);
      final rg = await rms(LoudnessMode.replayGainTrack);
      expect(rg - off, closeTo(-6.5, 0.5));
    }, skip: skip);
  });

  group('AUD-005 DSP chain', () {
    test('AUD-005 a parametric cut at the tone frequency lowers it', () async {
      Future<double> level(AudioDspChain dsp) async {
        final pcm = await _capture((e) async {
          await e.setAudioDsp(dsp);
          await e.open(UriSource(Uri.file(corpusPath('gapless_flac_1.flac'))));
          await waitFor(
            e,
            (s) => s.status == PlaybackStatus.ended,
            timeout: const Duration(seconds: 20),
          );
        });
        return pcm.rmsDb(channel: 0, skipFrames: 4410);
      }

      final flat = await level(const AudioDspChain());
      final cut = await level(
        const AudioDspChain(
          parametricEq: [
            EqBand(
              type: EqBandType.peaking,
              frequencyHz: 440,
              gainDb: -12,
              q: 1,
            ),
          ],
        ),
      );
      expect(cut - flat, closeTo(-12, 1));
    }, skip: skip);

    test('AUD-005 every DSP stage is accepted by the engine', () async {
      final e = await openItem('flac_16_44.flac', role: EngineRole.music);
      await waitPlaying(e);
      await e.setAudioDsp(
        const AudioDspChain(
          graphicEq: [1, 2, 3, 0, 0, 0, -1, -2, -3, 0],
          parametricEq: [
            EqBand(type: EqBandType.highShelf, frequencyHz: 8000, gainDb: 2),
          ],
          preampDb: -3,
          limiter: true,
          balance: 0.2,
          crossfeed: true,
          bassDb: 2,
          trebleDb: -2,
          pitch: 1.05,
          channelMatrix: [
            [1, 0],
            [0, 1],
          ],
        ),
      );
      final af = await prop(e, 'af');
      expect('$af', contains('equalizer'));
      expect(await prop(e, 'pitch'), closeTo(1.05, 0.001));
      final s = await waitFor(
        e,
        (s) => s.position > const Duration(seconds: 1),
      );
      expect(s.error, isNull);
    }, skip: skip);
  });

  group('AUD-006 output quality indicator', () {
    test('AUD-006 reports device rate, depth and path', () async {
      final e = headlessEngine(
        role: EngineRole.music,
        nullAudio: false,
        extraOptions: {
          'ao': 'pcm',
          'ao-pcm-file': '${Directory.systemTemp.path}/mh_aud006.wav',
        },
      );
      addTearDown(e.dispose);
      await e.open(
        UriSource(Uri.file(corpusPath('flac_24_192.flac'))),
        opts: const OpenOptions(autoplay: false),
      );
      final s = await waitFor(e, (s) => s.audio.sampleRate != null);
      expect(s.audio.sampleRate, isNotNull);
      expect(s.audio.bitDepth, isNotNull);
      expect(s.audio.path, isNot(AudioOutputPath.unknown));
      expect(
        s.audio.path,
        isNot(AudioOutputPath.bitPerfect),
        reason: 'shared output is never reported bit-perfect',
      );
    }, skip: skip);
  });

  group('AUD-040…045 engine side', () {
    test(
      'AUD-040…042 exclusive mode and device selection are applied',
      () async {
        final e = await openItem('flac_16_44.flac', role: EngineRole.music);
        await e.setAudioOutput(
          const AudioOutputConfig(exclusive: true, passthroughCodecs: ['ac3']),
        );
        expect(await prop(e, 'audio-exclusive'), isTrue);
        expect(await prop(e, 'audio-spdif'), 'ac3');
      },
      skip: skip,
    );

    test('AUD-043 DSD plays as PCM with the selected low-pass', () async {
      final e = await openItem('dsd64.dsf', role: EngineRole.music);
      final s = await waitPlaying(e);
      expect(s.error, isNull);
      expect(s.tracks.first.codec, startsWith('dsd'));
      await e.setAudioOutput(
        const AudioOutputConfig(dsdFilter: DsdFilter.sharp),
      );
      expect('${await prop(e, 'af')}', contains('lowpass=f=20000'));
    }, skip: skip);

    test(
      'AUD-044 latency offset shifts audio for Bluetooth A/V sync',
      () async {
        final e = await openItem('mkv_multitrack.mkv');
        await waitPlaying(e);
        await e.setAudioOutput(
          const AudioOutputConfig(latencyOffset: Duration(milliseconds: 200)),
        );
        expect(await prop(e, 'audio-delay'), closeTo(0.2, 0.001));
        await e.setAudioDelay(const Duration(milliseconds: 100));
        expect(await prop(e, 'audio-delay'), closeTo(0.3, 0.001));
      },
      skip: skip,
    );
  });
}

/// Interleaved s16 stereo samples captured with mpv's PCM writer.
final class _Pcm {
  _Pcm(this.samples, this.channels);
  final Int16List samples;
  final int channels;

  int get frames => samples.length ~/ channels;

  int maxStep({required int channel}) {
    var m = 0;
    for (var i = channels + channel; i < samples.length; i += channels) {
      final d = (samples[i] - samples[i - channels]).abs();
      if (d > m) m = d;
    }
    return m;
  }

  double rmsDb({required int channel, int skipFrames = 0}) {
    var sum = 0.0;
    var n = 0;
    for (
      var i = skipFrames * channels + channel;
      i < samples.length;
      i += channels
    ) {
      final v = samples[i] / 32768;
      sum += v * v;
      n++;
    }
    return 10 * math.log(sum / n) / math.ln10;
  }
}

/// Runs [body] on a music engine whose output is written to a WAV file
/// (untimed), then returns the samples.
Future<_Pcm> _capture(Future<void> Function(MpvEngine e) body) async {
  final dir = await Directory.systemTemp.createTemp('mh-pcm');
  final file = '${dir.path}${Platform.pathSeparator}out.wav';
  final e = headlessEngine(
    role: EngineRole.music,
    nullAudio: false,
    extraOptions: {
      'ao': 'pcm',
      'ao-pcm-file': file,
      'ao-pcm-waveheader': 'no',
      // Append: an output re-open would otherwise truncate the capture; a
      // re-open also breaks continuity, which the tests then detect.
      'ao-pcm-append': 'yes',
      'audio-format': 's16',
    },
  );
  try {
    await body(e);
    // ao_pcm writes from its own thread; let it drain before the core goes.
    var last = -1;
    var stable = 0;
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    while (stable < 3 && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      final f = File(file);
      final size = f.existsSync() ? f.lengthSync() : 0;
      stable = size == last ? stable + 1 : 0;
      last = size;
    }
  } finally {
    await e.dispose();
  }
  final bytes = await File(file).readAsBytes();
  await dir.delete(recursive: true);
  return _Pcm(Int16List.sublistView(Uint8List.fromList(bytes)), 2);
}
