import 'dart:async';
import 'dart:io';

import 'package:mediahro_engine/src/api/models.dart';
import 'package:mediahro_engine/src/mpv/mpv_client.dart';
import 'package:mediahro_engine/src/mpv/mpv_node.dart';
import 'package:mediahro_engine/src/mpv/render_mapping.dart';
import 'package:mediahro_engine/src/mpv/stream_protocol.dart';
import 'package:mediahro_ffi/mediahro_ffi.dart' show VirtualFile;
// The mpv bindings are an engine-private part of mediahro_ffi (lane B1).
// ignore: implementation_imports
import 'package:mediahro_ffi/src/mpv/mpv.dart' show Libmpv;

/// VID-042: exports a range of a source on a separate headless libmpv core,
/// so playback continues undisturbed.
///
/// - [ExportFormat.gif]: palette-optimised animated GIF (15 fps, at most
///   480 px wide), libavcodec's `gif` encoder.
/// - [ExportFormat.webp]: animated WebP (`libwebp_anim`).
/// - [ExportFormat.clipCopy]: lossless stream copy of the range through
///   mpv's demuxer cache (`dump-cache`); the container follows [out]'s
///   extension (`.mkv` keeps every track). Cuts land on the source's
///   packets, so a range starting between keyframes starts at the previous
///   one.
///
/// Subtitles are burnt into GIF/WebP when [subtitles] is true and kept as a
/// track in clip copies.
Future<void> exportRange({
  required String url,
  required Duration start,
  required Duration end,
  required ExportFormat format,
  required File out,
  VirtualFile? virtualFile,
  bool subtitles = false,
  String? libmpvPath,
  Duration timeout = const Duration(minutes: 10),
}) async {
  if (end <= start) throw ExportException('empty range $start…$end');
  final copy = format == ExportFormat.clipCopy;
  final options = <String, String>{
    'config': 'no',
    'terminal': 'no',
    'load-scripts': 'no',
    'ytdl': 'no',
    'idle': 'yes',
    'audio-display': 'no',
    if (copy) ...{
      // Play nothing; fill the demuxer cache over the range and dump it.
      'vo': 'null',
      'ao': 'null',
      'pause': 'yes',
      'cache': 'yes',
      'demuxer-max-bytes': '${1 << 30}',
      'demuxer-max-back-bytes': '${1 << 30}',
      'demuxer-readahead-secs': secondsValue(end - start + _slack),
      'sid': subtitles ? 'auto' : 'no',
    } else ...{
      'o': out.path,
      'of': format == ExportFormat.gif ? 'gif' : 'webp',
      'ovc': format == ExportFormat.gif ? 'gif' : 'libwebp_anim',
      if (format == ExportFormat.webp) 'ovcopts': 'quality=75,loop=0',
      'aid': 'no',
      'sid': subtitles ? 'auto' : 'no',
      'vf': format == ExportFormat.gif
          ? r'lavfi=[fps=15,scale=w=min(iw\,480):h=-2:flags=lanczos,split[a][b];'
                '[a]palettegen[p];[b][p]paletteuse]'
          : r'lavfi=[fps=15,scale=w=min(iw\,480):h=-2:flags=lanczos]',
      'start': secondsValue(start),
      'end': secondsValue(end),
      'hr-seek': 'yes',
    },
  };
  final client = await MpvClient.create(
    options: options,
    library: Libmpv.open(path: libmpvPath),
  );
  final protocol = MpvStreamProtocol.register(client);
  final loaded = Completer<void>();
  final ended = Completer<void>();
  final sub = client.events.listen((e) {
    switch (e) {
      case MpvFileLoaded():
        if (!loaded.isCompleted) loaded.complete();
      case MpvEndFile(:final reason, :final error):
        final failure = reason == MpvEndReason.error
            ? MpvException('export', error)
            : null;
        if (!loaded.isCompleted) {
          loaded.completeError(
            failure ?? const ExportException('nothing to export'),
          );
        }
        if (!ended.isCompleted) {
          failure == null ? ended.complete() : ended.completeError(failure);
        }
      default:
        break;
    }
  });
  try {
    final target = virtualFile == null || protocol == null
        ? url
        : protocol.urlFor(virtualFile);
    await client.loadfile(target);
    if (copy) {
      await loaded.future.timeout(timeout);
      await client.command(['seek', secondsValue(start), 'absolute+exact']);
      final deadline = DateTime.now().add(timeout);
      // Wait until the cache holds the whole range (or the file ends).
      while (DateTime.now().isBefore(deadline)) {
        final cached = await client.getProperty('demuxer-cache-time');
        final idle = await client.getProperty('demuxer-cache-idle');
        if ((cached is num && cached >= _seconds(end)) || idle == true) break;
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      await client.command([
        'dump-cache',
        secondsValue(start),
        secondsValue(end),
        out.path,
      ]);
    } else {
      // The muxer finalises the file when the core shuts down.
      await ended.future.timeout(timeout);
    }
  } finally {
    await sub.cancel();
    protocol?.shutdown();
    await client.destroy();
    await protocol?.dispose();
  }
  if (!out.existsSync() || out.lengthSync() == 0) {
    throw const ExportException('export produced no output');
  }
}

const _slack = Duration(seconds: 5);

double _seconds(Duration d) => d.inMicroseconds / 1e6;

/// An export that produced nothing (VID-042).
final class ExportException implements Exception {
  const ExportException(this.message);

  final String message;

  @override
  String toString() => 'ExportException: $message';
}
