import 'package:mediahro_engine/src/api/models.dart';
import 'package:mediahro_engine/src/mpv/mpv_node.dart';

/// Properties `MpvEngine` observes, with the format each is read in.
const Map<String, int> observedProperties = {
  'time-pos': MpvFormat.double_,
  'duration': MpvFormat.double_,
  'pause': MpvFormat.flag,
  'idle-active': MpvFormat.flag,
  'eof-reached': MpvFormat.flag,
  'paused-for-cache': MpvFormat.flag,
  'seeking': MpvFormat.flag,
  'demuxer-cache-time': MpvFormat.double_,
  'speed': MpvFormat.double_,
  'volume': MpvFormat.double_,
  'mute': MpvFormat.flag,
  'track-list': MpvFormat.node,
  'chapter-list': MpvFormat.node,
  'vid': MpvFormat.string,
  'aid': MpvFormat.string,
  'sid': MpvFormat.string,
  'secondary-sid': MpvFormat.string,
  'audio-delay': MpvFormat.double_,
  'sub-delay': MpvFormat.double_,
  'secondary-sub-delay': MpvFormat.double_,
  'video-params': MpvFormat.node,
  'hwdec-current': MpvFormat.string,
  'file-format': MpvFormat.string,
  'video-format': MpvFormat.string,
  'frame-drop-count': MpvFormat.int64,
  'decoder-frame-drop-count': MpvFormat.int64,
  'video-bitrate': MpvFormat.double_,
  'container-fps': MpvFormat.double_,
  'audio-params': MpvFormat.node,
  'audio-out-params': MpvFormat.node,
  'current-ao': MpvFormat.string,
  'audio-device': MpvFormat.string,
  'audio-exclusive': MpvFormat.flag,
  'secondary-sub-text': MpvFormat.string,
};

Duration? _seconds(Object? v) => v is num
    ? Duration(microseconds: (v * Duration.microsecondsPerSecond).round())
    : null;

int? _trackId(Object? v) => v is String ? int.tryParse(v) : null;

/// Applies one observed property change to [s] (pure; unit-tested).
///
/// Status transitions that depend on events (opening, errors) are applied by
/// the engine; this only maps property values.
PlaybackState applyProperty(PlaybackState s, String name, Object? value) {
  switch (name) {
    case 'time-pos':
      return s.copyWith(position: _seconds(value) ?? s.position);
    case 'duration':
      return s.copyWith(duration: _seconds(value));
    case 'demuxer-cache-time':
      return s.copyWith(bufferedUntil: _seconds(value) ?? Duration.zero);
    case 'speed':
      return value is num ? s.copyWith(rate: value.toDouble()) : s;
    case 'volume':
      return value is num ? s.copyWith(volume: value / 100) : s;
    case 'mute':
      return s.copyWith(muted: value == true);
    case 'track-list':
      return s.copyWith(tracks: parseTrackList(value));
    case 'chapter-list':
      return s.copyWith(chapters: parseChapters(value));
    case 'vid':
      return s.copyWith(videoTrackId: _trackId(value));
    case 'aid':
      return s.copyWith(audioTrackId: _trackId(value));
    case 'sid':
      return s.copyWith(subtitleTrackId: _trackId(value));
    case 'secondary-sid':
      return s.copyWith(secondarySubtitleTrackId: _trackId(value));
    case 'audio-delay':
      return s.copyWith(audioDelay: _seconds(value) ?? Duration.zero);
    case 'sub-delay':
      return s.copyWith(subtitleDelay: _seconds(value) ?? Duration.zero);
    case 'secondary-sub-delay':
      return s.copyWith(
        secondarySubtitleDelay: _seconds(value) ?? Duration.zero,
      );
    case 'secondary-sub-text':
      return s.copyWith(
        secondarySubtitleText: value is String && value.isNotEmpty
            ? value
            : null,
      );
    case 'video-params':
      return s.copyWith(video: applyVideoParams(s.video, value, s.tracks));
    case 'hwdec-current':
      return s.copyWith(video: s.video.copyWith(hwdec: parseHwdec(value)));
    case 'file-format':
      return s.copyWith(
        video: s.video.copyWith(container: value is String ? value : null),
      );
    case 'video-format':
      return s.copyWith(
        video: s.video.copyWith(videoCodec: value is String ? value : null),
      );
    case 'frame-drop-count':
    case 'decoder-frame-drop-count':
      // Both counters contribute; the engine keeps the latest of each.
      return s;
    case 'video-bitrate':
      return s.copyWith(
        video: s.video.copyWith(bitrate: value is num ? value.round() : null),
      );
    case 'container-fps':
      return s.copyWith(
        video: s.video.copyWith(fps: value is num ? value.toDouble() : null),
      );
    default:
      return s;
  }
}

