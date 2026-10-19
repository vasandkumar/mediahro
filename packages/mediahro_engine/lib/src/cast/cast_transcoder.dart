import 'dart:async';
import 'dart:io';

import 'package:mediahro_engine/src/api/media_source.dart';
import 'package:mediahro_engine/src/cast/cast_plan.dart';
import 'package:mediahro_engine/src/mpv/mpv_client.dart';
import 'package:mediahro_engine/src/mpv/mpv_node.dart';
import 'package:mediahro_engine/src/mpv/mpv_options.dart';
import 'package:mediahro_engine/src/mpv/render_mapping.dart';
import 'package:mediahro_engine/src/mpv/stream_protocol.dart';
import 'package:mediahro_engine/src/mpv/subtitle_convert.dart';
// The mpv bindings are an engine-private part of mediahro_ffi (lane B1).
// ignore: implementation_imports
import 'package:mediahro_ffi/src/mpv/mpv.dart' show Libmpv;

/// H.264 encoders in preference order (CAST-005): OS encoders first —
/// MediaCodec, VideoToolbox, Media Foundation are licensed with the OS —
/// then VP8 (libvpx, BSD) where a receiver accepts it. No x264/openh264
/// (docs/09 §2, §4).
List<String> castVideoEncoders(EnginePlatform p) => switch (p) {
  EnginePlatform.android => const ['h264_mediacodec', 'libvpx'],
  EnginePlatform.ios ||
  EnginePlatform.macos => const ['h264_videotoolbox', 'libvpx'],
  EnginePlatform.windows => const ['h264_mf', 'libvpx'],
  EnginePlatform.linux => const ['h264_vaapi', 'libvpx'],
};

/// A running transcode for a cast session (CAST-005). Output lands in
/// [directory]: an HLS playlist (`index.m3u8` + segments) for H.264, or a
/// progressive `stream.webm` for the VP8 fallback. Never used for library
/// storage; the directory is deleted on [stop].
final class CastTranscoder {
  CastTranscoder._(this.directory, this.encoder, this._client, this._protocol);

  final Directory directory;
  final String encoder;
  final MpvClient _client;
  final MpvStreamProtocol? _protocol;
  final _done = Completer<void>();
  var _stopped = false;

  /// File the cast server publishes.
  String get entry => encoder == 'libvpx' ? 'stream.webm' : 'index.m3u8';

  /// Completes when the whole item is encoded (or fails with the mpv error).
  Future<void> get done => _done.future;

