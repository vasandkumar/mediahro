// Generates the synthetic part of the media corpus (docs/11 §2) with ffmpeg.
//
//   dart run tools/corpus/generate.dart --ffmpeg <path> [--out <dir>]
//
// Files are generated at build time and never shipped (lane B1 brief §9), so
// any encoder may be used; items whose encoder is missing from the given
// ffmpeg are skipped and listed in the manifest. The manifest records what
// the harness must observe for each file (track counts, codecs, HDR type).
// Third-party samples that cannot be synthesised (Dolby Vision, HDR10+)
// live in test-media/corpus (Git LFS) with their own manifest.
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

void main(List<String> args) async {
  String? opt(String name) {
    final i = args.indexOf(name);
    return i >= 0 && i + 1 < args.length ? args[i + 1] : null;
  }

  final ffmpegArg = opt('--ffmpeg') ?? 'ffmpeg';
  final ffmpeg = File(ffmpegArg).existsSync()
      ? File(ffmpegArg).absolute.path
      : ffmpegArg;
  final out = Directory(opt('--out') ?? 'test-media/generated');
  final only = opt('--only');
  out.createSync(recursive: true);
  final encoders = await _encoders(ffmpeg);
  final gen = _Generator(ffmpeg, out, encoders);
  await gen.run(only: only == null ? null : RegExp(only));
  final manifest = File('${out.path}/manifest.json')
    ..writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert({
        'generator': 'tools/corpus/generate.dart',
        'ffmpeg': encoders.version,
        'items': gen.items,
        'skipped': gen.skipped,
      }),
    );
  stdout.writeln(
    'corpus: ${gen.items.length} files, ${gen.skipped.length} skipped → '
    '${manifest.path}',
  );
}

final class _Encoders {
  _Encoders(this.version, this.names);
  final String version;
  final Set<String> names;
  bool has(String e) => names.contains(e);
}

Future<_Encoders> _encoders(String ffmpeg) async {
  final r = await Process.run(ffmpeg, ['-hide_banner', '-encoders']);
  final v = await Process.run(ffmpeg, ['-hide_banner', '-version']);
  final names = <String>{};
  for (final line in (r.stdout as String).split('\n')) {
    final m = RegExp(r'^\s[VAS][\w.]{5}\s+(\S+)').firstMatch(line);
    if (m != null) names.add(m.group(1)!);
  }
  return _Encoders((v.stdout as String).split('\n').first.trim(), names);
}

final class _Generator {
  _Generator(this.ffmpeg, this.out, this.enc);

  final String ffmpeg;
  final Directory out;
  final _Encoders enc;
  final items = <Map<String, Object?>>[];
  final skipped = <Map<String, String>>[];
  RegExp? _only;

  String p(String name) => '${out.path}/$name';

  static const _video = ['-f', 'lavfi', '-i', 'testsrc2=size=640x360:rate=25'];
  static const _tone = [
    '-f',
    'lavfi',
    '-i',
    'sine=frequency=440:sample_rate=48000',
  ];

  static const _svtHdr10 =
      'mastering-display=G(0.17,0.797)B(0.131,0.046)R(0.708,0.292)'
      'WP(0.3127,0.329)L(1000,0.0001):content-light=1000,400';

  String? _h264() =>
      ['libx264', 'h264_videotoolbox', 'h264_mf'].where(enc.has).firstOrNull;

  String? _hevc() =>
      ['libx265', 'hevc_videotoolbox', 'hevc_mf'].where(enc.has).firstOrNull;

  String? _av1() => ['libsvtav1', 'libaom-av1'].where(enc.has).firstOrNull;

  /// Runs ffmpeg for [name]; records [expect] for the harness.
  Future<void> item(
    String name,
    List<String> ffArgs, {
    required Map<String, Object?> expect,
    List<String> needs = const [],
    List<String> ids = const [],
    String? category,
  }) async {
    if (_only != null && !_only!.hasMatch(name)) return;
    final missing = needs.where((e) => !enc.has(e)).toList();
    if (missing.isNotEmpty) {
      skipped.add({'file': name, 'reason': 'encoder missing: $missing'});
      return;
    }
    final r = await Process.run(ffmpeg, [
      '-hide_banner',
      '-loglevel',
      'error',
      '-y',
      ...ffArgs,
      p(name),
    ]);
    if (r.exitCode != 0) {
      skipped.add({'file': name, 'reason': 'ffmpeg: ${r.stderr}'.trim()});
      return;
    }
    items.add({
      'file': name,
      'category': ?category,
      'ids': ids,
      'expect': expect,
    });
  }

  /// Records a file written by Dart (no ffmpeg).
  void written(
    String name,
    List<int> bytes, {
    required Map<String, Object?> expect,
    List<String> ids = const [],
    String? category,
  }) {
    if (_only != null && !_only!.hasMatch(name)) return;
    File(p(name)).writeAsBytesSync(bytes);
    items.add({
      'file': name,
      'category': ?category,
      'ids': ids,
      'expect': expect,
    });
  }

  Future<void> run({RegExp? only}) async {
    _only = only;
    _subtitleFiles();
    await _containers();
    await _videoCodecs();
    await _hdr();
    await _audio();
    await _subtitles();
    await _edgeCases();
    await _subtitleScenes();
    _dsd();
    _playlists();
  }

  // ------------------------------------------------------------ text subs --

  static const _srt =
      '1\n00:00:00,500 --> 00:00:02,000\nHello subtitle\n\n'
      '2\n00:00:02,500 --> 00:00:04,500\nSecond line\n';