/// `track-list` → [Track]s (VID-001…003, SUB-012).
List<Track> parseTrackList(Object? value) {
  if (value is! List) return const [];
  final tracks = <Track>[];
  for (final t in value) {
    if (t is! Map<String, Object?>) continue;
    final type = switch (t['type']) {
      'video' => TrackType.video,
      'audio' => TrackType.audio,
      'sub' => TrackType.subtitle,
      _ => null,
    };
    final id = t['id'];
    if (type == null || id is! int) continue;
    // Cover art is a video track in mpv; it is not a selectable video.
    if (type == TrackType.video && t['albumart'] == true) continue;
    final title = t['title'];
    tracks.add(
      Track(
        id: id,
        type: type,
        title: title is String ? title : null,
        language: _lang(t['lang']),
        codec: t['codec'] as String?,
        channels: _int(t['demux-channel-count']),
        sampleRate: _int(t['demux-samplerate']),
        width: _int(t['demux-w']),
        height: _int(t['demux-h']),
        fps: (t['demux-fps'] as num?)?.toDouble(),
        isDefault: t['default'] == true,
        isForced: t['forced'] == true,
        isExternal: t['external'] == true,
        isAudioDescription:
            t['visual-impaired'] == true ||
            (title is String && _adTitle.hasMatch(title)),
        isHearingImpaired:
            t['hearing-impaired'] == true ||
            (title is String && _sdhTitle.hasMatch(title)),
        dolbyVisionProfile: _int(t['dolby-vision-profile']),
        replayGainTrackDb: (t['replaygain-track-gain'] as num?)?.toDouble(),
        replayGainAlbumDb: (t['replaygain-album-gain'] as num?)?.toDouble(),
      ),
    );
  }
  return tracks;
}

final _adTitle = RegExp(
  r'\b(audio description|described|descriptive)\b|\bAD\b',
  caseSensitive: false,
);
final _sdhTitle = RegExp(
  r'\b(SDH|CC|hearing impaired)\b',
  caseSensitive: false,
);

int? _int(Object? v) => v is num ? v.toInt() : null;

String? _lang(Object? v) =>
    v is String && v.isNotEmpty && v != 'und' ? normaliseLanguage(v) : null;

/// ISO 639-2/B and /T three-letter codes → BCP 47 primary tags for the
/// languages that matter for track selection; unknown codes pass through.
String normaliseLanguage(String code) {
  final c = code.toLowerCase();
  return _iso639.containsKey(c) ? _iso639[c]! : c;
}

const _iso639 = {
  'eng': 'en',
  'fre': 'fr',
  'fra': 'fr',
  'ger': 'de',
  'deu': 'de',
  'spa': 'es',
  'ita': 'it',
  'por': 'pt',
  'rus': 'ru',
  'jpn': 'ja',
  'chi': 'zh',
  'zho': 'zh',
  'kor': 'ko',
  'ara': 'ar',
  'heb': 'he',
  'hin': 'hi',
  'tam': 'ta',
  'tel': 'te',
  'dut': 'nl',
  'nld': 'nl',
  'swe': 'sv',
  'nor': 'no',
  'nob': 'nb',
  'dan': 'da',
  'fin': 'fi',
  'pol': 'pl',
  'tur': 'tr',
  'gre': 'el',
  'ell': 'el',
  'cze': 'cs',
  'ces': 'cs',
  'hun': 'hu',
  'rum': 'ro',
  'ron': 'ro',
  'ukr': 'uk',
  'tha': 'th',
  'vie': 'vi',
  'ind': 'id',
  'may': 'ms',
  'msa': 'ms',
  'per': 'fa',
  'fas': 'fa',
  'bul': 'bg',
  'hrv': 'hr',
  'srp': 'sr',
  'slv': 'sl',
  'slo': 'sk',
  'slk': 'sk',
  'cat': 'ca',
  'baq': 'eu',
  'eus': 'eu',
  'glg': 'gl',
  'ice': 'is',
  'isl': 'is',
  'ben': 'bn',
};

/// `chapter-list` → [Chapter]s.
List<Chapter> parseChapters(Object? value) {
  if (value is! List) return const [];
  return [
    for (final c in value)
      if (c is Map<String, Object?> && c['time'] is num)
        Chapter(
          start: _seconds(c['time'])!,
          title: c['title'] is String ? c['title']! as String : null,
        ),
  ];
}

HwdecPath parseHwdec(Object? v) => switch (v) {
  null || '' || 'no' => HwdecPath.none,
  final String s when s.startsWith('mediacodec') => HwdecPath.mediacodec,
  final String s when s.startsWith('videotoolbox') => HwdecPath.videotoolbox,
  final String s when s.startsWith('d3d11va') => HwdecPath.d3d11va,
  final String s when s.startsWith('d3d12va') => HwdecPath.d3d12va,
  final String s when s.startsWith('vulkan') => HwdecPath.vulkan,
  _ => HwdecPath.other,
};

