import 'dart:isolate';
import 'dart:typed_data';

import 'package:mediahro/features/music/library/music_files.dart';
import 'package:mediahro/features/music/library/music_library.dart';
import 'package:mediahro_engine/mediahro_engine.dart';
import 'package:mediahro_ffi/mediahro_ffi.dart';
import 'package:meta/meta.dart';

/// Seconds of audio AcoustID needs to recognise a song.
const fingerprintSeconds = 120;

/// Chromaprint's own analysis rate; decoding straight to it avoids a second
/// resample.
const fingerprintRate = 11025;

/// Less than this cannot be recognised.
const minFingerprintSeconds = 3;

/// A Chromaprint fingerprint in AcoustID's compressed form, with the length
/// of the song in seconds (AcoustID wants both).
@immutable
final class AudioFingerprint {
  const AudioFingerprint(this.encoded, this.durationSeconds);

  final String encoded;
  final int durationSeconds;
}

enum FingerprintFailure { tooShort, noAudio }

final class FingerprintException implements Exception {
  const FingerprintException(this.reason);

  final FingerprintFailure reason;

  @override
  String toString() => 'FingerprintException($reason)';
}

/// Computes the encoded fingerprint of mono 16-bit PCM. The default runs
/// Chromaprint (B2's binding, LGPL, dynamically linked) on a worker isolate,
/// because the call blocks.
typedef FingerprintCompute = Future<String> Function(
  Int16List pcm,
  int sampleRate,
);

Future<String> chromaprintCompute(Int16List pcm, int sampleRate) =>
    Isolate.run(() {
      final fp = Fingerprinter();
      try {
        fp
          ..start(sampleRate, 1)
          ..feed(pcm)
          ..finish();
        return fp.encoded();
      } finally {
        fp.dispose();
      }
    });

/// Fingerprints a library song (MUS-010): the engine decodes its first two
/// minutes to PCM (ADR-032, independent of what is playing), Chromaprint
/// turns that into a fingerprint. Nothing leaves the device here.
final class TrackFingerprinter {
  TrackFingerprinter({
    required this.engine,
    required this.files,
    this.compute = chromaprintCompute,
  });

  final PlaybackEngine engine;
  final MusicFiles files;
  final FingerprintCompute compute;

  Future<AudioFingerprint> of(MusicTrack t) async {
    final source = await files.mediaSource(
      t.sourceId,
      t.relPath,
      title: t.title,
    );
    const cap = fingerprintRate * fingerprintSeconds;
    final pcm = Int16List(cap);
    var n = 0;
    // Leaving the loop cancels the subscription, which stops decoding.
    await for (final chunk in engine.decodeAudio(
      source,
      sampleRate: fingerprintRate,
      end: const Duration(seconds: fingerprintSeconds),
    )) {
      for (var i = 0; i < chunk.length && n < cap; i++) {
        pcm[n++] = (chunk[i].clamp(-1.0, 1.0) * 32767).round();
      }
      if (n >= cap) break;
    }
    if (n == 0) throw const FingerprintException(FingerprintFailure.noAudio);
    if (n < fingerprintRate * minFingerprintSeconds) {
      throw const FingerprintException(FingerprintFailure.tooShort);
    }
    final decoded = Int16List.sublistView(pcm, 0, n);
    final encoded = await compute(decoded, fingerprintRate);
    // The song's real length when the library knows it; otherwise what was
    // decoded (a song shorter than two minutes decodes completely).
    final seconds = t.duration?.inSeconds ?? (n / fingerprintRate).round();
    return AudioFingerprint(encoded, seconds);
  }
}