  void _subtitleFiles() {
    File(p('subs.srt')).writeAsStringSync(_Generator._srt);
    File(p('subs.ass')).writeAsStringSync(_ass);
  }

  static const _ass = r'''
[Script Info]
ScriptType: v4.00+
PlayResX: 640
PlayResY: 360

[V4+ Styles]
Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding
Style: Default,Arial,40,&H00FFFFFF,&H000000FF,&H00000000,&H00000000,0,0,0,0,100,100,0,0,1,2,0,2,10,10,20,1
Style: Top,Arial,32,&H0000FFFF,&H000000FF,&H00000000,&H00000000,1,0,0,0,100,100,0,0,1,2,0,8,10,10,20,1

[Events]
Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text
Dialogue: 0,0:00:00.50,0:00:04.50,Default,,0,0,0,,{\k50}Ka{\k50}ra{\k50}o{\k50}ke
Dialogue: 0,0:00:00.50,0:00:04.50,Top,,0,0,0,,{\move(100,40,540,40)}Moving sign
''';

  // ----------------------------------------------------------- containers --

  Future<void> _containers() async {
    const c = 'containers';
    await item(
      'mkv_multitrack.mkv',
      [
        ..._video,
        ..._tone,
        '-f',
        'lavfi',
        '-i',
        'sine=frequency=660:sample_rate=44100',
        '-i',
        p('subs.srt'),
        '-i',
        p('subs.ass'),
        '-t',
        '6',
        '-map',
        '0:v',
        '-map',
        '1:a',
        '-map',
        '2:a',
        '-map',
        '3:s',
        '-map',
        '4:s',
        '-c:v',
        'mpeg4',
        '-q:v',
        '5',
        '-c:a:0',
        'libopus',
        '-c:a:1',
        'flac',
        '-c:s:0',
        'srt',
        '-c:s:1',
        'ass',
        '-metadata:s:a:0',
        'language=eng',
        '-metadata:s:a:1',
        'language=fre',
        '-metadata:s:a:1',
        'title=Commentary',
        '-metadata:s:s:0',
        'language=eng',
        '-metadata:s:s:1',
        'language=jpn',
        '-disposition:s:1',
        'forced',
      ],
      needs: ['mpeg4', 'libopus', 'flac', 'srt', 'ass'],
      ids: ['VID-001', 'VID-003', 'SUB-010', 'SUB-012'],
      category: c,
      expect: {
        'video': 1,
        'audio': 2,
        'sub': 2,
        'videoCodec': 'mpeg4',
        'audioCodecs': ['opus', 'flac'],
        'subCodecs': ['subrip', 'ass'],
        'duration': 6,
        'width': 640,
        'height': 360,
      },
    );
    await _chapters();
    final h264 = _h264();
    for (final (name, extra, tag) in [
      ('mp4_h264_aac.mp4', <String>[], 'mp4'),
      ('mp4_fragmented.mp4', ['-movflags', 'frag_keyframe+empty_moov'], 'mp4'),
      ('mov_h264.mov', <String>[], 'mov'),
      ('m4v_h264.m4v', <String>[], 'm4v'),
    ]) {
      await item(
        name,
        [
          ..._video,
          ..._tone,
          '-t',
          '5',
          '-c:v',
          ?h264,
          '-b:v',
          '1M',
          '-pix_fmt',
          'yuv420p',
          '-c:a',
          'aac',
          ...extra,
        ],
        needs: [?h264, 'aac'],
        ids: ['VID-001', 'VID-002'],
        category: c,
        expect: {
          'video': 1,
          'audio': 1,
          'videoCodec': 'h264',
          'container': tag,
        },
      );
      if (h264 == null) {
        skipped.add({'file': name, 'reason': 'no H.264 encoder'});
      }
    }
    await item(
      'webm_vp9_opus.webm',
      [
        ..._video,
        ..._tone,
        '-t',
        '5',
        '-c:v',
        'libvpx-vp9',
        '-b:v',
        '500k',
        '-deadline',
        'realtime',
        '-cpu-used',
        '8',
        '-c:a',
        'libopus',
      ],
      needs: ['libvpx-vp9', 'libopus'],
      ids: ['VID-001', 'VID-002'],
      category: c,
      expect: {'video': 1, 'audio': 1, 'videoCodec': 'vp9'},
    );
    await item(
      'webm_vp8_vorbis.webm',
      [
        ..._video,
        ..._tone,
        '-t',
        '5',
        '-c:v',
        'libvpx',
        '-b:v',
        '500k',
        '-deadline',
        'realtime',
        '-cpu-used',
        '8',
        '-c:a',
        'libvorbis',
      ],
      needs: ['libvpx', 'libvorbis'],
      ids: ['VID-001', 'VID-002', 'VID-003'],
      category: c,
      expect: {'video': 1, 'audio': 1, 'videoCodec': 'vp8'},
    );
    await item(
      'avi_mpeg4_mp3.avi',
      [
        ..._video,
        ..._tone,
        '-t',
        '5',
        '-c:v',
        'mpeg4',
        '-q:v',
        '5',
        '-c:a',
        'libmp3lame',
      ],
      needs: ['mpeg4', 'libmp3lame'],
      ids: ['VID-001'],
      category: c,
      expect: {'video': 1, 'audio': 1, 'videoCodec': 'mpeg4'},
    );
    await item(
      'wmv_wmv2_wma.wmv',
      [
        ..._video,
        ..._tone,
        '-t',
        '5',
        '-c:v',
        'wmv2',
        '-b:v',
        '1M',
        '-c:a',
        'wmav2',
      ],
      needs: ['wmv2', 'wmav2'],
      ids: ['VID-001', 'VID-003'],
      category: c,
      expect: {'video': 1, 'audio': 1, 'videoCodec': 'wmv2'},
    );
    await item(
      'flv_flv1_mp3.flv',
      [
        ..._video,
        '-f',
        'lavfi',
        '-i',
        'sine=frequency=440:sample_rate=44100',
        '-t',
        '5',
        '-c:v',
        'flv',
        '-b:v',
        '1M',
        '-c:a',
        'libmp3lame',
      ],
      needs: ['flv', 'libmp3lame'],
      ids: ['VID-001'],
      category: c,
      expect: {'video': 1, 'audio': 1, 'videoCodec': 'flv1'},
    );
    await item(
      'ts_mpeg2_interlaced_ac3.ts',
      [
        ..._video,
        ..._tone,
        '-t',
        '5',
        '-c:v',
        'mpeg2video',
        '-b:v',
        '2M',
        '-flags',
        '+ilme+ildct',
        '-vf',
        'setfield=tff',
        '-c:a',
        'ac3',
      ],
      needs: ['mpeg2video', 'ac3'],
      ids: ['VID-001', 'VID-002', 'VID-003'],
      category: c,
      expect: {'video': 1, 'audio': 1, 'videoCodec': 'mpeg2video'},
    );
    await item(
      'm2ts_mpeg2_ac3.m2ts',
      [
        ..._video,
        ..._tone,
        '-t',
        '5',
        '-c:v',
        'mpeg2video',
        '-b:v',
        '2M',
        '-c:a',
        'ac3',
        '-mpegts_m2ts_mode',
        '1',
      ],
      needs: ['mpeg2video', 'ac3'],
      ids: ['VID-001'],
      category: c,
      expect: {'video': 1, 'audio': 1, 'videoCodec': 'mpeg2video'},
    );
    await item(
      'mpg_mpeg2_mp2.mpg',
      [
        ..._video,
        ..._tone,
        '-t',
        '5',
        '-c:v',
        'mpeg2video',
        '-b:v',
        '2M',
        '-c:a',
        'mp2',
        '-f',
        'vob',
      ],
      needs: ['mpeg2video', 'mp2'],
      ids: ['VID-001'],
      category: c,
      expect: {'video': 1, 'audio': 1, 'videoCodec': 'mpeg2video'},
    );
    await item(
      'ogv_theora_vorbis.ogv',
      [
        ..._video,
        ..._tone,
        '-t',
        '5',
        '-c:v',
        'libtheora',
        '-q:v',
        '5',
        '-c:a',
        'libvorbis',
      ],
      needs: ['libtheora', 'libvorbis'],
      ids: ['VID-001', 'VID-002'],
      category: c,
      expect: {'video': 1, 'audio': 1, 'videoCodec': 'theora'},
    );
    await item(
      '3gp_mpeg4_aac.3gp',
      [
        ..._video,
        '-f',
        'lavfi',
        '-i',
        'sine=frequency=440:sample_rate=16000',
        '-t',
        '5',
        '-s',
        '352x288',
        '-c:v',
        'mpeg4',
        '-q:v',
        '5',
        '-c:a',
        'aac',
        '-ac',
        '1',
      ],
      needs: ['mpeg4', 'aac'],
      ids: ['VID-001'],
      category: c,
      expect: {'video': 1, 'audio': 1, 'videoCodec': 'mpeg4'},
    );
    await item(
      'rm_rv20.rm',
      [..._video, '-t', '5', '-s', '352x288', '-c:v', 'rv20', '-b:v', '1M'],
      needs: ['rv20'],
      ids: ['VID-001'],
      category: c,
      expect: {'video': 1, 'audio': 0, 'videoCodec': 'rv20'},
    );
    await item(
      'mxf_mpeg2.mxf',
      [
        ..._video,
        ..._tone,
        '-t',
        '5',
        '-s',
        '720x576',
        '-r',
        '25',
        '-c:v',
        'mpeg2video',
        '-b:v',
        '5M',
        '-c:a',
        'pcm_s16le',
      ],
      needs: ['mpeg2video', 'pcm_s16le'],
      ids: ['VID-001'],
      category: c,
      expect: {'video': 1, 'audio': 1, 'videoCodec': 'mpeg2video'},
    );
  }

