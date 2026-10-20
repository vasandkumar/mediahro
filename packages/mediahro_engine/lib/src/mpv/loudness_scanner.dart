import 'dart:async';
import 'dart:math' as math;

import 'package:mediahro_engine/src/api/media_source.dart';
import 'package:mediahro_engine/src/mpv/mpv_client.dart';
import 'package:mediahro_engine/src/mpv/mpv_node.dart';
import 'package:mediahro_engine/src/mpv/stream_protocol.dart';
// The mpv bindings are an engine-private part of mediahro_ffi (lane B1).
// ignore: implementation_imports
import 'package:mediahro_ffi/src/mpv/mpv.dart' show Libmpv;
import 'package:meta/meta.dart';

/// EBU R128 measurement of one item (AUD-004).
@immutable
final class LoudnessMeasurement {
  const LoudnessMeasurement({
    required this.integratedLufs,
    this.loudnessRangeLu,
    this.truePeakDbtp,
  });

  final double integratedLufs;
  final double? loudnessRangeLu;
  final double? truePeakDbtp;

  @override
  String toString() =>
      'LoudnessMeasurement($integratedLufs LUFS, LRA $loudnessRangeLu, '
      'TP $truePeakDbtp dBTP)';
}

/// Measures integrated loudness and true peak of files without ReplayGain
/// tags (AUD-004), for the library's background scan queue.
///
/// Runs FFmpeg's `ebur128` filter (the libebur128 algorithm, BS.1770-4)
/// inside a headless mpv core at full decode speed, so the scan needs no
/// extra library and reads any source the engine can play (incl.
/// `VirtualFile`s). The library stores the result; the engine applies it
/// through `OpenOptions.loudnessGainDb`.
abstract final class LoudnessScanner {
  static Future<LoudnessMeasurement?> measure(
    MediaSource source, {
    String? libmpvPath,
    Duration timeout = const Duration(minutes: 10),
  }) async {
    final client = await MpvClient.create(
      options: const {
        'config': 'no',
        'terminal': 'no',
        'load-scripts': 'no',
        'ytdl': 'no',
        'idle': 'yes',
        'vid': 'no',
        'vo': 'null',
        'ao': 'null',
        'ao-null-untimed': 'yes',
        'untimed': 'yes',
        // The filter's final summary is read at EOF, with the file loaded.
        'keep-open': 'yes',
        'af': '@r128:lavfi=[ebur128=metadata=1:peak=true]',
      },
      library: Libmpv.open(path: libmpvPath),
    );
    final protocol = MpvStreamProtocol.register(client);
    final done = Completer<bool>();
    client.events.listen((e) {
      switch (e) {
        case MpvPropertyChange(name: 'eof-reached', value: true):
          if (!done.isCompleted) done.complete(true);
        case MpvEndFile(:final reason) when reason == MpvEndReason.error:
          if (!done.isCompleted) done.complete(false);
        default:
          break;
      }
    });
    client.observe('eof-reached', MpvFormat.flag);
    try {
      final url = switch (source) {
        UriSource(:final uri) =>
          uri.scheme == 'file' ? uri.toFilePath() : uri.toString(),
        VirtualFileSource(:final file) =>
          protocol == null
              ? throw StateError('stream shim missing')
              : protocol.urlFor(file),
      };
      await client.loadfile(url);
      final ok = await done.future.timeout(timeout);
      if (!ok) return null;
      final meta = await client.getProperty('af-metadata/r128');
      if (meta is! Map<String, Object?>) return null;
      final m = meta;
      double? metric(String k) {
        final v = m[k];
        return v is String
            ? double.tryParse(v)
            : (v is num ? v.toDouble() : null);
      }

      final i = metric('lavfi.r128.I');
      if (i == null || i.isInfinite || i < -70) return null;
      final peaks = [
        for (final MapEntry(:key, :value) in m.entries)
          if (key.startsWith('lavfi.r128.true_peaks_ch'))
            double.tryParse('$value'),
      ].nonNulls;
      // Per-channel true peaks are linear sample values.
      final linear = peaks.isEmpty ? null : peaks.reduce(math.max);
      final tp = linear == null || linear <= 0
          ? null
          : 20 * math.log(linear) / math.ln10;
      return LoudnessMeasurement(
        integratedLufs: i,
        loudnessRangeLu: metric('lavfi.r128.LRA'),
        truePeakDbtp: tp,
      );
    } finally {
      protocol?.shutdown();
      await client.destroy();
      await protocol?.dispose();
    }
  }
}
