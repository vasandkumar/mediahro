import 'package:flutter_test/flutter_test.dart';
import 'package:mediahro_engine/mediahro_engine.dart';
import 'package:mediahro_engine/src/mpv/mpv_engine.dart' show encodeOptions;
import 'package:mediahro_engine/src/mpv/mpv_node.dart';
import 'package:mediahro_engine/src/mpv/mpv_options.dart';
import 'package:mediahro_engine/src/mpv/playlist_files.dart';
import 'package:mediahro_engine/src/mpv/state_mapping.dart';

void main() {
  group('docs/05 §4.1 option defaults', () {
    Map<String, String> opts(EnginePlatform p, {VideoOutputMode? v}) =>
        defaultMpvOptions(
          platform: p,
          role: EngineRole.video,
          video:
              v ??
              (p == EnginePlatform.android
                  ? VideoOutputMode.androidSurface
                  : VideoOutputMode.renderApi),
        );

    test('VID-030 gpu-next renderer, direct rendering, HDR hints', () {
      for (final p in EnginePlatform.values) {
        final o = opts(p);
        expect(o['vd-lavc-dr'], 'yes');
        expect(o['target-colorspace-hint'], 'yes');
        expect(o['hdr-compute-peak'], 'yes');
        expect(o['hwdec'], 'auto-safe');
      }
      expect(opts(EnginePlatform.android)['vo'], 'gpu-next');
      expect(
        opts(EnginePlatform.android)['gpu-context'],
        'androidvk,android',
        reason: 'Vulkan first on Android',
      );
      expect(opts(EnginePlatform.windows)['vo'], 'libmpv');
    });

    test('VID-031 tone mapping defaults to bt.2390', () {
      expect(opts(EnginePlatform.macos)['tone-mapping'], 'bt.2390');
    });

    test('VID-039 video-sync per platform family', () {
      expect(opts(EnginePlatform.windows)['video-sync'], 'display-resample');
      expect(opts(EnginePlatform.macos)['video-sync'], 'display-resample');
      expect(opts(EnginePlatform.android)['video-sync'], 'audio');
      expect(opts(EnginePlatform.ios)['video-sync'], 'audio');
    });

    test('AUD-040…042 audio outputs per platform', () {
      expect(opts(EnginePlatform.android)['ao'], startsWith('aaudio'));
      expect(opts(EnginePlatform.ios)['ao'], startsWith('avfoundation'));
      expect(opts(EnginePlatform.macos)['ao'], startsWith('coreaudio'));
      expect(opts(EnginePlatform.windows)['ao'], 'wasapi');
      expect(opts(EnginePlatform.windows)['audio-exclusive'], 'no');
    });

    test('AUD-002 gapless audio and playlist prefetch are on', () {
      final o = opts(EnginePlatform.windows);
      expect(o['gapless-audio'], 'yes');
      expect(o['prefetch-playlist'], 'yes');
    });

    test('AUD-005 scaletempo2 handles speed; no GPL rubberband', () {
      for (final p in EnginePlatform.values) {
        final o = opts(p);
        expect(o['af'], 'scaletempo2');
        expect(o.values.join(' '), isNot(contains('rubberband')));
      }
    });

    test('SUB-010 libass with embedded fonts; SUB-012 external lookup', () {
      final o = opts(EnginePlatform.ios);
      expect(o['sub-ass'], 'yes');
      expect(o['embeddedfonts'], 'yes');
      expect(o['sub-auto'], 'fuzzy');
      expect(o['sub-file-paths'], contains('Subs'));
      expect(o['sub-codepage'], 'auto', reason: 'SUB-013 uchardet');
    });

    test('PRIV-004 no scripting, config files or youtube-dl network', () {
      final o = opts(EnginePlatform.windows);
      expect(o['load-scripts'], 'no');
      expect(o['ytdl'], 'no');
      expect(o['config'], 'no');
      expect(o['osc'], 'no');
    });

    test('VID-068 music role and audio-only mode drop video', () {
      final o = defaultMpvOptions(
        platform: EnginePlatform.android,
        role: EngineRole.music,
        video: VideoOutputMode.none,
      );
      expect(o['vo'], 'null');
      expect(o['vid'], 'no');
      expect(o['audio-display'], 'no');
    });

    test('VID-006 cache sized by bitrate within memory budgets', () {
      const mb = 1024 * 1024;
      expect(
        cacheBytes(platform: EnginePlatform.android, isNetwork: false),
        32 * mb,
      );
      // 40 Mbit/s 4K stream: 90 s read-ahead, capped at the mobile budget.
      expect(
        cacheBytes(
          platform: EnginePlatform.android,
          isNetwork: true,
          bitrate: 40000000,
        ),
        150 * mb,
      );
      expect(
        cacheBytes(
          platform: EnginePlatform.windows,
          isNetwork: true,
          bitrate: 8000000,
        ),
        8000000 ~/ 8 * 90,
      );
      expect(
        cacheBytes(platform: EnginePlatform.windows, isNetwork: true),
        192 * mb,
      );
      expect(isNetworkUri(Uri.parse('smb://nas/a.mkv')), isTrue);
      expect(isNetworkUri(Uri.file('/a.mkv')), isFalse);
    });

    test('VID-006 network resume: reconnect with 30 s window', () {
      final o = opts(EnginePlatform.windows);
      expect(o['network-timeout'], '30');
      expect(o['stream-lavf-o'], contains('reconnect_delay_max=30'));
    });
  });

  group('state mapping', () {
    const s0 = PlaybackState();

    test('VID-001 track-list maps types, languages and flags', () {
      final s = applyProperty(s0, 'track-list', [
        {'id': 1, 'type': 'video', 'codec': 'hevc', 'demux-w': 3840},
        {'id': 2, 'type': 'video', 'albumart': true},
        {
          'id': 1,
          'type': 'audio',
          'lang': 'eng',
          'demux-channel-count': 6,
          'default': true,
          'title': 'English (Audio Description)',
        },
        {
          'id': 1,
          'type': 'sub',
          'lang': 'fre',
          'forced': true,
          'external': true,
          'hearing-impaired': true,
        },
        {'id': 9, 'type': 'unknown'},
      ]);
      expect(s.tracks, hasLength(3), reason: 'cover art is not a video');
      final a = s.tracks.firstWhere((t) => t.type == TrackType.audio);
      expect(a.language, 'en');
      expect(a.channels, 6);
      expect(a.isDefault, isTrue);
      expect(a.isAudioDescription, isTrue);
      final sub = s.tracks.firstWhere((t) => t.type == TrackType.subtitle);
      expect(sub.language, 'fr');
      expect(sub.isForced && sub.isExternal && sub.isHearingImpaired, isTrue);
    });

    test('chapters, positions and selections map', () {
      var s = applyProperty(s0, 'chapter-list', [
        {'time': 0.0, 'title': 'A'},
        {'time': 61.5},
      ]);
      expect(s.chapters[1].start, const Duration(milliseconds: 61500));
      s = applyProperty(s, 'time-pos', 12.25);
      expect(s.position, const Duration(milliseconds: 12250));
      s = applyProperty(s, 'sid', '3');
      expect(s.subtitleTrackId, 3);
      s = applyProperty(s, 'sid', 'no');
      expect(s.subtitleTrackId, isNull);
      s = applyProperty(s, 'volume', 150.0);
      expect(s.volume, 1.5);
    });

    test('VID-031 HDR10 and HLG detected from transfer function', () {
      expect(detectHdr({'gamma': 'pq'}), HdrType.hdr10);
      expect(detectHdr({'gamma': 'hlg'}), HdrType.hlg);
      expect(detectHdr({'gamma': 'bt.1886'}), HdrType.sdr);
    });

    test('VID-032 HDR10+ detected from per-scene MaxRGB', () {
      expect(
        detectHdr({'gamma': 'pq', 'scene-max-r': 900.0}),
        HdrType.hdr10Plus,
      );
    });

    test('VID-033…035 Dolby Vision profile reported technically', () {
      final tracks = [
        const Track(id: 1, type: TrackType.video, dolbyVisionProfile: 8),
      ];
      final v = applyVideoParams(const VideoStats(), {
        'gamma': 'pq',
        'w': 3840,
        'h': 2160,
        'max-luma': 1000.0,
      }, tracks);
      expect(v.hdr, HdrType.dolbyVision);
      expect(v.dolbyVisionProfile, 8);
      expect(v.peakNits, 1000);
      expect((v.width, v.height), (3840, 2160));
    });

    test('VID-072 hwdec path names', () {
      expect(parseHwdec('mediacodec'), HwdecPath.mediacodec);
      expect(parseHwdec('videotoolbox-copy'), HwdecPath.videotoolbox);
      expect(parseHwdec('d3d11va'), HwdecPath.d3d11va);
      expect(parseHwdec('vulkan'), HwdecPath.vulkan);
      expect(parseHwdec('no'), HwdecPath.none);
      expect(parseHwdec('cuda'), HwdecPath.other);
    });

    test('AUD-006 output path is truthful', () {
      AudioOutputPath path({
        int inRate = 96000,
        int outRate = 96000,
        String inFmt = 's32',
        String outFmt = 's32',
        bool exclusive = true,
        bool dsp = false,
      }) => audioOutputInfo(
        decoded: {'samplerate': inRate, 'format': inFmt, 'channel-count': 2},
        output: {'samplerate': outRate, 'format': outFmt, 'channel-count': 2},
        exclusive: exclusive,
        dspActive: dsp,
      ).path;
      expect(path(), AudioOutputPath.bitPerfect);
      expect(path(outRate: 48000), AudioOutputPath.resampled);
      expect(path(exclusive: false), AudioOutputPath.mixed);
      expect(path(dsp: true), AudioOutputPath.resampled);
      expect(path(outFmt: 'spdif-ac3'), AudioOutputPath.passthrough);
      final info = audioOutputInfo(
        decoded: {'samplerate': 44100, 'format': 's16'},
        output: {'samplerate': 44100, 'format': 's16', 'channel-count': 2},
        exclusive: true,
        dspActive: false,
        device: 'wasapi/{id}',
      );
      expect(info.bitDepth, 16);
      expect(info.sampleRate, 44100);
      expect(info.device, 'wasapi/{id}');
    });

    test('CORE-011 load errors map to actionable categories', () {
      expect(
        mapEndFileError(MpvError.unknownFormat, isNetwork: false),
        EngineErrorCode.unsupportedFormat,
      );
      expect(
        mapEndFileError(MpvError.loadingFailed, isNetwork: true),
        EngineErrorCode.networkTimeout,
      );
      expect(
        mapEndFileError(MpvError.loadingFailed, isNetwork: false),
        EngineErrorCode.sourceUnavailable,
      );
      expect(mapEndFileError(-99, isNetwork: false), EngineErrorCode.unknown);
    });
  });

  test('VID-001 XSPF playlists expand relative to the playlist', () {
    final entries = parseXspf(
      '<playlist><trackList>'
      '<track><location>a%20b.mkv</location></track>'
      '<track><title>x</title><location>http://h/c.mp4?x=1&amp;y=2</location></track>'
      '<track></track>'
      '</trackList></playlist>',
      Uri.parse('file:///media/list.xspf'),
    );
    expect(entries.map((e) => e.toString()), [
      'file:///media/a%20b.mkv',
      'http://h/c.mp4?x=1&y=2',
    ]);
    expect(needsPlaylistExpansion('/x/Y.XSPF'), isTrue);
  });

  test('per-file options are length-quoted for loadfile', () {
    expect(
      encodeOptions({'start': '10', 'http-header-fields': 'A: 1,B: 2'}),
      'start=%2%10,http-header-fields=%9%A: 1,B: 2',
    );
    expect(encodeOptions({'t': 'é'}), 't=%2%é');
  });
}
