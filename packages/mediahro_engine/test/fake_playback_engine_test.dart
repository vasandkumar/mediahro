import 'package:flutter_test/flutter_test.dart';
import 'package:mediahro_engine/mediahro_engine.dart';
import 'package:mediahro_engine/testing.dart';

void main() {
  late FakePlaybackEngine engine;
  final src = UriSource(Uri.parse('https://example.test/film.mkv'));

  setUp(() => engine = FakePlaybackEngine());
  tearDown(() => engine.dispose());

  test('state stream replays the current snapshot to new listeners', () async {
    await engine.open(src);
    final first = await engine.state.first;
    expect(first.status, PlaybackStatus.playing);
    expect(first.duration, engine.mediaDuration);
  });

  test('seek clamps to the media bounds and relative seeks add', () async {
    await engine.open(
      src,
      opts: const OpenOptions(start: Duration(minutes: 1)),
    );
    await engine.seek(const Duration(seconds: 10), mode: SeekMode.relative);
    expect(engine.current.position, const Duration(minutes: 1, seconds: 10));
    await engine.seek(const Duration(hours: 9));
    expect(engine.current.position, engine.mediaDuration);
  });

  test('VID-062 rate outside 0.25–4.0 is rejected', () async {
    await engine.open(src);
    await engine.setRate(2);
    expect(engine.current.rate, 2);
    expect(() => engine.setRate(5), throwsA(isA<EngineException>()));
  });

  test('VID-068 audio-only open drops the video track', () async {
    await engine.open(src, opts: const OpenOptions(audioOnly: true));
    expect(
      engine.current.tracks.any((t) => t.type == TrackType.video),
      isFalse,
    );
    expect(engine.current.videoTrackId, isNull);
  });

  test('SUB-016 secondary subtitle slot is independent', () async {
    await engine.open(src);
    await engine.selectTrack(TrackType.subtitle, 1);
    await engine.selectTrack(
      TrackType.subtitle,
      2,
      slot: SubtitleSlot.secondary,
    );
    expect(engine.current.subtitleTrackId, 1);
    expect(engine.current.secondarySubtitleTrackId, 2);
  });

  test('CORE-011 engine faults surface as state, not exceptions', () async {
    await engine.open(src);
    engine.fail(EngineErrorCode.decodeFailed);
    expect(engine.current.status, PlaybackStatus.error);
    expect(engine.current.error?.code, EngineErrorCode.decodeFailed);
  });

  test('playback ends at duration when time advances', () async {
    await engine.open(
      src,
      opts: const OpenOptions(start: Duration(minutes: 89)),
    );
    engine.advance(const Duration(minutes: 2));
    expect(engine.current.status, PlaybackStatus.ended);
  });
}