  Future<void> _chapters() async {
    final meta = File(p('chapters.ffmeta'))
      ..writeAsStringSync(
        ';FFMETADATA1\n'
        '[CHAPTER]\nTIMEBASE=1/1000\nSTART=0\nEND=2000\ntitle=Opening\n'
        '[CHAPTER]\nTIMEBASE=1/1000\nSTART=2000\nEND=4000\ntitle=Middle\n'
        '[CHAPTER]\nTIMEBASE=1/1000\nSTART=4000\nEND=6000\ntitle=End\n',
      );
    await item(
      'mkv_chapters.mkv',
      [
        ..._video,
        ..._tone,
        '-i',
        meta.path,
        '-map_metadata',
        '2',
        '-map_chapters',
        '2',
        '-t',
        '6',
        '-c:v',
        'mpeg4',
        '-q:v',
        '5',
        '-c:a',
        'libopus',
      ],
      needs: ['mpeg4', 'libopus'],
      ids: ['VID-001'],
      category: 'containers',
      expect: {'video': 1, 'audio': 1, 'chapters': 3},
    );
  }

  // --------------------------------------------------------- video codecs --

  Future<void> _videoCodecs() async {
    const c = 'video-codecs';
    final hevc = _hevc();
    for (final tag in ['hvc1', 'hev1']) {
      await item(
        'mp4_hevc_$tag.mp4',
        [
          ..._video,
          '-t',
          '4',
          '-c:v',
          ?hevc,
          '-b:v',
          '1M',
          '-pix_fmt',
          'yuv420p',
          '-tag:v',
          tag,
        ],
        needs: [?hevc],
        ids: ['VID-002', 'VID-005'],
        category: c,
        expect: {'video': 1, 'videoCodec': 'hevc'},
      );
    }
    if (hevc == null) {
      skipped.add({'file': 'mp4_hevc_*.mp4', 'reason': 'no HEVC encoder'});
    }
    if (enc.has('libx264')) {
      await item(
        'mkv_h264_10bit.mkv',
        [
          ..._video,
          '-t',
          '4',
          '-c:v',
          'libx264',
          '-pix_fmt',
          'yuv420p10le',
          '-preset',
          'ultrafast',
        ],
        needs: ['libx264'],
        ids: ['VID-002', 'VID-005'],
        category: c,
        expect: {'video': 1, 'videoCodec': 'h264'},
      );
    }
    final av1 = _av1();
    await item(
      'mkv_av1_10bit.mkv',
      [
        ..._video,
        '-t',
        '3',
        '-c:v',
        ?av1,
        '-pix_fmt',
        'yuv420p10le',
        if (av1 == 'libsvtav1') ...['-preset', '12'] else ...['-cpu-used', '8'],
        '-b:v',
        '500k',
      ],
      needs: [?av1],
      ids: ['VID-002'],
      category: c,
      expect: {'video': 1, 'videoCodec': 'av1'},
    );
    for (final (name, codec, args, expected) in [
      ('mov_prores.mov', 'prores_ks', ['-profile:v', '2'], 'prores'),
      (
        'mov_dnxhd.mov',
        'dnxhd',
        ['-s', '1280x720', '-b:v', '90M', '-r', '25', '-pix_fmt', 'yuv422p'],
        'dnxhd',
      ),
      (
        'avi_mjpeg.avi',
        'mjpeg',
        ['-q:v', '5', '-pix_fmt', 'yuvj420p'],
        'mjpeg',
      ),
      ('mkv_ffv1.mkv', 'ffv1', <String>[], 'ffv1'),
      ('mkv_mpeg1.mkv', 'mpeg1video', ['-b:v', '1M'], 'mpeg1video'),
      ('mov_hap.mov', 'hap', <String>[], 'hap'),
    ]) {
      await item(
        name,
        [..._video, '-t', '2', '-c:v', codec, ...args],
        needs: [codec],
        ids: ['VID-002'],
        category: c,
        expect: {'video': 1, 'videoCodec': expected},
      );
    }
    // Variable frame rate (VID-005).
    await item(
      'mkv_vfr.mkv',
      [
        ..._video,
        '-t',
        '5',
        '-vf',
        "setpts='if(lt(N,50),N/25/TB,(50/25+(N-50)/50)/TB)'",
        '-fps_mode',
        'vfr',
        '-c:v',
        'mpeg4',
        '-q:v',
        '5',
      ],
      needs: ['mpeg4'],
      ids: ['VID-005'],
      category: c,
      expect: {'video': 1, 'videoCodec': 'mpeg4'},
    );
  }