  /// Completes once the receiver can start: the playlist lists a segment
  /// (HLS) or the stream has data (WebM).
  Future<void> ready({Duration timeout = const Duration(seconds: 30)}) async {
    final f = File('${directory.path}${Platform.pathSeparator}$entry');
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      if (f.existsSync()) {
        final ok = entry.endsWith('.m3u8')
            ? f.readAsStringSync().contains('#EXTINF')
            : f.lengthSync() > 64 * 1024;
        if (ok) return;
      }
      if (_done.isCompleted) {
        await _done.future;
        if (f.existsSync()) return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    throw TimeoutException('cast transcode did not start', timeout);
  }

  /// Starts encoding [source] for [plan], trying [encoders] in order.
  static Future<CastTranscoder> start(
    MediaSource source,
    CastPlan plan, {
    CastReceiver receiver = CastReceiver.chromecast,
    Duration? from,
    List<String>? encoders,
    EnginePlatform? platform,
    String? libmpvPath,
    void Function(MpvLogMessage message)? onLog,
  }) async {
    final candidates =
        encoders ?? castVideoEncoders(platform ?? EnginePlatform.current);
    Object? lastError;
    for (final encoder in candidates) {
      if (encoder == 'libvpx' && !receiver.videoCodecs.contains('vp8')) {
        continue;
      }
      final dir = await Directory.systemTemp.createTemp('mediahro-cast');
      try {
        final t = await _launch(
          source,
          plan,
          receiver,
          dir,
          encoder,
          from,
          libmpvPath,
          onLog,
        );
        // A missing encoder fails within the first second.
        await Future.any([t.ready(), t.done.then((_) {})]);
        return t;
      } on Object catch (e) {
        lastError = e;
        await dir.delete(recursive: true).catchError((Object _) => dir);
      }
    }
    throw StateError('no cast encoder available: $lastError');
  }

  static Future<CastTranscoder> _launch(
    MediaSource source,
    CastPlan plan,
    CastReceiver receiver,
    Directory dir,
    String encoder,
    Duration? from,
    String? libmpvPath,
    void Function(MpvLogMessage message)? onLog,
  ) async {
    final hls = encoder != 'libvpx';
    final out =
        '${dir.path}${Platform.pathSeparator}'
        '${hls ? 'index.m3u8' : 'stream.webm'}';
    final options = <String, String>{
      'config': 'no',
      'terminal': 'no',
      'load-scripts': 'no',
      'ytdl': 'no',
      'idle': 'yes',
      'o': out,
      'of': hls ? 'hls' : 'webm',
      if (hls)
        'ofopts':
            'hls_time=4,hls_list_size=0,hls_playlist_type=event,'
            'hls_segment_type=mpegts',
      'ovc': encoder,
      'ovcopts': switch (encoder) {
        'libvpx' => 'b=4M,deadline=realtime,cpu-used=8',
        'h264_mf' => 'b=8M,g=96,hw_encoding=0',
        _ => 'b=8M,g=96',
      },
      'oac': receiver.audioCodecs.contains('aac') ? 'aac' : 'libopus',
      'oacopts': 'b=192k',
      if (receiver.maxAudioChannels <= 2) 'audio-channels': 'stereo',
      'vf': "scale=w=-2:h='min(ih,${receiver.maxHeight})',format=yuv420p",
      'sid': 'no',
      'hr-seek': 'yes',
      if (from != null) 'start': secondsValue(from),
    };
    final client = await MpvClient.create(
      options: options,
      library: Libmpv.open(path: libmpvPath),
      logLevel: onLog == null ? 'warn' : 'v',
    );
    final protocol = MpvStreamProtocol.register(client);
    final t = CastTranscoder._(dir, encoder, client, protocol);
    client.events.listen((e) {
      switch (e) {
        case MpvLogMessage():
          onLog?.call(e);
        case MpvEndFile(:final reason, :final error):
          if (t._done.isCompleted) return;
          if (reason == MpvEndReason.error) {
            t._done.completeError(MpvException('cast encode', error));
          } else {
            // The muxer writes the last segment and the end-of-list tag
            // when the core shuts down.
            unawaited(t._finish());
          }
        default:
          break;
      }
    });
    final url = switch (source) {
      UriSource(:final uri) =>
        uri.scheme == 'file' ? uri.toFilePath() : uri.toString(),
      VirtualFileSource(:final file) =>
        protocol == null
            ? throw StateError('stream shim missing')
            : protocol.urlFor(file),
    };
    await client.command(['loadfile', url]);
    return t;
  }

  Future<void> _finish() async {
    _protocol?.shutdown();
    await _client.destroy();
    await _protocol?.dispose();
    if (!_done.isCompleted) _done.complete();
  }

  /// Stops encoding and deletes the output.
  Future<void> stop() async {
    if (_stopped) return;
    _stopped = true;
    _protocol?.shutdown();
    await _client.destroy();
    await _protocol?.dispose();
    if (!_done.isCompleted) _done.complete();
    await directory.delete(recursive: true).catchError((Object _) => directory);
  }
}

/// Extracts the cues of an embedded or external text subtitle track by
/// running a headless core at full speed (CAST-005: subtitles are served to
/// receivers as WebVTT).
Future<List<Cue>> extractSubtitleCues(
  MediaSource source, {
  required int trackId,
  String? libmpvPath,
  Duration timeout = const Duration(minutes: 5),
}) async {
  // Subtitles advance with the video clock, so video stays on (decoded to
  // a null output) and the file plays at 50x; untimed playback would
  // coalesce the property changes.
  final client = await MpvClient.create(
    options: const {
      'config': 'no',
      'terminal': 'no',
      'load-scripts': 'no',
      'ytdl': 'no',
      'idle': 'yes',
      'vo': 'null',
      'ao': 'null',
      'speed': '50',
      'hwdec': 'no',
    },
    library: Libmpv.open(path: libmpvPath),
  );
  final protocol = MpvStreamProtocol.register(client);
  final cues = <Cue>[];
  double? start;
  double? end;
  final done = Completer<void>();
  client.events.listen((e) {
    switch (e) {
      case MpvPropertyChange(:final name, :final value):
        switch (name) {
          // mpv reports start and end before the text of the same cue.
          case 'sub-start':
            start = value is double ? value : null;
          case 'sub-end':
            end = value is double ? value : null;
          case 'sub-text':
            final s = start;
            final t = end;
            if (value is String && value.isNotEmpty && s != null && t != null) {
              final at = Duration(milliseconds: (s * 1000).round());
              if (cues.isEmpty ||
                  cues.last.start != at ||
                  cues.last.text != value) {
                cues.add(
                  Cue(at, Duration(milliseconds: (t * 1000).round()), value),
                );
              }
            }
        }
      case MpvEndFile():
        if (!done.isCompleted) done.complete();
      default:
        break;
    }
  });
  client
    ..observe('sub-start', MpvFormat.double_)
    ..observe('sub-end', MpvFormat.double_)
    ..observe('sub-text', MpvFormat.string);
  try {
    final url = switch (source) {
      UriSource(:final uri) =>
        uri.scheme == 'file' ? uri.toFilePath() : uri.toString(),
      VirtualFileSource(:final file) => protocol!.urlFor(file),
    };
    await client.command(['loadfile', url, 'replace', '-1', 'sid=$trackId']);
    await done.future.timeout(timeout);
  } finally {
    protocol?.shutdown();
    await client.destroy();
    await protocol?.dispose();
  }
  return cues;
}
