import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mediahro/features/video/player/video_player_controller.dart';
import 'package:mediahro_engine/mediahro_engine.dart';
import 'package:mediahro_subtitles/mediahro_subtitles.dart';

/// Mono float PCM of a source's audio, decoded faster than playback, with
/// the stream time of each chunk (SUB-050, SUB-052).
typedef PcmSource = Stream<(Duration, Float32List)> Function(
  MediaSource source,
);

/// Sample rate C1 asks for (VAD and whisper both use 16 kHz).
const int syncSampleRate = 16000;

/// Offline audio decode. Null until the engine exposes it (ADR request:
/// `PlaybackEngine.decodeAudio`); then `videoOverrides` points it there.
final pcmSourceProvider = Provider<PcmSource?>((ref) => null);

/// The user stopped an auto-sync run.
final class SyncCancelled implements Exception {
  const SyncCancelled();
}

/// Progress and outcome of one auto-sync run (SUB-050).
final class AudioSyncRun extends ChangeNotifier {
  AudioSyncRun._(this._sub, this._session, this._duration);

  /// Decodes [source]'s audio, detects speech and aligns [doc]. Watch
  /// [progress]; await [result]; [cancel] stops everything.
  static Future<AudioSyncRun> start({
    required PcmSource pcm,
    required MediaSource source,
    required SubtitleDocument doc,
    Duration? duration,
  }) async {
    final session = await AutoSyncSession.start(sampleRate: syncSampleRate);
    late final AudioSyncRun run;
    final sub = pcm(source).listen(
      (chunk) {
        session.add(chunk.$2);
        run
          .._position = chunk.$1
          ..notifyListeners();
      },
      onError: (Object e) {
        session.cancel();
        if (!run._done.isCompleted) run._done.completeError(e);
      },
      onDone: () async {
        try {
          final r = await session.finish(doc);
          if (!run._done.isCompleted) run._done.complete(r);
        } on Object catch (e) {
          if (!run._done.isCompleted) run._done.completeError(e);
        }
      },
    );
    return run = AudioSyncRun._(sub, session, duration);
  }

  final StreamSubscription<(Duration, Float32List)> _sub;
  final AutoSyncSession _session;
  final Duration? _duration;
  final Completer<SyncResult> _done = Completer();
  Duration _position = Duration.zero;

  /// 0…1 of the audio analysed so far (null without a duration).
  double? get progress {
    final d = _duration;
    if (d == null || d <= Duration.zero) return null;
    return (_position.inMilliseconds / d.inMilliseconds).clamp(0.0, 1.0);
  }

  Future<SyncResult> get result => _done.future;

  Future<void> cancel() async {
    await _sub.cancel();
    _session.cancel();
    if (!_done.isCompleted) _done.completeError(const SyncCancelled());
  }
}

/// A sync result previewed in the player through the per-file subtitle
/// delay and speed (SUB-050: "result previewed before save"); [undo] puts
/// the earlier values back.
final class SyncPreview {
  SyncPreview._(this.result, this._delay, this._speed);

  static Future<SyncPreview> apply(
    VideoPlayerController c,
    SyncResult result,
  ) async {
    final p = SyncPreview._(result, c.subtitleDelay, c.subtitleSpeed);
    // mpv shows a cue at t × speed + delay.
    await c.setSubtitleSpeed(result.factor);
    await c.setSubtitleDelay(result.offset);
    return p;
  }

  final SyncResult result;
  final Duration _delay;
  final double _speed;

  Future<void> undo(VideoPlayerController c) async {
    await c.setSubtitleSpeed(_speed);
    await c.setSubtitleDelay(_delay);
  }
}