  // ------------------------------------------------------------------ HDR --

  Future<void> _hdr() async {
    const c = 'hdr';
    final av1 = _av1();
    // setparams tags the frames (lavfi sources are untagged); the output
    // options then carry the tags into the bitstream and container.
    final hdr10 = [
      '-vf',
      'setparams=color_primaries=bt2020:color_trc=smpte2084:colorspace=bt2020nc',
      '-color_primaries',
      'bt2020',
      '-color_trc',
      'smpte2084',
      '-colorspace',
      'bt2020nc',
    ];
    await item(
      'mkv_av1_hdr10.mkv',
      [
        ..._video,
        '-t',
        '3',
        '-c:v',
        ?av1,
        '-pix_fmt',
        'yuv420p10le',
        ...hdr10,
        if (av1 == 'libsvtav1') ...[
          '-preset',
          '12',
          '-svtav1-params',
          _svtHdr10,
        ] else ...[
          '-cpu-used',
          '8',
        ],
        '-b:v',
        '500k',
      ],
      needs: [?av1],
      ids: ['VID-031'],
      category: c,
      expect: {'video': 1, 'hdr': 'hdr10'},
    );
    await item(
      'mkv_av1_hlg.mkv',
      [
        ..._video,
        '-t',
        '3',
        '-c:v',
        ?av1,
        '-pix_fmt',
        'yuv420p10le',
        '-vf',
        'setparams=color_primaries=bt2020:color_trc=arib-std-b67:colorspace=bt2020nc',
        '-color_primaries',
        'bt2020',
        '-color_trc',
        'arib-std-b67',
        '-colorspace',
        'bt2020nc',
        if (av1 == 'libsvtav1') ...['-preset', '12'] else ...['-cpu-used', '8'],
        '-b:v',
        '500k',
      ],
      needs: [?av1],
      ids: ['VID-031'],
      category: c,
      expect: {'video': 1, 'hdr': 'hlg'},
    );
    // FFV1 carries the colour tags losslessly and decodes everywhere.
    await item(
      'mkv_ffv1_pq.mkv',
      [
        ..._video,
        '-t',
        '2',
        '-c:v',
        'ffv1',
        '-pix_fmt',
        'yuv420p10le',
        ...hdr10,
      ],
      needs: ['ffv1'],
      ids: ['VID-031'],
      category: c,
      expect: {'video': 1, 'hdr': 'hdr10'},
    );
  }

