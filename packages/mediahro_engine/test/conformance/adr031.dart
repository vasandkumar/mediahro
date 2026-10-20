import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mediahro_engine/mediahro_engine.dart';

import 'support.dart';

/// ADR-031 on real libmpv: the primary subtitle line as text (SUB-040,
/// SUB-053) and embedded text tracks extracted to files (SUB-030, SUB-050,
/// SUB-053).
void adr031Suite() {
  final skip = ffiSkipReason;
  prepareCorpus();

  Future<String> extract(
    PlaybackEngine e,
    int track,
    String ext,
    Directory dir,
  ) async {
    final out = File('${dir.path}${Platform.pathSeparator}t$track$ext');
    await e.extractSubtitles(track, out.uri);
    return out.readAsStringSync().replaceAll('\r\n', '\n');
  }

  Future<(MpvEngine, Directory)> opened(String name) async {
    final e = headlessEngine();
    addTearDown(e.dispose);
    final dir = await Directory.systemTemp.createTemp('mh-subx');
    addTearDown(() => dir.delete(recursive: true));
    await e.open(UriSource(Uri.file(corpusPath(name))));
    await waitFor(e, (s) => s.tracks.isNotEmpty, reason: 'tracks');
    return (e, dir);
  }

  group('ADR-031 subtitle text', () {
    test(
      'SUB-040 subtitleText follows the primary text track',
      () async {
        final (e, _) = await opened('mkv_multitrack.mkv');
        await e.selectTrack(TrackType.subtitle, 1);
        await e.seek(const Duration(seconds: 1), mode: SeekMode.exact);
        final s = await waitFor(
          e,
          (s) => s.subtitleText == 'Hello subtitle',
          reason: 'first cue as text',
        );
        expect(s.subtitleTrackId, 1);
        await e.seek(const Duration(milliseconds: 2200), mode: SeekMode.exact);
        await waitFor(e, (s) => s.subtitleText == null, reason: 'between cues');
      },
      skip: skip,
      timeout: const Timeout(Duration(minutes: 1)),
    );
  });

  group('ADR-031 extraction', () {
    test(
      'SUB-030 an embedded SRT track extracts to SRT and ASS while playing',
      () async {
        final (e, dir) = await opened('mkv_multitrack.mkv');
        await e.play();
        await waitPlaying(e);
        final srt = await extract(e, 1, '.srt', dir);
        expect(srt, contains('00:00:00,500 --> 00:00:02,000\nHello subtitle'));
        expect(srt, contains('00:00:02,500 --> 00:00:04,500\nSecond line'));
        final ass = await extract(e, 1, '.ass', dir);
        expect(ass, contains('0:00:00.50,0:00:02.00,Default,,0,0,0,,Hello'));
        final vtt = await extract(e, 1, '.vtt', dir);
        expect(vtt, contains('00:00:02.500 --> 00:00:04.500\nSecond line'));
        expect(e.current.status, isNot(PlaybackStatus.error));
      },
      skip: skip,
      timeout: const Timeout(Duration(minutes: 1)),
    );

    test(
      'SUB-053 an embedded ASS track keeps its styles; SRT gets plain text',
      () async {
        final (e, dir) = await opened('mkv_multitrack.mkv');
        final ass = await extract(e, 2, '.ass', dir);
        expect(ass, contains('Style: Top'));
        expect(
          ass,
          contains(r'0:00:00.50,0:00:04.50,Default,,0,0,0,,{\k50}Ka'),
        );
        final srt = await extract(e, 2, '.srt', dir);
        expect(srt, contains('00:00:00,500 --> 00:00:04,500\nKaraoke'));
        expect(srt, contains('Moving sign'));
      },
      skip: skip,
      timeout: const Timeout(Duration(minutes: 1)),
    );

    test(
      'SUB-030 MP4 timed text (mov_text) extracts without its decoder',
      () async {
        final (e, dir) = await opened('mp4_movtext.mp4');
        final srt = await extract(e, 1, '.srt', dir);
        expect(srt, contains('00:00:00,500 --> 00:00:02,000\nHello subtitle'));
        expect(srt, contains('00:00:02,500 --> 00:00:04,500\nSecond line'));
        expect(srt.split('-->'), hasLength(3), reason: 'no empty gap cues');
      },
      skip: skip,
      timeout: const Timeout(Duration(minutes: 1)),
    );

    test(
      'SUB-051 bitmap tracks and bad requests are refused',
      () async {
        final (e, dir) = await opened('mkv_vobsub.mkv');
        Future<void> attempt(int id, String ext) => e.extractSubtitles(
          id,
          File('${dir.path}${Platform.pathSeparator}x$ext').uri,
        );
        await expectLater(
          attempt(1, '.srt'),
          throwsA(
            isA<EngineException>().having(
              (x) => x.error.code,
              'code',
              EngineErrorCode.notSupported,
            ),
          ),
        );
        await expectLater(attempt(9, '.srt'), throwsA(isA<EngineException>()));
      },
      skip: skip,
      timeout: const Timeout(Duration(minutes: 1)),
    );
  });
}