/// `video-params` (+ the selected track) → HDR type, size (VID-031…035).
VideoStats applyVideoParams(VideoStats v, Object? params, List<Track> tracks) {
  if (params is! Map<String, Object?>) {
    return v.copyWith(hdr: HdrType.sdr, width: null, height: null);
  }
  final dv = tracks
      .where((t) => t.type == TrackType.video)
      .map((t) => t.dolbyVisionProfile)
      .nonNulls
      .firstOrNull;
  return v.copyWith(
    width: _int(params['dw']) ?? _int(params['w']),
    height: _int(params['dh']) ?? _int(params['h']),
    hdr: detectHdr(params, dolbyVisionProfile: dv),
    dolbyVisionProfile: dv,
    peakNits: (params['max-luma'] as num?)?.toDouble(),
    maxCll: (params['max-cll'] as num?)?.toDouble(),
  );
}

/// Dynamic-range classification of the decoded stream.
///
/// Dolby Vision is reported for profiles 5, 7 and 8 (the stream plays as its
/// base layer or through libplacebo reshaping, VID-033…035); HDR10+ when the
/// frame carries per-scene MaxRGB; otherwise by transfer function.
HdrType detectHdr(Map<String, Object?> params, {int? dolbyVisionProfile}) {
  if (dolbyVisionProfile != null) return HdrType.dolbyVision;
  final gamma = params['gamma'];
  if (gamma == 'pq') {
    final dynamic10Plus = [
      'scene-max-r',
      'scene-max-g',
      'scene-max-b',
    ].any((k) => (params[k] as num? ?? 0) > 0);
    return dynamic10Plus ? HdrType.hdr10Plus : HdrType.hdr10;
  }
  if (gamma == 'hlg') return HdrType.hlg;
  return HdrType.sdr;
}

/// Truthful output-path classification (AUD-006).
///
/// `bitPerfect` only when the device runs exclusively at the decoded sample
/// rate and format with no DSP; `passthrough` for compressed bitstreams;
/// `resampled` when the rate or channel layout changed; `mixed` when the OS
/// mixer sits in between (shared mode).
AudioOutputInfo audioOutputInfo({
  required Map<String, Object?>? decoded,
  required Map<String, Object?>? output,
  required bool exclusive,
  required bool dspActive,
  String? device,
  String? ao,
}) {
  if (output == null) {
    return AudioOutputInfo(device: device);
  }
  final outFormat = output['format'] as String?;
  final outRate = _int(output['samplerate']);
  final outChannels = _int(output['channel-count']);
  final inRate = _int(decoded?['samplerate']);
  final inFormat = decoded?['format'] as String?;
  final inChannels = _int(decoded?['channel-count']);
  final AudioOutputPath path;
  if (outFormat != null && outFormat.startsWith('spdif')) {
    path = AudioOutputPath.passthrough;
  } else if (inRate != null && outRate != null && inRate != outRate ||
      inChannels != null && outChannels != null && inChannels != outChannels) {
    path = AudioOutputPath.resampled;
  } else if (!exclusive) {
    path = AudioOutputPath.mixed;
  } else if (dspActive || inFormat != null && inFormat != outFormat) {
    path = AudioOutputPath.resampled;
  } else {
    path = AudioOutputPath.bitPerfect;
  }
  return AudioOutputInfo(
    device: device,
    format: outFormat,
    sampleRate: outRate,
    bitDepth: sampleFormatBits(outFormat),
    channels: outChannels,
    path: path,
    output: ao,
  );
}

/// Bits per sample of an mpv sample format (`s16`, `s32`, `floatp`, …).
int? sampleFormatBits(String? format) => switch (format) {
  null => null,
  final f when f.startsWith('u8') => 8,
  final f when f.startsWith('s16') => 16,
  final f when f.startsWith('s24') => 24,
  final f when f.startsWith('s32') || f.startsWith('float') => 32,
  final f when f.startsWith('s64') || f.startsWith('double') => 64,
  _ => null,
};

/// libmpv end-of-file error → user-facing category (CORE-011, docs/06 §8).
EngineErrorCode mapEndFileError(int error, {required bool isNetwork}) =>
    switch (error) {
      MpvError.unknownFormat => EngineErrorCode.unsupportedFormat,
      MpvError.nothingToPlay => EngineErrorCode.unsupportedFormat,
      MpvError.loadingFailed =>
        isNetwork
            ? EngineErrorCode.networkTimeout
            : EngineErrorCode.sourceUnavailable,
      MpvError.aoInitFailed ||
      MpvError.voInitFailed => EngineErrorCode.decodeFailed,
      MpvError.unsupported ||
      MpvError.notImplemented => EngineErrorCode.unsupportedFormat,
      _ => EngineErrorCode.unknown,
    };