  // ---------------------------------------------------------------- audio --

  Future<void> _audio() async {
    const c = 'audio';
    final sweep = [
      '-f',
      'lavfi',
      '-i',
      'aevalsrc=sin(2*PI*(200+100*t)*t):s=48000:c=stereo',
    ];
    for (final (name, codec, args, expected) in [
      (
        'flac_24_192.flac',
        'flac',
        ['-ar', '192000', '-sample_fmt', 's32'],
        'flac',
      ),
      (
        'flac_16_44.flac',
        'flac',
        ['-ar', '44100', '-sample_fmt', 's16'],
        'flac',
      ),
      ('alac.m4a', 'alac', <String>[], 'alac'),
      ('wav_f32.wav', 'pcm_f32le', <String>[], 'pcm_f32le'),
      ('aiff_s24.aiff', 'pcm_s24be', <String>[], 'pcm_s24be'),
      ('opus.opus', 'libopus', <String>[], 'opus'),
      ('vorbis.ogg', 'libvorbis', <String>[], 'vorbis'),
      ('mp3_lame.mp3', 'libmp3lame', ['-b:a', '192k'], 'mp3'),
      ('aac.m4a', 'aac', <String>[], 'aac'),
      ('wavpack.wv', 'wavpack', <String>[], 'wavpack'),
      ('tta.tta', 'tta', <String>[], 'tta'),
      ('wma.wma', 'wmav2', <String>[], 'wmav2'),
      ('ac3_51.ac3', 'ac3', ['-ac', '6'], 'ac3'),
      ('eac3_51.eac3', 'eac3', ['-ac', '6'], 'eac3'),
      ('truehd.thd', 'truehd', ['-strict', '-2', '-ac', '2'], 'truehd'),
      ('dts.dts', 'dca', ['-strict', '-2', '-ar', '48000'], 'dts'),
      ('mp2.mp2', 'mp2', <String>[], 'mp2'),
    ]) {
      await item(
        name,
        [...sweep, '-t', '4', '-c:a', codec, ...args],
        needs: [codec],
        ids: ['AUD-001', 'VID-003'],
        category: c,
        expect: {'video': 0, 'audio': 1, 'audioCodec': expected},
      );
    }
    // Gapless album: one continuous sweep split into 4 tracks (AUD-002).
    for (var i = 0; i < 4; i++) {
      for (final (ext, codec) in [('flac', 'flac'), ('mp3', 'libmp3lame')]) {
        await item(
          'gapless_${ext}_${i + 1}.$ext',
          [
            '-f',
            'lavfi',
            '-i',
            'aevalsrc=sin(2*PI*440*t):s=44100:c=stereo',
            '-ss',
            '${i * 2}',
            '-t',
            '2',
            '-c:a',
            codec,
            if (codec == 'libmp3lame') ...['-b:a', '256k'],
          ],
          needs: [codec],
          ids: ['AUD-002'],
          category: 'gapless',
          expect: {'video': 0, 'audio': 1, 'gaplessIndex': i},
        );
      }
    }
    // ReplayGain-tagged track (AUD-004).
    await item(
      'replaygain.flac',
      [
        ...sweep,
        '-t',
        '3',
        '-c:a',
        'flac',
        '-metadata',
        'REPLAYGAIN_TRACK_GAIN=-6.50 dB',
        '-metadata',
        'REPLAYGAIN_ALBUM_GAIN=-7.25 dB',
      ],
      needs: ['flac'],
      ids: ['AUD-004'],
      category: c,
      expect: {'audio': 1, 'replayGainTrack': -6.5, 'replayGainAlbum': -7.25},
    );
    // CUE sheet over one FLAC (AUD-001).
    await item(
      'cue_album.flac',
      [...sweep, '-t', '9', '-c:a', 'flac'],
      needs: ['flac'],
      ids: ['AUD-001'],
      category: c,
      expect: {'audio': 1},
    );
    File(p('cue_album.cue')).writeAsStringSync(
      'PERFORMER "Mediahro"\nTITLE "Corpus"\nFILE "cue_album.flac" WAVE\n'
      '  TRACK 01 AUDIO\n    TITLE "One"\n    INDEX 01 00:00:00\n'
      '  TRACK 02 AUDIO\n    TITLE "Two"\n    INDEX 01 00:03:00\n'
      '  TRACK 03 AUDIO\n    TITLE "Three"\n    INDEX 01 00:06:00\n',
    );
    items.add({
      'file': 'cue_album.cue',
      'category': c,
      'ids': ['AUD-001', 'VID-001'],
      'expect': {'audio': 1, 'chapters': 3},
    });
    written(
      'tracker.mod',
      _modFile(),
      category: c,
      ids: ['AUD-001'],
      expect: {'video': 0, 'audio': 1, 'container': 'libopenmpt'},
    );
  }

  // ------------------------------------------------------------ subtitles --

