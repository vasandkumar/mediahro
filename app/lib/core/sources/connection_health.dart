import 'package:mediahro/platform/network_status.dart';
import 'package:mediahro_ffi/mediahro_ffi.dart';
import 'package:meta/meta.dart';

enum HealthWarning {
  /// Metered connection (mobile data, hotspot): streaming costs data.
  metered,

  /// Too slow for HD (about 8 Mbit/s).
  slowForHd,

  /// Too slow for 4K remuxes (about 50 Mbit/s).
  slowFor4k,

  /// Round trips above 150 ms make seeking sluggish.
  highLatency,
}

@immutable
final class HealthReport {
  const HealthReport({
    required this.latency,
    required this.throughputMbps,
    required this.suggestedCacheMiB,
    required this.suggestedReadAheadSeconds,
    required this.warnings,
    this.sampledBytes = 0,
  });

  /// Median round trip of a metadata request.
  final Duration latency;

  /// Sequential read speed in Mbit/s (null when no file was sampled).
  final double? throughputMbps;

  /// Suggested demuxer cache (feeds `demuxer-max-bytes`, VID-006).
  final int suggestedCacheMiB;
  final int suggestedReadAheadSeconds;
  final Set<HealthWarning> warnings;
  final int sampledBytes;
}

/// Latency/throughput test per source with cache sizing suggestion and
/// metered-network warnings (NET-019).
final class ConnectionHealth {
  ConnectionHealth({this.network, Stopwatch Function()? stopwatch})
    : _sw = stopwatch ?? Stopwatch.new;

  final NetworkStatusFacade? network;
  final Stopwatch Function() _sw;

  Future<HealthReport> test(
    VirtualFileSystem fs,
    Uri root, {
    Uri? sample,
    int pings = 5,
    int sampleBytes = 8 << 20,
  }) async {
    final rtts = <int>[];
    for (var i = 0; i < pings; i++) {
      final sw = _sw()..start();
      await fs.stat(root);
      rtts.add(sw.elapsedMicroseconds);
    }
    rtts.sort();
    final latency = Duration(microseconds: rtts[rtts.length ~/ 2]);

    double? mbps;
    var read = 0;
    final target = sample ?? await _largestFile(fs, root);
    if (target != null) {
      final f = await fs.open(target);
      try {
        final sw = _sw()..start();
        while (read < sampleBytes) {
          final chunk = await f.read(read, 1 << 20);
          if (chunk.isEmpty) break;
          read += chunk.length;
        }
        final secs = sw.elapsedMicroseconds / 1e6;
        if (read > 0 && secs > 0) mbps = read * 8 / secs / 1e6;
      } finally {
        await f.close();
      }
    }

    final warnings = <HealthWarning>{
      if ((await network?.current())?.metered ?? false) HealthWarning.metered,
      if (latency > const Duration(milliseconds: 150))
        HealthWarning.highLatency,
      if (mbps != null && mbps < 8) HealthWarning.slowForHd,
      if (mbps != null && mbps < 50) HealthWarning.slowFor4k,
    };
    final (cache, ahead) = suggestCache(mbps, latency);
    return HealthReport(
      latency: latency,
      throughputMbps: mbps,
      suggestedCacheMiB: cache,
      suggestedReadAheadSeconds: ahead,
      warnings: warnings,
      sampledBytes: read,
    );
  }

  /// Cache sizing: fast LANs need little; slow or jittery links buffer
  /// more seconds of a 40 Mbit/s 4K stream, capped for phones.
  static (int cacheMiB, int seconds) suggestCache(
    double? mbps,
    Duration latency,
  ) {
    if (mbps == null) return (150, 30);
    final seconds = mbps >= 200
        ? 10
        : mbps >= 80
        ? 20
        : mbps >= 40
        ? 40
        : 90;
    final extra = latency > const Duration(milliseconds: 100) ? 20 : 0;
    final s = seconds + extra;
    // 40 Mbit/s ≈ 5 MiB/s of the heaviest common stream.
    final mib = (s * 5).clamp(64, 1024);
    return (mib, s);
  }

  static Future<Uri?> _largestFile(VirtualFileSystem fs, Uri root) async {
    VirtualEntry? best;
    try {
      await for (final e in fs.list(root)) {
        if (!e.isDirectory && (e.size ?? 0) > (best?.size ?? 0)) best = e;
      }
    } on VirtualFileException {
      return null;
    }
    return best?.uri;
  }
}
