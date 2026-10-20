import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mediahro_engine/mediahro_engine.dart';
import 'package:mediahro_engine/src/mpv/state_mapping.dart';
import 'package:mediahro_engine/testing.dart';

/// ADR-031 without libmpv: the primary line as text (SUB-040, SUB-053) and
/// track extraction through the doubles (SUB-030).
void main() {
  group('ADR-031 subtitle text', () {
    test('SUB-040 sub-text maps to subtitleText; empty is null', () {
      var s = applyProperty(const PlaybackState(), 'sub-text', 'Hello');
      expect(s.subtitleText, 'Hello');
      s = applyProperty(s, 'sub-text', '');
      expect(s.subtitleText, isNull);
      expect(observedProperties, contains('sub-text'));
    });

    test('SUB-053 the fake engine reports a subtitle line', () async {
      final e = FakePlaybackEngine();
      addTearDown(e.dispose);
      e.setSubtitleText('Bonjour');
      expect(e.current.subtitleText, 'Bonjour');
      e.setSubtitleText(null);
      expect(e.current.subtitleText, isNull);
    });
  });

  group('ADR-031 extraction doubles', () {
    late Directory dir;
    setUp(() async {
      dir = await Directory.systemTemp.createTemp('mh-subx-unit');
    });
    tearDown(() => dir.delete(recursive: true));

    test(
      'SUB-030 the fake writes its text; bitmap tracks are refused',
      () async {
        final e = FakePlaybackEngine(
          mediaTracks: const [
            Track(id: 1, type: TrackType.subtitle, codec: 'subrip'),
            Track(id: 2, type: TrackType.subtitle, codec: 'hdmv_pgs_subtitle'),
          ],
        );
        addTearDown(e.dispose);
        await e.open(UriSource(Uri.parse('https://example.test/film.mkv')));
        final out = File('${dir.path}${Platform.pathSeparator}a.srt');
        await e.extractSubtitles(1, out.uri);
        expect(out.readAsStringSync(), contains('Hello'));
        await expectLater(
          e.extractSubtitles(2, out.uri),
          throwsA(
            isA<EngineException>().having(
              (x) => x.error.code,
              'code',
              EngineErrorCode.notSupported,
            ),
          ),
        );
        await expectLater(
          e.extractSubtitles(7, out.uri),
          throwsA(isA<EngineException>()),
        );
      },
    );

    test('SUB-050 the crossfader extracts through its core', () async {
      final e = CrossfadingEngine(
        () => FakePlaybackEngine(
          role: EngineRole.music,
          mediaTracks: const [
            Track(id: 1, type: TrackType.subtitle, codec: 'ass'),
          ],
        )..extractedSubtitles = 'lyrics',
      );
      addTearDown(e.dispose);
      await e.open(UriSource(Uri.parse('https://example.test/a.mka')));
      final out = File('${dir.path}${Platform.pathSeparator}b.ass');
      await e.extractSubtitles(1, out.uri);
      expect(out.readAsStringSync(), 'lyrics');
    });
  });
}