  Future<void> _subtitles() async {
    const c = 'subtitles';
    // Charsets (SUB-013): same text in legacy encodings, plus UTF-8 BOM.
    final text = {
      'utf8bom': ('Привет, мир', <int>[0xEF, 0xBB, 0xBF]),
      'cp1251': ('Привет, мир', <int>[]),
    };
    for (final MapEntry(key: name, value: (s, bom)) in text.entries) {
      final body = '1\n00:00:00,500 --> 00:00:03,000\n$s\n';
      final bytes = name == 'cp1251'
          ? _cp1251(body)
          : [...bom, ...utf8.encode(body)];
      written(
        'subs_$name.srt',
        bytes,
        category: c,
        ids: ['SUB-013'],
        expect: {'subText': s},
      );
    }
    written(
      'subs.vtt',
      utf8.encode(
        'WEBVTT\n\n00:00:00.500 --> 00:00:02.000\nHello <b>VTT</b>\n',
      ),
      category: c,
      ids: ['SUB-010'],
      expect: {'subText': 'Hello VTT'},
    );
    written(
      'subs.smi',
      utf8.encode(
        '<SAMI><HEAD><STYLE TYPE="text/css"><!-- .ENCC {Name: English; '
        'lang: en-US;} --></STYLE></HEAD>\n<BODY>\n'
        '<SYNC Start=500><P Class=ENCC>Hello SAMI</P>\n'
        '<SYNC Start=2000><P Class=ENCC>&nbsp;</P>\n</BODY></SAMI>\n',
      ),
      category: c,
      ids: ['SUB-010'],
      expect: {'subText': 'Hello SAMI'},
    );
    written(
      'subs_microdvd.sub',
      utf8.encode('{1}{1}25\n{12}{50}Hello MicroDVD\n'),
      category: c,
      ids: ['SUB-010'],
      expect: {'subText': 'Hello MicroDVD'},
    );
    written(
      'subs.ssa',
      utf8.encode(
        '[Script Info]\nScriptType: v4.00\n\n[V4 Styles]\n'
        'Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, TertiaryColour, BackColour, Bold, Italic, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, AlphaLevel, Encoding\n'
        'Style: Default,Arial,28,16777215,65535,65535,0,0,0,1,2,0,2,10,10,10,0,1\n\n'
        '[Events]\nFormat: Marked, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text\n'
        'Dialogue: Marked=0,0:00:00.50,0:00:02.00,Default,,0000,0000,0000,,Hello SSA\n',
      ),
      category: c,
      ids: ['SUB-010'],
      expect: {'subText': 'Hello SSA'},
    );
    written(
      'subs.sup',
      _pgs(),
      category: c,
      ids: ['SUB-011'],
      expect: {
        'sub': 1,
        'subCodecs': ['hdmv_pgs_subtitle'],
      },
    );
    // Image subtitles (SUB-011): VobSub and DVB re-encoded from the PGS
    // bitmaps (ffmpeg converts bitmap to bitmap only).
    for (final (name, codec, fmt) in [
      ('mkv_vobsub.mkv', 'dvdsub', 'dvd_subtitle'),
      ('ts_dvbsub.ts', 'dvbsub', 'dvb_subtitle'),
    ]) {
      await item(
        name,
        [
          ..._video,
          '-i',
          p('subs.sup'),
          '-t',
          '5',
          '-map',
          '0:v',
          '-map',
          '1:s',
          '-c:v',
          'mpeg2video',
          '-b:v',
          '1M',
          '-c:s',
          codec,
        ],
        needs: [codec, 'mpeg2video'],
        ids: ['SUB-011'],
        category: c,
        expect: {
          'video': 1,
          'sub': 1,
          'subCodecs': [fmt],
        },
      );
    }
  }

  // ----------------------------------------------------------- edge cases --

  Future<void> _edgeCases() async {
    const c = 'edge';
    final src = File(p('mkv_multitrack.mkv'));
    if (src.existsSync()) {
      final bytes = src.readAsBytesSync();
      written(
        'truncated.mkv',
        bytes.sublist(0, (bytes.length * 0.6).round()),
        category: c,
        ids: ['VID-005'],
        expect: {'video': 1, 'truncated': true},
      );
    }
    written(
      'zero_bytes.mkv',
      const [],
      category: c,
      ids: ['CORE-011'],
      expect: {'error': 'unsupportedFormat'},
    );
    written(
      'garbage.mp4',
      List<int>.generate(4096, (i) => (i * 7919) & 0xff),
      category: c,
      ids: ['CORE-011'],
      expect: {'error': 'unsupportedFormat'},
    );
    final mp4 = File(p('mp4_h264_aac.mp4'));
    final avi = File(p('avi_mpeg4_mp3.avi'));
    if (avi.existsSync()) {
      written(
        'wrong_extension.mp4',
        avi.readAsBytesSync(),
        category: c,
        ids: ['VID-005'],
        expect: {'video': 1, 'audio': 1},
      );
    } else if (mp4.existsSync()) {
      written(
        'wrong_extension.mkv',
        mp4.readAsBytesSync(),
        category: c,
        ids: ['VID-005'],
        expect: {'video': 1, 'audio': 1},
      );
    }
  }

