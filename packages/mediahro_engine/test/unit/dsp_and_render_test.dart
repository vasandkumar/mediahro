import 'package:flutter_test/flutter_test.dart';
import 'package:mediahro_engine/mediahro_engine.dart';
import 'package:mediahro_engine/src/mpv/audio_dsp.dart';
import 'package:mediahro_engine/src/mpv/render_mapping.dart';

void main() {
  group('AUD-005 DSP chain', () {
    test('AUD-005 empty chain keeps only scaletempo2', () {
      expect(audioFilterValue(const AudioDspChain()), 'scaletempo2');
    });

    test('AUD-005 10-band graphic EQ uses one-octave peaking bands', () {
      final f = dspFilters(
        const AudioDspChain(graphicEq: [3, 0, 0, 0, 0, -2, 0, 0, 0, 6]),
      );
      expect(f, [
        'equalizer=f=31:t=q:w=1.4142:g=3',
        'equalizer=f=1000:t=q:w=1.4142:g=-2',
        'equalizer=f=16000:t=q:w=1.4142:g=6',
      ]);
    });

    test('AUD-005 parametric bands map to biquad filters', () {
      final f = dspFilters(
        const AudioDspChain(
          parametricEq: [
            EqBand(type: EqBandType.lowShelf, frequencyHz: 105, gainDb: 4),
            EqBand(type: EqBandType.notch, frequencyHz: 50, gainDb: 0, q: 10),
            EqBand(type: EqBandType.peaking, frequencyHz: 2000, gainDb: 0),
          ],
        ),
      );
      expect(f, [
        'lowshelf=f=105:t=q:w=0.707:g=4',
        'bandreject=f=50:t=q:w=10',
      ], reason: 'flat peaking bands are dropped');
    });

    test('AUD-005 at most 32 parametric bands', () {
      final bands = List.generate(
        33,
        (i) =>
            EqBand(type: EqBandType.peaking, frequencyHz: 100.0 + i, gainDb: 1),
      );
      expect(
        () => dspFilters(AudioDspChain(parametricEq: bands)),
        throwsArgumentError,
      );
    });

    test('AUD-005 limiter, balance, mono, crossfeed, bass/treble, preamp', () {
      final v = audioFilterValue(
        const AudioDspChain(
          preampDb: -3,
          bassDb: 2,
          trebleDb: -1.5,
          mono: true,
          balance: -0.25,
          crossfeed: true,
          limiter: true,
        ),
      );
      expect(v, startsWith('lavfi=[volume=-3dB,bass=g=2,treble=g=-1.5,'));
      expect(v, contains('pan=stereo|c0=0.5*c0+0.5*c1|c1=0.5*c0+0.5*c1'));
      expect(v, contains('stereotools=balance_out=-0.25'));
      expect(v, contains('crossfeed='));
      expect(v, contains('alimiter='));
      expect(v, endsWith('],scaletempo2'));
      expect(v, isNot(contains('rubberband')), reason: 'GPL (docs/09 §2)');
    });

    test('AUD-005 channel mixer builds a pan matrix', () {
      final f = dspFilters(
        const AudioDspChain(
          channelMatrix: [
            [1, 0.5],
            [0, 1],
          ],
        ),
      );
      expect(f, ['pan=stereo|c0=1*c0+0.5*c1|c1=1*c1']);
    });

    test('POD-001 skip silence', () {
      expect(
        dspFilters(const AudioDspChain(skipSilence: true)).single,
        startsWith('silenceremove='),
      );
    });

    test('AUD-005 pitch is independent of tempo via mpv pitch', () {
      expect(dspProperties(const AudioDspChain(pitch: 1.05))['pitch'], '1.05');
    });

    test('AUD-043 DSD→PCM low-pass selectable', () {
      expect(
        dspFilters(
          const AudioDspChain(),
          sourceCodec: 'dsd_lsbf_planar',
          dsd: DsdFilter.sharp,
        ),
        ['lowpass=f=20000:p=2'],
      );
      expect(
        dspFilters(
          const AudioDspChain(),
          sourceCodec: 'flac',
          dsd: DsdFilter.sharp,
        ),
        isEmpty,
      );
    });

    test('AUD-005 EQ response matches the band gains', () {
      const band = EqBand(
        type: EqBandType.peaking,
        frequencyHz: 1000,
        gainDb: 6,
        q: 1,
      );
      expect(eqResponseDb([band], 1000, 48000), closeTo(6, 0.01));
      expect(eqResponseDb([band], 50, 48000).abs(), lessThan(0.2));
      const shelf = EqBand(
        type: EqBandType.lowShelf,
        frequencyHz: 100,
        gainDb: -4,
      );
      expect(eqResponseDb([shelf], 20, 48000), closeTo(-4, 0.3));
    });

    test('AUD-005 AutoEq ParametricEQ.txt import', () {
      final r = parseAutoEq('''
Preamp: -6.4 dB
Filter 1: ON LSC Fc 105 Hz Gain 5.3 dB Q 0.70
Filter 2: ON PK Fc 1730 Hz Gain -2.1 dB Q 1.43
Filter 3: ON HSC Fc 10000 Hz Gain -3.0 dB Q 0.70
Filter 4: OFF PK Fc 3000 Hz Gain 9 dB Q 1
''');
      expect(r.preampDb, -6.4);
      expect(r.bands, hasLength(3));
      expect(r.bands[0].type, EqBandType.lowShelf);
      expect(r.bands[1].frequencyHz, 1730);
      expect(r.bands[1].gainDb, -2.1);
      expect(r.bands[1].q, 1.43);
    });

    test('AUD-005 Wavelet GraphicEQ import resamples to ≤ 32 bands', () {
      final r = parseAutoEq('GraphicEQ: 20 -1.0; 1000 2.0; 20000 -3.0');
      expect(r.bands.length, lessThanOrEqualTo(32));
      expect(
        r.bands.firstWhere((b) => (b.frequencyHz - 1000).abs() < 1).gainDb,
        2,
      );
    });
  });

  group('AUD-004 loudness', () {
    test('AUD-004 ReplayGain modes and R128 target as pre-amp', () {
      final p = dspProperties(
        const AudioDspChain(
          loudness: LoudnessMode.replayGainAlbum,
          r128TargetLufs: -14,
        ),
      );
      expect(p['replaygain'], 'album');
      expect(p['replaygain-preamp'], '4', reason: '-14 LUFS vs RG2 -18');
      expect(p['replaygain-clip'], 'no', reason: 'clipping prevention on');
      expect(dspProperties(const AudioDspChain())['replaygain'], 'no');
    });

    test('AUD-004 scanned gain applies to untagged files', () {
      final p = dspProperties(
        const AudioDspChain(loudness: LoudnessMode.ebuR128),
        scannedGainDb: -5,
      );
      expect(p['replaygain-fallback'], '-5');
    });

    test('AUD-004 gain is limited by true peak headroom', () {
      expect(loudnessGainDb(integratedLufs: -23, targetLufs: -18), 5);
      expect(
        loudnessGainDb(integratedLufs: -23, targetLufs: -18, truePeakDbtp: -3),
        2,
        reason: 'keeps true peak at -1 dBTP',
      );
    });
  });

  group('video rendering', () {
    test('VID-031 tone-mapping names', () {
      expect(ToneMapping.values.map(toneMappingName), [
        'bt.2390',
        'spline',
        'reinhard',
        'hable',
        'mobius',
        'clip',
      ]);
    });

    test('VID-037/039/041 filter chain maps to mpv properties', () {
      final p = videoFilterProperties(
        const VideoFilterChain(
          toneMapping: ToneMapping.hable,
          scaler: Scaler.ewaLanczos,
          deband: true,
          rotate: 450,
          flipHorizontal: true,
          aspectOverride: 2.39,
          interpolation: true,
        ),
      );
      expect(p['tone-mapping'], 'hable');
      expect(p['scale'], 'ewa_lanczos');
      expect(p['deband'], 'yes');
      expect(p['video-rotate'], '90');
      expect(p['vf'], 'hflip');
      expect(p['video-aspect-override'], '2.39');
      expect(p['interpolation'], 'yes');
    });
  });

  group('subtitles', () {
    test('SUB-014 style maps to mpv sub options', () {
      final p = subtitleStyleProperties(
        const SubtitleStyle(
          font: 'Noto Sans',
          scale: 1.5,
          colorArgb: 0xFFFFFF00,
          outlineColorArgb: 0xFF000000,
          outlineWidth: 2,
          backgroundArgb: 0x80000000,
          verticalPosition: 10,
          alignX: SubtitleAlignX.left,
          borderStyle: SubtitleBorderStyle.backgroundBox,
          overrideAssStyles: true,
        ),
      );
      expect(p['sub-font'], 'Noto Sans');
      expect(p['sub-scale'], '1.5');
      expect(p['sub-color'], '#FFFFFF00');
      expect(p['sub-outline-color'], '#FF000000');
      expect(p['sub-back-color'], '#80000000');
      expect(p['sub-pos'], '90');
      expect(p['sub-align-x'], 'left');
      expect(p['sub-border-style'], 'background-box');
      expect(p['sub-ass-override'], 'force');
    });

    test('SUB-014 unset fields stay with system caption defaults', () {
      final p = subtitleStyleProperties(const SubtitleStyle());
      expect(p.containsKey('sub-font'), isFalse);
      expect(p.containsKey('sub-color'), isFalse);
      expect(p['sub-ass-override'], 'scale');
    });

    test('SUB-016 secondary slot positions independently', () {
      final p = subtitleStyleProperties(
        const SubtitleStyle(verticalPosition: 90),
        slot: SubtitleSlot.secondary,
      );
      expect(p, {
        'secondary-sub-pos': '10',
        'secondary-sub-ass-override': 'yes',
      });
    });

    test('SUB-015 delay is ±60 s in 50 ms steps', () {
      expect(
        snapSubtitleDelay(const Duration(milliseconds: 1234)),
        const Duration(milliseconds: 1250),
      );
      expect(
        snapSubtitleDelay(const Duration(seconds: -90)),
        const Duration(seconds: -60),
      );
      expect(subtitleFpsFactor(from: 25, to: 23.976), closeTo(1.0427, 0.0001));
      expect(secondsValue(const Duration(milliseconds: -1500)), '-1.5');
    });
  });
}
