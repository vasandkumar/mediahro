import 'package:flutter_test/flutter_test.dart';
import 'package:mediahro_engine/mediahro_engine.dart';
import 'package:mediahro_engine/testing.dart';

/// ADR-045: PlaybackEngine.audioRouteChanged (AUD-043 DoP safety).
void main() {
  group('AUD-043 audio route changes (ADR-045)', () {
    int routeCalls(FakePlaybackEngine c) =>
        c.calls.where((x) => x == 'audioRouteChanged').length;

    test(
      'AUD-043 the crossfader forwards a route change to both cores',
      () async {
        final cores = <FakePlaybackEngine>[];
        final e = CrossfadingEngine(() {
          final c = FakePlaybackEngine(
            role: EngineRole.music,
            mediaDuration: const Duration(seconds: 10),
          );
          cores.add(c);
          return c;
        }, fadeStep: const Duration(milliseconds: 1));
        addTearDown(e.dispose);
        await e.setTransition(
          const TransitionConfig(naturalEnd: Duration(seconds: 2)),
        );
        await e.open(UriSource(Uri.parse('https://example.test/a.flac')));
        await e.setNext(UriSource(Uri.parse('https://example.test/b.flac')));
        expect(cores, hasLength(2));

        await e.audioRouteChanged();
        expect(cores.map(routeCalls), [1, 1]);
        await e.audioRouteChanged();
        expect(cores.map(routeCalls), [2, 2]);
      },
    );

    test('AUD-043 the crossfader forwards with a single core too', () async {
      final cores = <FakePlaybackEngine>[];
      final e = CrossfadingEngine(() {
        final c = FakePlaybackEngine(role: EngineRole.music);
        cores.add(c);
        return c;
      });
      addTearDown(e.dispose);
      await e.audioRouteChanged();
      expect(cores.map(routeCalls), [1]);
    });

    test('AUD-043 the fake engine records route changes', () async {
      final f = FakePlaybackEngine();
      addTearDown(f.dispose);
      await f.audioRouteChanged();
      expect(routeCalls(f), 1);
    });

    test('AUD-043 MpvEngine overrides the interface method publicly', () {
      // Compiles only when the method is public and part of PlaybackEngine.
      Future<void> route(PlaybackEngine e) => e.audioRouteChanged();
      Future<void> routeMpv(MpvEngine e) => e.audioRouteChanged();
      expect(route, isA<Function>());
      expect(routeMpv, isA<Function>());
    });
  });
}
