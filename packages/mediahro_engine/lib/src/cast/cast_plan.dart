/// Casting pipeline decision (docs/05 §4.5, CAST-005): what a receiver can
/// play directly, what needs a container change (remux) and what must be
/// transcoded. Senders (Cast SDK, Open Screen, AirPlay, DLNA) are lane C4's;
/// they pick a [CastReceiver] profile and hand the plan to the cast server.
library;

import 'package:meta/meta.dart';

/// Containers the cast server can deliver.
enum CastContainer { mp4, webm, mpegts, hls, mkv, other }

/// Capabilities of a receiver class.
@immutable
final class CastReceiver {
  const CastReceiver({
    required this.name,
    required this.containers,
    required this.videoCodecs,
    required this.audioCodecs,
    this.maxHeight = 1080,
    this.maxFps = 60,
    this.tenBit = false,
    this.hdr = false,
    this.maxAudioChannels = 2,
    this.webVttSubtitles = true,
  });

  final String name;
  final Set<CastContainer> containers;
  final Set<String> videoCodecs;
  final Set<String> audioCodecs;
  final int maxHeight;
  final int maxFps;
  final bool tenBit;
  final bool hdr;
  final int maxAudioChannels;
  final bool webVttSubtitles;

  /// Chromecast (3rd gen) Default Media Receiver.
  static const chromecast = CastReceiver(
    name: 'chromecast',
    containers: {CastContainer.mp4, CastContainer.webm, CastContainer.hls},
    videoCodecs: {'h264', 'vp8'},
    audioCodecs: {'aac', 'mp3', 'opus', 'vorbis', 'flac'},
  );

  /// Chromecast Ultra / with Google TV.
  static const chromecast4k = CastReceiver(
    name: 'chromecast-4k',
    containers: {CastContainer.mp4, CastContainer.webm, CastContainer.hls},
    videoCodecs: {'h264', 'hevc', 'vp8', 'vp9', 'av1'},
    audioCodecs: {'aac', 'mp3', 'opus', 'vorbis', 'flac', 'ac3', 'eac3'},
    maxHeight: 2160,
    tenBit: true,
    hdr: true,
    maxAudioChannels: 8,
  );

  /// AirPlay (HLS from the cast server, played by AVPlayer).
  static const airplay = CastReceiver(
    name: 'airplay',
    containers: {CastContainer.mp4, CastContainer.hls},
    videoCodecs: {'h264', 'hevc'},
    audioCodecs: {'aac', 'mp3', 'ac3', 'eac3', 'alac', 'flac'},
    maxHeight: 2160,
    tenBit: true,
    hdr: true,
    maxAudioChannels: 8,
  );

  /// Generic DLNA renderer (conservative baseline).
  static const dlna = CastReceiver(
    name: 'dlna',
    containers: {CastContainer.mp4, CastContainer.mpegts},
    videoCodecs: {'h264', 'mpeg2video'},
    audioCodecs: {'aac', 'mp3', 'ac3'},
    webVttSubtitles: false,
  );
}

/// What the source contains (from `MpvEngine` track info).
@immutable
final class MediaProbe {
  const MediaProbe({
    required this.container,
    this.videoCodec,
    this.height,
    this.fps,
    this.tenBit = false,
    this.hdr = false,
    this.audioCodec,
    this.audioChannels,
  });

  final CastContainer container;
  final String? videoCodec;
  final int? height;
  final double? fps;
  final bool tenBit;
  final bool hdr;
  final String? audioCodec;
  final int? audioChannels;

  /// Maps an mpv `file-format` name to a container.
  static CastContainer containerOf(String? fileFormat) {
    final f = fileFormat ?? '';
    if (f == 'webm') return CastContainer.webm;
    // lavf reports Matroska and WebM together as `matroska,webm`.
    if (f.contains('matroska') || f == 'mkv') return CastContainer.mkv;
    if (f.contains('mp4') || f.contains('mov')) return CastContainer.mp4;
    if (f.contains('mpegts')) return CastContainer.mpegts;
    if (f.contains('hls')) return CastContainer.hls;
    return CastContainer.other;
  }
}

/// How a stream is prepared for a receiver.
enum StreamAction { copy, encode, drop }

@immutable
final class CastPlan {
  const CastPlan({
    required this.kind,
    required this.container,
    required this.video,
    required this.audio,
    this.reasons = const [],
  });

  final CastPlanKind kind;
  final CastContainer container;
  final StreamAction video;
  final StreamAction audio;

  /// Why the plan is not passthrough (shown in the cast sheet's details).
  final List<String> reasons;

  @override
  String toString() =>
      'CastPlan(${kind.name}, ${container.name}, video ${video.name}, '
      'audio ${audio.name}, $reasons)';
}

enum CastPlanKind {
  /// Serve the original file (byte ranges).
  passthrough,

  /// Same codecs, new container (MKV → fragmented MP4).
  remux,

  /// Re-encode at least one stream (H.264/AAC via OS encoders).
  transcode,
}

/// Decides the cheapest plan [receiver] can play (CAST-005).
CastPlan decideCastPlan(MediaProbe m, CastReceiver receiver) {
  final reasons = <String>[];
  var video = StreamAction.copy;
  var audio = StreamAction.copy;
  final v = m.videoCodec;
  if (v == null) {
    video = StreamAction.drop;
  } else {
    if (!receiver.videoCodecs.contains(v)) {
      reasons.add('video codec $v');
      video = StreamAction.encode;
    }
    if ((m.height ?? 0) > receiver.maxHeight) {
      reasons.add('resolution ${m.height}p');
      video = StreamAction.encode;
    }
    if ((m.fps ?? 0) > receiver.maxFps + 0.5) {
      reasons.add('frame rate ${m.fps}');
      video = StreamAction.encode;
    }
    if (m.tenBit && !receiver.tenBit) {
      reasons.add('10-bit video');
      video = StreamAction.encode;
    }
    if (m.hdr && !receiver.hdr) {
      reasons.add('HDR video');
      video = StreamAction.encode;
    }
  }
  final a = m.audioCodec;
  if (a == null) {
    audio = StreamAction.drop;
  } else {
    if (!receiver.audioCodecs.contains(a)) {
      reasons.add('audio codec $a');
      audio = StreamAction.encode;
    }
    if ((m.audioChannels ?? 2) > receiver.maxAudioChannels) {
      reasons.add('${m.audioChannels} audio channels');
      audio = StreamAction.encode;
    }
  }
  if (video != StreamAction.encode && audio != StreamAction.encode) {
    if (receiver.containers.contains(m.container)) {
      return CastPlan(
        kind: CastPlanKind.passthrough,
        container: m.container,
        video: video,
        audio: audio,
      );
    }
    reasons.add('container ${m.container.name}');
    final target = receiver.containers.contains(CastContainer.mp4)
        ? CastContainer.mp4
        : receiver.containers.first;
    return CastPlan(
      kind: CastPlanKind.remux,
      container: target,
      video: video,
      audio: audio,
      reasons: reasons,
    );
  }
  return CastPlan(
    kind: CastPlanKind.transcode,
    container: receiver.containers.contains(CastContainer.hls)
        ? CastContainer.hls
        : (receiver.containers.contains(CastContainer.mpegts)
              ? CastContainer.mpegts
              : CastContainer.mp4),
    video: video,
    audio: audio,
    reasons: reasons,
  );
}
