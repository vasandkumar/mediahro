import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediahro_engine/mediahro_engine.dart';
import 'package:mediahro_engine/src/mpv/audio_dsp.dart' show loudnessGainDb;
import 'package:mediahro_engine/src/mpv/mp4_gapless.dart' show LocalVirtualFile;

import 'support.dart';

/// AUD-001…006 and the engine side of AUD-040…045: formats, gapless,
/// crossfade, loudness, DSP, output truthfulness, DSD conversion.
void audioSuite() {
  final skip = ffiSkipReason;
  prepareCorpus();

  group('AUD-001 formats', () {
    for (final item in corpusItems(category: 'audio')) {
      test(
        'AUD-001 ${item.file} decodes',
        () async {
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
        },
        skip: item.file == 'midi_scale.mid'
            ? 'blocked: STATUS §3 — no MIDI synthesiser in mediahro-deps '
                  '(soundfont playback, B4a)'
            : const {'replaygain.flac', 'tracker.mod'}.contains(item.file)
            ? blockedOn(appleBootstrap, appleBootstrapBlocker)
            : skip,
      );
    }
  });

  group('VID-006 stream protocol', () {
    test(
      'VID-006 played files are not kept by the stream protocol',
      () async {
        final e = headlessEngine(role: EngineRole.music);
        addTearDown(e.dispose);
        Future<VirtualFileSource> source(String name) async =>
            VirtualFileSource(LocalVirtualFile(File(corpusPath(name))));

        await e.open(await source('gapless_flac_1.flac'));
        await waitPlaying(e);
        expect(e.servedFileCount, 1);
        // Another item replaces it; the first is forgotten.
        await e.open(await source('gapless_flac_2.flac'));
        await waitPlaying(e);
        expect(e.servedFileCount, 1, reason: 'only the item in play');
        // A queued item is registered, a replaced queue entry is forgotten.
        await e.setNext(await source('gapless_mp3_1.mp3'));
        expect(e.servedFileCount, 2);
        await e.setNext(await source('gapless_mp3_2.mp3'));
        expect(e.servedFileCount, 2, reason: 'the replaced entry is gone');
        await e.setNext(null);
        expect(e.servedFileCount, 1);
        // Advancing makes the queued item the one in play.
        await e.setNext(await source('gapless_flac_1.flac'));
        await e.skipToNext();
        await waitFor(e, (s) => s.item >= 3, reason: 'advanced');
        expect(e.servedFileCount, 1);
        await e.stop();
        expect(e.servedFileCount, 0, reason: 'nothing kept after stop');
      },
      skip: skip,
      timeout: const Timeout(Duration(minutes: 1)),
    );
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
      }, skip: blockedOn(appleBootstrap, appleBootstrapBlocker));
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
    }, skip: blockedOn(appleBootstrap, appleBootstrapBlocker));

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
    }, skip: blockedOn(appleBootstrap, appleBootstrapBlocker));
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
    }, skip: blockedOn(appleBootstrap, appleBootstrapBlocker));

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
    }, skip: blockedOn(appleBootstrap, appleBootstrapBlocker));
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
      'AUD-043 native DSD plays as DoP, bit-exact under volume and speed',
      () async {
        final dir = await Directory.systemTemp.createTemp('mh-dop');
        addTearDown(() => dir.delete(recursive: true));
        final out = '${dir.path}${Platform.pathSeparator}dop.pcm';
        final e = headlessEngine(
          role: EngineRole.music,
          nullAudio: false,
          extraOptions: {
            'ao': 'pcm',
            'ao-pcm-file': out,
            'ao-pcm-waveheader': 'no',
            'ao-pcm-append': 'yes',
            'audio-format': 's32',
          },
        );
        addTearDown(e.dispose);
        await e.setAudioOutput(_dopOutput);
        // Gain, speed and a DSP chain would corrupt DoP; the engine ignores
        // them for the item.
        await e.setVolume(0.5);
        await e.setRate(1.5);
        await e.setAudioDsp(
          const AudioDspChain(loudness: LoudnessMode.ebuR128),
        );
        await e.open(UriSource(Uri.file(corpusPath('dsd64.dsf'))));
        final playing = await waitFor(
          e,
          (s) =>
              s.audio.path == AudioOutputPath.dop && s.audio.sampleRate != null,
          reason: 'DoP output path',
        );
        expect(playing.audio.sampleRate, 176400, reason: 'DSD64 / 16');
        expect(playing.audio.bitDepth, anyOf(24, 32));
        await waitFor(
          e,
          (s) => s.status == PlaybackStatus.ended,
          timeout: const Duration(seconds: 30),
          reason: 'DSD played to the end',
        );
        var last = -1;
        for (var i = 0; i < 30; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 100));
          final size = File(out).lengthSync();
          if (size == last) break;
          last = size;
        }
        final pcm = ByteData.sublistView(File(out).readAsBytesSync());
        final frames = pcm.lengthInBytes ~/ 8;
        // 2 s of DSD64 is 352,800 DoP frames.
        expect(frames, closeTo(352800, 2000));
        // The source: the first block of each channel, bits oldest-first.
        final src = File(corpusPath('dsd64.dsf')).readAsBytesSync();
        int rev(int b) {
          var r = 0;
          for (var i = 0; i < 8; i++) {
            if (b & (1 << i) != 0) r |= 1 << (7 - i);
          }
          return r;
        }

        const dataAt = 92;
        const block = 4096;
        for (var f = 0; f < block ~/ 2; f++) {
          for (var c = 0; c < 2; c++) {
            final v = pcm.getInt32((f * 2 + c) * 4, Endian.little);
            final marker = (v >> 24) & 0xFF;
            expect(marker, f.isEven ? 0x05 : 0xFA, reason: 'marker at $f');
            final older = rev(src[dataAt + c * block + 2 * f]);
            final newer = rev(src[dataAt + c * block + 2 * f + 1]);
            expect((v >> 16) & 0xFF, older, reason: 'older byte at $f/$c');
            expect((v >> 8) & 0xFF, newer, reason: 'newer byte at $f/$c');
          }
        }
        // The markers alternate for the whole stream, with no gap or repeat.
        for (var f = 0; f < frames; f += 97) {
          final marker = (pcm.getInt32(f * 8, Endian.little) >> 24) & 0xFF;
          expect(marker, f.isEven ? 0x05 : 0xFA, reason: 'marker at $f');
        }
      },
      skip: skip,
    );

    // DoP to a device that does not decode it is noise, so each condition
    // of the guard is tested on its own: the engine plays PCM instead.
    Future<PlaybackState> dsdWith({
      required AudioOutputConfig config,
      Map<String, String> options = const {},
    }) async {
      final dir = await Directory.systemTemp.createTemp('mh-dopg');
      addTearDown(() => dir.delete(recursive: true));
      final e = headlessEngine(
        role: EngineRole.music,
        nullAudio: false,
        extraOptions: {
          'ao': 'pcm',
          'ao-pcm-file': '${dir.path}${Platform.pathSeparator}o.pcm',
          'ao-pcm-waveheader': 'no',
          'audio-format': 's32',
          ...options,
        },
      );
      addTearDown(e.dispose);
      await e.setAudioOutput(config);
      await e.open(UriSource(Uri.file(corpusPath('dsd64.dsf'))));
      final playing = await waitPlaying(e);
      return playing;
    }

    test('AUD-043 DoP needs an exclusive output', () async {
      final s = await dsdWith(
        config: const AudioOutputConfig(
          nativeDsd: true,
          passthroughCodecs: ['dop'],
        ),
      );
      expect(s.error, isNull);
      expect(s.audio.path, isNot(AudioOutputPath.dop));
    }, skip: skip);

    test('AUD-043 DoP needs the device to be listed as taking it', () async {
      final s = await dsdWith(
        config: const AudioOutputConfig(nativeDsd: true, exclusive: true),
      );
      expect(s.error, isNull);
      expect(s.audio.path, isNot(AudioOutputPath.dop));
    }, skip: skip);

    test(
      'AUD-043 DoP is dropped when the opened output is not 24-bit',
      () async {
        // A 16-bit output would truncate the markers: PCM conversion instead.
        final s = await dsdWith(
          config: _dopOutput,
          options: {'audio-format': 's16'},
        );
        expect(s.error, isNull);
        expect(s.audio.path, isNot(AudioOutputPath.dop));
      },
      skip: skip,
    );

    test(
      'AUD-043 a DSD item is not joined gaplessly to the one before',
      () async {
        final e = headlessEngine(role: EngineRole.music);
        addTearDown(e.dispose);
        await e.setAudioOutput(_dopOutput);
        await e.open(UriSource(Uri.file(corpusPath('gapless_flac_1.flac'))));
        await waitPlaying(e);
        await e.setNext(UriSource(Uri.file(corpusPath('dsd64.dsf'))));
        expect(
          e.current.nextPrepared,
          isFalse,
          reason: 'opened by the app later',
        );
        await e.setNext(UriSource(Uri.file(corpusPath('gapless_flac_2.flac'))));
        expect(e.current.nextPrepared, isTrue);
      },
      skip: skip,
    );

    test(
      'AUD-043 DoP needs a named device, never the system default',
      () async {
        final s = await dsdWith(
          config: const AudioOutputConfig(
            nativeDsd: true,
            exclusive: true,
            passthroughCodecs: ['dop'],
          ),
        );
        expect(s.error, isNull);
        expect(s.audio.path, isNot(AudioOutputPath.dop));
      },
      skip: skip,
    );

    test(
      'AUD-043 a DoP item is pinned to its device and falls back to null',
      () async {
        final dir = await Directory.systemTemp.createTemp('mh-dopp');
        addTearDown(() => dir.delete(recursive: true));
        final e = headlessEngine(
          role: EngineRole.music,
          nullAudio: false,
          extraOptions: {
            'ao': 'pcm',
            'ao-pcm-file': '${dir.path}${Platform.pathSeparator}o.pcm',
            'ao-pcm-waveheader': 'no',
            'audio-format': 's32',
          },
        );
        addTearDown(e.dispose);
        await e.setAudioOutput(_dopOutput);
        await e.open(
          UriSource(Uri.file(corpusPath('dsd64.dsf'))),
          opts: const OpenOptions(autoplay: false),
        );
        await waitFor(e, (s) => s.audio.path == AudioOutputPath.dop);
        // If the DAC goes away mpv must open its silent null output, not the
        // speaker; and the device is the named one, not 'auto'.
        expect(await prop(e, 'audio-device'), 'pcm/dac');
        expect(await prop(e, 'audio-fallback-to-null'), isTrue);
        // The next item is ordinary: the setting is the item's own.
        await e.open(UriSource(Uri.file(corpusPath('gapless_flac_1.flac'))));
        await waitPlaying(e);
        expect(await prop(e, 'audio-fallback-to-null'), isFalse);
        expect(await prop(e, 'audio-device'), 'pcm/dac');
      },
      skip: skip,
    );

    test(
      'AUD-043 mpv losing the pinned device on its own leads to PCM',
      () async {
        // The observer path: nobody calls the engine, mpv itself loses the
        // device (a driver that does not exist stands in for an unplugged
        // DAC). The item is paused with its output open, so nothing can have
        // been written; the engine finds mpv on its null output, which is not
        // the DAC, and plays the file as PCM on the chosen output.
        final dir = await Directory.systemTemp.createTemp('mh-dopv');
        addTearDown(() => dir.delete(recursive: true));
        final file = File('${dir.path}${Platform.pathSeparator}o.pcm');
        final e = headlessEngine(
          role: EngineRole.music,
          nullAudio: false,
          extraOptions: {
            'ao': 'pcm',
            'ao-pcm-file': file.path,
            'ao-pcm-waveheader': 'no',
            'ao-pcm-append': 'yes',
            'audio-format': 's32',
          },
        );
        addTearDown(e.dispose);
        await e.setAudioOutput(_dopOutput);
        await e.open(
          UriSource(Uri.file(corpusPath('dsd64.dsf'))),
          opts: const OpenOptions(autoplay: false),
        );
        await waitFor(
          e,
          (s) =>
              s.audio.path == AudioOutputPath.dop &&
              s.status == PlaybackStatus.paused,
        );
        await e.debugSetMpvProperty('audio-device', 'nonexistent/dac');
        await waitFor(
          e,
          (s) =>
              s.audio.path != AudioOutputPath.dop &&
              s.audio.path != AudioOutputPath.unknown,
          reason: 'PCM after the device was lost',
        );
        expect(
          await prop(e, 'audio-device'),
          'pcm/dac',
          reason: 'chosen output',
        );
        await e.play();
        await waitFor(
          e,
          (s) => s.status == PlaybackStatus.ended,
          timeout: const Duration(seconds: 30),
        );
        expect(e.current.error, isNull);
        final d = ByteData.sublistView(file.readAsBytesSync());
        var run = 0;
        var longest = 0;
        for (var i = 0; i + 1 < d.lengthInBytes ~/ 8; i++) {
          final m = (d.getInt32(i * 8, Endian.little) >> 24) & 0xFF;
          final n = (d.getInt32((i + 1) * 8, Endian.little) >> 24) & 0xFF;
          run = (m == 0x05 && n == 0xFA) || (m == 0xFA && n == 0x05)
              ? run + 1
              : 0;
          if (run > longest) longest = run;
        }
        expect(longest, lessThan(64), reason: 'no DoP frames were written');
        expect(d.lengthInBytes, greaterThan(100000), reason: 'the item played');
      },
      skip: skip,
    );

    // A DoP stream must not reach a changed output unchecked (device,
    // exclusivity, native DSD off, the OS moving the route): the engine
    // pauses first, checks, and plays PCM from the same place if the output
    // no longer carries the stream. The capture is the output file; the
    // item is opened paused, with its output verified and open, so that not a
    // single frame can have been written before the change (the capture
    // output runs faster than real time, so a change mid-playback cannot be
    // timed; the same code path runs, with the item playing, on a device).
    group('AUD-043 DoP is re-checked while playing', () {
      Future<(MpvEngine, File)> startDop({
        AudioBridge? bridge,
        EnginePlatform? platform,
      }) async {
        final dir = await Directory.systemTemp.createTemp('mh-dopr');
        addTearDown(() => dir.delete(recursive: true));
        final file = File('${dir.path}${Platform.pathSeparator}o.pcm');
        final options = {
          'ao': 'pcm',
          'ao-pcm-file': file.path,
          'ao-pcm-waveheader': 'no',
          'ao-pcm-append': 'yes',
          'audio-format': 's32',
        };
        final e = MpvEngine(
          EngineRole.music,
          config: MpvEngineConfig(
            platform: platform,
            video: VideoOutputMode.none,
            libmpvPath: env.libmpvPath,
            audioBridge: bridge,
            extraOptions: options,
          ),
        );
        addTearDown(e.dispose);
        await e.setAudioOutput(_dopOutput);
        await e.open(
          UriSource(Uri.file(corpusPath('dsd64.dsf'))),
          opts: const OpenOptions(autoplay: false),
        );
        await waitFor(
          e,
          (s) =>
              s.audio.path == AudioOutputPath.dop &&
              s.status == PlaybackStatus.paused,
          reason: 'DoP opened and verified, paused',
        );
        return (e, file);
      }

      // Which captured frames (stereo s32) are DoP: the marker bytes
      // 0x05 / 0xFA alternating over at least 64 frames in a row.
      List<bool> dopFrames(File f) {
        final d = ByteData.sublistView(f.readAsBytesSync());
        final n = d.lengthInBytes ~/ 8;
        int marker(int i) => (d.getInt32(i * 8, Endian.little) >> 24) & 0xFF;
        final dop = List.filled(n, false);
        var run = 0;
        for (var i = 0; i < n; i++) {
          final m = marker(i);
          final alternates =
              (m == 0x05 || m == 0xFA) && (i == 0 || marker(i - 1) != m);
          run = alternates ? run + 1 : 0;
          if (run >= 64) {
            for (var k = i - 63; k <= i; k++) {
              dop[k] = true;
            }
          }
        }
        return dop;
      }

      // The item was paused with nothing written, so after the change not a
      // single frame of the capture may be DoP, and the item must have gone
      // on (as PCM).
      void expectNoDop(File f) {
        final dop = dopFrames(f);
        expect(dop.length, greaterThan(100000), reason: 'the item went on');
        expect(dop.any((x) => x), isFalse, reason: 'DoP frames emitted');
      }

      Future<void> untilEnded(MpvEngine e) => waitFor(
        e,
        (s) => s.status == PlaybackStatus.ended,
        timeout: const Duration(seconds: 30),
      );

      test('AUD-043 a non-exclusive output mid-DoP leads to PCM', () async {
        final (e, file) = await startDop();
        expect(file.lengthSync(), 0, reason: 'nothing written yet');
        await e.setAudioOutput(
          const AudioOutputConfig(nativeDsd: true, passthroughCodecs: ['dop']),
        );
        await e.play();
        await untilEnded(e);
        expect(e.current.error, isNull);
        expect(e.current.audio.path, isNot(AudioOutputPath.dop));
        expectNoDop(file);
      }, skip: skip);

      test('AUD-043 native DSD switched off mid-DoP leads to PCM', () async {
        final (e, file) = await startDop();
        expect(file.lengthSync(), 0, reason: 'nothing written yet');
        await e.setAudioOutput(
          const AudioOutputConfig(exclusive: true, passthroughCodecs: ['dop']),
        );
        await e.play();
        await untilEnded(e);
        expect(e.current.audio.path, isNot(AudioOutputPath.dop));
        expectNoDop(file);
      }, skip: skip);

      test(
        'AUD-043 an unchanged output is re-checked and DoP goes on',
        () async {
          final (e, file) = await startDop();
          await e.setAudioOutput(
            _dopOutput.copyWith(
              latencyOffset: const Duration(milliseconds: 20),
            ),
          );
          await e.play();
          await untilEnded(e);
          expect(e.current.audio.path, AudioOutputPath.dop);
          final dop = dopFrames(file);
          expect(dop.length, closeTo(352800, 4000));
          expect(
            dop.where((x) => !x).length,
            lessThan(200),
            reason: 'the whole stream stays DoP, marker order unbroken',
          );
        },
        skip: skip,
      );

      test(
        'AUD-043 the OS moving the route off the DAC mid-DoP leads to PCM',
        () async {
          final results = <String, Object?>{
            'prefer': {
              'applied': true,
              'bitPerfect': true,
              'sampleRate': 176400,
              'device': 'USB DAC',
            },
          };
          final (e, file) = await startDop(
            platform: EnginePlatform.android,
            bridge: AudioBridge(
              channel: MethodChannel(
                'mh/test/audio',
                const StandardMethodCodec(),
                _FakeMessenger(results),
              ),
            ),
          );
          expect(file.lengthSync(), 0, reason: 'nothing written yet');
          // The DAC is unplugged: the OS no longer grants the path.
          results['prefer'] = {'applied': false, 'bitPerfect': false};
          await e.audioRouteChanged();
          await e.play();
          await untilEnded(e);
          expect(e.current.audio.path, isNot(AudioOutputPath.dop));
          expectNoDop(file);
        },
        skip: skip,
      );
    });

    for (final (granted, expectDop) in [(false, false), (true, true)]) {
      test('AUD-043 on a phone the OS must grant the bit-perfect path '
          '(granted: $granted)', () async {
        // The OS answers the bit-perfect request through a fake messenger
        // (no Flutter test binding, which would break the HTTP tests).
        final channel = MethodChannel(
          'mh/test/audio',
          const StandardMethodCodec(),
          _FakeMessenger({
            'prefer': {
              'applied': granted,
              'bitPerfect': granted,
              'sampleRate': granted ? 176400 : null,
              'device': 'USB DAC',
            },
          }),
        );
        final dir = await Directory.systemTemp.createTemp('mh-dopm');
        addTearDown(() => dir.delete(recursive: true));
        final e = MpvEngine(
          EngineRole.music,
          config: MpvEngineConfig(
            platform: EnginePlatform.android,
            video: VideoOutputMode.none,
            libmpvPath: env.libmpvPath,
            audioBridge: AudioBridge(channel: channel),
            extraOptions: {
              'ao': 'pcm',
              'ao-pcm-file': '${dir.path}${Platform.pathSeparator}o.pcm',
              'ao-pcm-waveheader': 'no',
              'audio-format': 's32',
            },
          ),
        );
        addTearDown(e.dispose);
        await e.setAudioOutput(_dopOutput);
        await e.open(UriSource(Uri.file(corpusPath('dsd64.dsf'))));
        final s = await waitPlaying(e);
        expect(s.error, isNull);
        expect(s.audio.path == AudioOutputPath.dop, expectDop);
      }, skip: skip);
    }

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

/// An exclusive output whose device is listed as taking DoP.
const _dopOutput = AudioOutputConfig(
  deviceId: 'pcm/dac',
  nativeDsd: true,
  exclusive: true,
  passthroughCodecs: ['dop'],
);

/// Answers every method call of a [MethodChannel] with a fixed result.
final class _FakeMessenger implements BinaryMessenger {
  _FakeMessenger(this.results);

  final Map<String, Object?> results;

  @override
  Future<ByteData?> send(String channel, ByteData? message) async {
    const codec = StandardMethodCodec();
    final call = codec.decodeMethodCall(message);
    return codec.encodeSuccessEnvelope(results[call.method]);
  }

  @override
  Future<void> handlePlatformMessage(
    String channel,
    ByteData? data,
    PlatformMessageResponseCallback? callback,
  ) async {}

  @override
  void setMessageHandler(String channel, MessageHandler? handler) {}
}