  void _playlists() {
    const c = 'playlists';
    final files = [
      'webm_vp9_opus.webm',
      'avi_mpeg4_mp3.avi',
    ].where((f) => File(p(f)).existsSync()).toList();
    if (files.isEmpty) return;
    written(
      'playlist.m3u',
      utf8.encode(
        '#EXTM3U\n${files.map((f) => '#EXTINF:5,$f\n$f').join('\n')}\n',
      ),
      category: c,
      ids: ['VID-001'],
      expect: {'playlistEntries': files.length},
    );
    written(
      'playlist.pls',
      utf8.encode(
        '[playlist]\n${[for (var i = 0; i < files.length; i++) 'File${i + 1}=${files[i]}'].join('\n')}\n'
        'NumberOfEntries=${files.length}\nVersion=2\n',
      ),
      category: c,
      ids: ['VID-001'],
      expect: {'playlistEntries': files.length},
    );
    written(
      'playlist.xspf',
      utf8.encode(
        '<?xml version="1.0" encoding="UTF-8"?>\n'
        '<playlist version="1" xmlns="http://xspf.org/ns/0/"><trackList>'
        '${files.map((f) => '<track><location>$f</location></track>').join()}'
        '</trackList></playlist>\n',
      ),
      category: c,
      ids: ['VID-001'],
      expect: {'playlistEntries': files.length},
    );
  }
}

extension on _Generator {
  /// Black video for pixel-level subtitle checks plus external-subtitle
  /// layouts for SUB-012 lookup.
  Future<void> _subtitleScenes() async {
    const c = 'subtitle-scenes';
    await item(
      'black.mkv',
      [
        '-f',
        'lavfi',
        '-i',
        'color=c=black:size=640x360:rate=25',
        '-f',
        'lavfi',
        '-i',
        'anullsrc=r=48000:cl=stereo',
        '-t',
        '10',
        '-c:v',
        'mpeg4',
        '-q:v',
        '2',
        '-c:a',
        'libopus',
      ],
      needs: ['mpeg4', 'libopus'],
      ids: ['SUB-010', 'SUB-014'],
      category: c,
      expect: {'video': 1, 'audio': 1},
    );
    written(
      'subs.ttml',
      utf8.encode(
        '<?xml version="1.0" encoding="UTF-8"?>\n'
        '<tt xmlns="http://www.w3.org/ns/ttml" '
        'xmlns:ttp="http://www.w3.org/ns/ttml#parameter" ttp:frameRate="25">\n'
        '<body><div>\n'
        '<p begin="00:00:00.500" end="00:00:02.000">Hello <span>TTML</span></p>\n'
        '<p begin="2.5s" dur="2s">Line one<br/>Line two</p>\n'
        '</div></body></tt>\n',
      ),
      category: c,
      ids: ['SUB-010'],
      expect: {'subText': 'Hello TTML'},
    );
    written(
      'lyrics.lrc',
      utf8.encode(
        '[ar:Mediahro]\n[ti:Corpus]\n[00:00.50]Hello LRC\n'
        '[00:02.50][00:04.00]Chorus line\n',
      ),
      category: c,
      ids: ['SUB-010'],
      expect: {'subText': 'Hello LRC'},
    );
    written(
      'timed.txt',
      utf8.encode('00:00:00.500 Hello TXT\n00:00:02.500 Second|line\n'),
      category: c,
      ids: ['SUB-010'],
      expect: {'subText': 'Hello TXT'},
    );
    // SUB-012: same-name, language-suffixed and Subs/ folder subtitles.
    final dir = Directory(p('ext_subs'))..createSync(recursive: true);
    Directory('${dir.path}/Subs').createSync(recursive: true);
    final black = File(p('black.mkv'));
    if (black.existsSync()) black.copySync('${dir.path}/movie.mkv');
    File('${dir.path}/movie.srt').writeAsStringSync(_Generator._srt);
    File('${dir.path}/movie.en.srt').writeAsStringSync(_Generator._srt);
    File('${dir.path}/Subs/movie.fr.srt').writeAsStringSync(_Generator._srt);
    File('${dir.path}/unrelated.srt').writeAsStringSync(_Generator._srt);
  }

  /// DSD64 stereo DSF with a 1 kHz tone from a second-order sigma-delta
  /// modulator (AUD-001 DSF, AUD-043 PCM conversion).
  void _dsd() {
    const fs = 2822400;
    const seconds = 2;
    const blockSize = 4096;
    const samples = fs * seconds;
    const bytesPerChannel = samples ~/ 8;
    const blocks = (bytesPerChannel + blockSize - 1) ~/ blockSize;
    final channel = Uint8List(blocks * blockSize);
    var i1 = 0.0;
    var i2 = 0.0;
    var y = 0.0;
    for (var n = 0; n < samples; n++) {
      final x = 0.5 * math.sin(2 * math.pi * 1000 * n / fs);
      i1 += x - y;
      i2 += i1 - y;
      y = i2 >= 0 ? 1.0 : -1.0;
      if (y > 0) channel[n >> 3] |= 1 << (n & 7); // LSB first
    }
    final data = BytesBuilder();
    for (var b = 0; b < blocks; b++) {
      for (var ch = 0; ch < 2; ch++) {
        data.add(
          Uint8List.sublistView(channel, b * blockSize, (b + 1) * blockSize),
        );
      }
    }
    final payload = data.takeBytes();
    final out = BytesBuilder();
    void u32(int v) => out.add(
      Uint8List(4)..buffer.asByteData().setUint32(0, v, Endian.little),
    );
    void u64(int v) => out.add(
      Uint8List(8)..buffer.asByteData().setUint64(0, v, Endian.little),
    );
    final total = 28 + 52 + 12 + payload.length;
    out.add(ascii.encode('DSD '));
    u64(28);
    u64(total);
    u64(0);
    out.add(ascii.encode('fmt '));
    u64(52);
    u32(1); // version
    u32(0); // DSD raw
    u32(2); // stereo
    u32(2); // channels
    u32(fs);
    u32(1); // bits per sample (LSB first)
    u64(samples);
    u32(blockSize);
    u32(0);
    out.add(ascii.encode('data'));
    u64(12 + payload.length);
    out.add(payload);
    written(
      'dsd64.dsf',
      out.takeBytes(),
      category: 'audio',
      ids: ['AUD-001', 'AUD-043'],
      expect: {'video': 0, 'audio': 1, 'audioCodec': 'dsd_lsbf_planar'},
    );
  }
}

