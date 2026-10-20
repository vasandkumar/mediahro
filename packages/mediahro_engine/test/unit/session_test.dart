import 'package:flutter_test/flutter_test.dart';
import 'package:mediahro_engine/mediahro_engine.dart';
import 'package:mediahro_engine/testing.dart';

void main() {
  final src = UriSource(Uri.parse('https://example.test/a.mkv'));

  group('CORE-011 auto-save of playback position', () {
    test('CORE-011 a checkpoint every 5 s while playing', () async {
      var now = DateTime(2026);
      final engine = FakePlaybackEngine();
      final cp = PlaybackCheckpointer(engine, clock: () => now);
      final got = <PlaybackCheckpoint>[];
      cp.checkpoints.listen(got.add);
      await engine.open(src);
      await pumpEventQueue();
      for (var i = 0; i < 12; i++) {
        now = now.add(const Duration(seconds: 1));
        engine.advance(const Duration(seconds: 1));
        await pumpEventQueue();
      }
      // First save on start, then at 5 s and 10 s of wall time.
      expect(got.length, 3);
      expect(got.last.position, const Duration(seconds: 10));
      await cp.dispose();
      await engine.dispose();
    });

    test('CORE-011 pause, faults and item changes save immediately', () async {
      final engine = FakePlaybackEngine();
      final cp = PlaybackCheckpointer(engine);
      final got = <PlaybackCheckpoint>[];
      cp.checkpoints.listen(got.add);
      await engine.open(src);
      engine.advance(const Duration(seconds: 42));
      await pumpEventQueue();
      await engine.pause();
      await pumpEventQueue();
      expect(got.last.position, const Duration(seconds: 42));
      await engine.play();
      engine
        ..advance(const Duration(seconds: 3))
        ..fail(EngineErrorCode.engineCrashed);
      await pumpEventQueue();
      expect(got.last.position, const Duration(seconds: 45));
      await cp.dispose();
      await engine.dispose();
    });

    test('CORE-011 the end of an item is marked finished', () async {
      final engine = FakePlaybackEngine(
        mediaDuration: const Duration(seconds: 3),
      );
      final cp = PlaybackCheckpointer(engine);
      final got = <PlaybackCheckpoint>[];
      cp.checkpoints.listen(got.add);
      await engine.open(src);
      engine.advance(const Duration(seconds: 5));
      await pumpEventQueue();
      expect(got.last.finished, isTrue);
      await cp.dispose();
      await engine.dispose();
    });
  });

  group('AUD-003 crossfade logic', () {
    late List<FakePlaybackEngine> cores;
    late CrossfadingEngine e;

    setUp(() {
      cores = [];
      e = CrossfadingEngine(() {
        final c = FakePlaybackEngine(
          role: EngineRole.music,
          mediaDuration: const Duration(seconds: 10),
        );
        cores.add(c);
        return c;
      }, fadeStep: const Duration(milliseconds: 1));
    });
    tearDown(() => e.dispose());

    test(
      'AUD-003 natural end starts the next item on the standby core',
      () async {
        await e.setTransition(
          const TransitionConfig(naturalEnd: Duration(seconds: 2)),
        );
        await e.open(src);
        await e.setNext(UriSource(Uri.parse('https://example.test/b.flac')));
        expect(cores, hasLength(2));
        expect(cores[1].calls, contains('open'));
        expect(e.current.nextPrepared, isTrue);
        cores[0].advance(const Duration(seconds: 8, milliseconds: 100));
        await e.state
            .firstWhere((s) => s.item == 2)
            .timeout(const Duration(seconds: 5));
        expect(cores[1].calls, contains('play'));
        expect(cores[0].calls, contains('stop'));
        expect(e.current.item, 2);
      },
    );

    test('AUD-003 fades are capped at 12 s', () async {
      await e.setTransition(
        const TransitionConfig(naturalEnd: Duration(seconds: 30)),
      );
      await e.open(src);
      await e.setNext(UriSource(Uri.parse('https://example.test/b.flac')));
      cores[0].advance(const Duration(seconds: 1));
      await pumpEventQueue();
      expect(e.fading, isFalse, reason: 'not before duration − 12 s');
    });

    test(
      'AUD-003 same-album transitions stay gapless unless opted in',
      () async {
        await e.setTransition(
          const TransitionConfig(naturalEnd: Duration(seconds: 2)),
        );
        await e.open(src);
        await e.setNext(
          UriSource(Uri.parse('https://example.test/b.flac')),
          sameAlbum: true,
        );
        expect(cores, hasLength(1), reason: 'no standby core needed');
        expect(cores[0].calls, contains('setNext'));
        await e.setTransition(
          const TransitionConfig(
            naturalEnd: Duration(seconds: 2),
            crossfadeGaplessAlbums: true,
          ),
        );
        expect(cores, hasLength(2), reason: 'opt-in crossfades the album');
      },
    );

    test('AUD-003 volume applies to the active core outside fades', () async {
      await e.open(src);
      await e.setVolume(0.5);
      expect(cores[0].current.volume, 0.5);
      expect(e.current.volume, 0.5);
    });
  });
}
