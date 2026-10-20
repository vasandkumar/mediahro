import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mediahro/features/video/player/play_request.dart';
import 'package:mediahro/features/video/player/video_memory.dart';
import 'package:mediahro/features/video/player/video_player_controller.dart';
import 'package:mediahro/features/video/subtitles/audio_sync.dart';
import 'package:mediahro_engine/mediahro_engine.dart';
import 'package:mediahro_subtitles/mediahro_subtitles.dart';

import '../../../integration_test/support/c1_audio.dart';
import '../../../integration_test/support/c1_engine.dart';
import '../../helpers.dart';

void main() {
  const seconds = 90;
  final turns = speechTurns(seconds);
  final source = UriSource(Uri.parse('file:///v/film.mkv'));

  SubtitleDocument doc({double shift = 0}) =>
      const SrtParser().parse(turnsSrt(turns, shift: shift));

  group('SUB-050 auto-sync in the player', () {
    test('SUB-050 decodes, detects speech and finds the offset', () async {
      final run = await AudioSyncRun.start(
        pcm: fakePcm(turns, seconds: seconds),
        source: source,
        doc: doc(shift: 2.4),
        duration: const Duration(seconds: seconds),
      );
      final progress = <double?>[];
      run.addListener(() => progress.add(run.progress));
      final r = await run.result;
      expect(r.offset.inMilliseconds, closeTo(-2400, 30));
      expect(r.factor, 1);
      expect(r.confident, isTrue);
      expect(progress.last, closeTo(1, 0.02));
    });

    test('SUB-050 can be cancelled', () async {
      final ctl = StreamController<(Duration, Float32List)>();
      final run = await AudioSyncRun.start(
        pcm: (_) => ctl.stream,
        source: source,
        doc: doc(),
      );
      await run.cancel();
      await expectLater(run.result, throwsA(isA<SyncCancelled>()));
      await ctl.close();
    });

    test('SUB-050 decoding errors end the run', () async {
      final run = await AudioSyncRun.start(
        pcm: (_) => Stream.error(
          const EngineException(
            EngineError(code: EngineErrorCode.unsupportedFormat),
          ),
        ),
        source: source,
        doc: doc(),
      );
      await expectLater(run.result, throwsA(isA<EngineException>()));
    });

    test('SUB-050 preview applies as delay and speed; undo restores', () async {
      final engine = RecordingEngine();
      final c = VideoPlayerController(
        engine: engine,
        memory: await VideoMemory.open(MemoryVideoMemoryPersistence()),
        settings: await memoryStore(),
      );
      addTearDown(() async {
        c.dispose();
        await engine.dispose();
      });
      await c.open(PlayRequest(source: source, title: 'f', memoryKey: 'f'));
      await c.setSubtitleDelay(const Duration(milliseconds: 500));
      final preview = await SyncPreview.apply(
        c,
        const SyncResult(
          offset: Duration(milliseconds: -2400),
          factor: 25 / 23.976,
          score: 0.8,
          confidence: 0.6,
        ),
      );
      expect(engine.subDelays.last.$1, const Duration(milliseconds: -2400));
      expect(engine.fake.subSpeed, closeTo(25 / 23.976, 1e-9));
      expect(c.subtitleSpeed, closeTo(25 / 23.976, 1e-9), reason: 'kept');
      await preview.undo(c);
      expect(engine.subDelays.last.$1, const Duration(milliseconds: 500));
      expect(engine.fake.subSpeed, 1);
    });
  });
}