/// Windows-1251 encoder for the Cyrillic test strings.
List<int> _cp1251(String s) => [
  for (final r in s.runes)
    if (r < 0x80)
      r
    else if (r >= 0x410 && r <= 0x44F)
      r - 0x410 + 0xC0
    else if (r == 0x401)
      0xA8
    else if (r == 0x451)
      0xB8
    else
      0x3F,
];

/// A minimal 4-channel ProTracker module: one sample (square wave), one
/// pattern playing it on all channels (AUD-001, libopenmpt).
List<int> _modFile() {
  final b = BytesBuilder();
  List<int> pad(String s, int n) => [
    ...ascii.encode(s),
    ...List<int>.filled(n - s.length, 0),
  ];
  b.add(pad('mediahro corpus', 20));
  const sampleWords = 32;
  for (var i = 0; i < 31; i++) {
    b.add(pad(i == 0 ? 'square' : '', 22));
    final words = i == 0 ? sampleWords : 0;
    b
      ..add([words >> 8, words & 0xff]) // length in words
      ..add([0, 64]) // finetune, volume
      ..add([0, 0]) // repeat offset
      ..add(i == 0 ? [0, sampleWords] : [0, 1]); // repeat length
  }
  b
    ..add([1, 127]) // song length, restart
    ..add(List<int>.filled(128, 0)) // order table
    ..add(ascii.encode('M.K.'));
  // Pattern 0: 64 rows × 4 channels; note C-3 (period 214) on row 0.
  for (var row = 0; row < 64; row++) {
    for (var ch = 0; ch < 4; ch++) {
      if (row % 16 == 0) {
        b.add([0x10 | (214 >> 8), 214 & 0xff, 0x10, 0x00]);
      } else {
        b.add([0, 0, 0, 0]);
      }
    }
  }
  b.add([
    for (var i = 0; i < sampleWords * 2; i++)
      if (i < sampleWords) 0x40 else 0xC0,
  ]);
  return b.takeBytes();
}

/// A one-caption PGS stream (`.sup`): PCS, WDS, PDS, ODS, END segments with
/// a 64×16 white rectangle shown at 0.5 s and cleared at 2 s (SUB-011).
List<int> _pgs() {
  final out = BytesBuilder();
  // Segments of one display set get strictly increasing timestamps (one
  // 90 kHz tick apart) so players that sort packets keep their order.
  var tick = 0;
  var lastMs = -1;
  void seg(int ptsMs, int type, List<int> payload) {
    tick = ptsMs == lastMs ? tick + 1 : 0;
    lastMs = ptsMs;
    final pts = ptsMs * 90 + tick;
    out
      ..add(ascii.encode('PG'))
      ..add(_u32(pts))
      ..add(_u32(0)) // DTS is 0 in real-world .sup files
      ..add([type])
      ..add([payload.length >> 8, payload.length & 0xff])
      ..add(payload);
  }

  List<int> pcs({required bool show, required int number}) => [
    ..._u16(640), ..._u16(360), 0x10, // size, frame rate
    ..._u16(number),
    if (show) 0x80 else 0x00, // epoch start / normal
    0x00, 0x00,
    if (show) 1 else 0, // objects
    if (show) ...[..._u16(0), 0, 0x00, ..._u16(288), ..._u16(300)],
  ];
  const w = 64;
  const h = 16;
  // RLE: each line is `w` pixels of colour 1, then end-of-line (0x00 0x00).
  final rle = <int>[];
  for (var y = 0; y < h; y++) {
    rle.addAll([0x00, 0xC0 | (w >> 8), w & 0xff, 0x01, 0x00, 0x00]);
  }
  seg(500, 0x16, pcs(show: true, number: 0));
  seg(500, 0x17, [1, 0, ..._u16(288), ..._u16(300), ..._u16(w), ..._u16(h)]);
  seg(500, 0x14, [0, 0, 1, 235, 128, 128, 255]); // palette: index 1 white
  seg(500, 0x15, [
    ..._u16(0), 0, 0xC0, // object id, version, first+last
    ..._u24(rle.length + 4), ..._u16(w), ..._u16(h), ...rle,
  ]);
  seg(500, 0x80, const []);
  seg(2000, 0x16, pcs(show: false, number: 1));
  seg(2000, 0x17, [1, 0, ..._u16(288), ..._u16(300), ..._u16(w), ..._u16(h)]);
  seg(2000, 0x14, [
    0,
    1,
    1,
    235,
    128,
    128,
    255,
  ]); // palette again (ffmpeg needs it per set)
  seg(2000, 0x80, const []);
  return out.takeBytes();
}

List<int> _u16(int v) => [(v >> 8) & 0xff, v & 0xff];
List<int> _u24(int v) => [(v >> 16) & 0xff, (v >> 8) & 0xff, v & 0xff];
List<int> _u32(int v) => [
  (v >> 24) & 0xff,
  (v >> 16) & 0xff,
  (v >> 8) & 0xff,
  v & 0xff,
];
