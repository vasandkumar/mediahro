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

  group('ADR-031 image extraction', () {
    for (final (file, codec) in [
      ('mkv_pgs.mkv', 'hdmv_pgs_subtitle'),
      ('mkv_vobsub.mkv', 'dvd_subtitle'),
      ('ts_dvbsub.ts', 'dvb_subtitle'),
    ]) {
      test(
        'SUB-051 $codec bitmaps come out with their times and place',
        () async {
          final (e, _) = await opened(file);
          final track = e.current.tracks.firstWhere(
            (t) => t.type == TrackType.subtitle,
          );
          expect(track.codec, codec);
          final images = await e.extractSubtitleImages(track.id).toList();
          // The corpus subtitle: a white bar of 64×16 at 288,300 in a
          // 640×360 frame. The muxed files start their subtitle stream at 0
          // (PGS shows it for 1.5 s; DVB for its page timeout or until the
          // clear).
          expect(images, hasLength(1));
          final i = images.single;
          expect(i.start.inMilliseconds, inInclusiveRange(0, 200));
          expect(i.end, greaterThan(i.start));
          expect(i.end, lessThan(const Duration(seconds: 10)));
          if (codec == 'hdmv_pgs_subtitle') {
            expect((i.end - i.start).inMilliseconds, closeTo(1500, 100));
          }
          expect(i.width, inInclusiveRange(40, 90));
          expect(i.height, inInclusiveRange(8, 30));
          expect(i.x, inInclusiveRange(270, 310));
          expect(i.y, inInclusiveRange(285, 315));
          expect(i.rgba.length, i.width * i.height * 4);
          var lit = 0;
          for (var p = 0; p < i.rgba.length; p += 4) {
            if (i.rgba[p + 3] > 200 && i.rgba[p] > 150) lit++;
          }
          expect(lit, greaterThan(i.width * i.height ~/ 2), reason: 'white');
        },
        skip: skip,
        timeout: const Timeout(Duration(minutes: 1)),
      );
    }

    // The rich corpus bitmap (tools/corpus/generate.dart _richIndex).
    int richIndex(int x, int y) {
      if (x < 2 || y < 2 || x >= 94 || y >= 22) return 4;
      if (y >= 18) return x < 60 ? 1 : 0;
      final stroke = (x % 8 < 5 && y % 6 < 4) || (x + y) % 11 == 0;
      if (!stroke) return y < 6 ? 4 : 0;
      return 1 + (x ~/ 16) % 3;
    }

    const richColours = [
      [0, 0, 0, 0],
      [255, 255, 255, 255],
      [255, 0, 0, 255],
      [255, 255, 0, 255],
      [0, 0, 0, 128],
    ];

    for (final (file, codec, exact) in [
      ('mkv_pgs_rich.mkv', 'hdmv_pgs_subtitle', true),
      ('mkv_vobsub_rich.mkv', 'dvd_subtitle', false),
      ('ts_dvbsub_rich.ts', 'dvb_subtitle', false),
    ]) {
      test(
        'SUB-051 $codec decodes a multi-colour bitmap like its source',
        () async {
          final (e, _) = await opened(file);
          final track = e.current.tracks.firstWhere(
            (t) => t.type == TrackType.subtitle,
          );
          final images = await e.extractSubtitleImages(track.id).toList();
          expect(images, hasLength(1));
          final i = images.single;
          expect((i.x, i.y, i.width, i.height), (100, 280, 96, 24));
          expect((i.frameWidth, i.frameHeight), (640, 360));
          // Exactly for PGS, which is stored as it was written. The
          // encoders of the others quantise colours, so they must agree on
          // which pixels show anything and on the opaque white and red.
          var shapeWrong = 0;
          var colourWrong = 0;
          for (var y = 0; y < 24; y++) {
            for (var x = 0; x < 96; x++) {
              final want = richColours[richIndex(x, y)];
              final at = (y * 96 + x) * 4;
              final got = i.rgba.sublist(at, at + 4);
              final shown = got[3] > 0;
              if (shown != (want[3] > 0)) shapeWrong++;
              if (exact) {
                for (var k = 0; k < 4; k++) {
                  if ((got[k] - want[k]).abs() > 3) {
                    colourWrong++;
                    break;
                  }
                }
              } else if (want[3] == 255 && shown && got[3] == 255) {
                if (want[1] == 255 && want[2] == 255 && got[0] < 200) {
                  colourWrong++;
                }
              }
            }
          }
          expect(shapeWrong, exact ? 0 : lessThan(96 * 24 ~/ 20));
          expect(colourWrong, exact ? 0 : lessThan(96 * 24 ~/ 20));
        },
        skip: skip,
        timeout: const Timeout(Duration(minutes: 1)),
      );
    }

    test(
      'SUB-051 text tracks and bad requests are refused on the stream',
      () async {
        final (e, _) = await opened('mkv_multitrack.mkv');
        await expectLater(
          e.extractSubtitleImages(1).toList(),
          throwsA(
            isA<EngineException>().having(
              (x) => x.error.code,
              'code',
              EngineErrorCode.notSupported,
            ),
          ),
        );
        await expectLater(
          e.extractSubtitleImages(9).toList(),
          throwsA(isA<EngineException>()),
        );
      },
      skip: skip,
      timeout: const Timeout(Duration(minutes: 1)),
    );
  });

  group('PRIV-007 protected media', () {
    test(
      'PRIV-007 a sensitive source is never extracted, exported or captured',
      () async {
        final e = headlessEngine();
        addTearDown(e.dispose);
        final dir = await Directory.systemTemp.createTemp('mh-priv');
        addTearDown(() => dir.delete(recursive: true));
        await e.open(
          UriSource(
            Uri.file(corpusPath('mkv_multitrack.mkv')),
            sensitive: true,
          ),
        );
        await waitFor(e, (s) => s.tracks.isNotEmpty, reason: 'tracks');
        Matcher refused() => throwsA(
          isA<EngineException>().having(
            (x) => x.error.code,
            'code',
            EngineErrorCode.notSupported,
          ),
        );
        final out = Uri.file('${dir.path}${Platform.pathSeparator}x.srt');
        await expectLater(e.extractSubtitles(1, out), refused());
        await expectLater(e.extractSubtitleImages(1).toList(), refused());
        await expectLater(e.screenshot(), refused());
        await expectLater(
          e.export(
            Duration.zero,
            const Duration(seconds: 1),
            ExportFormat.clipCopy,
            Uri.file('${dir.path}${Platform.pathSeparator}c.mkv'),
          ),
          refused(),
        );
        expect(dir.listSync(), isEmpty, reason: 'nothing was written');
        // Playback itself is unaffected.
        await e.play();
        await waitPlaying(e);
      },
      skip: skip,
      timeout: const Timeout(Duration(minutes: 1)),
    );

    test(
      'PRIV-007 a sensitive source gets no converted subtitle copy on disk',
      () async {
        // External subtitles in a format mpv does not read are converted to
        // an SRT file; for protected media that copy would be plaintext.
        Future<List<String>> subsFolders({required bool sensitive}) async {
          final e = headlessEngine();
          addTearDown(e.dispose);
          await e.open(
            UriSource(
              Uri.file(corpusPath('mkv_multitrack.mkv')),
              sensitive: sensitive,
            ),
          );
          await waitFor(e, (s) => s.tracks.isNotEmpty, reason: 'tracks');
          try {
            await e.addExternalTrack(
              TrackType.subtitle,
              Uri.file(corpusPath('subs.ttml')),
            );
          } on EngineException {
            // Not converted, so mpv cannot read it: the safe outcome for a
            // protected item.
            expect(sensitive, isTrue, reason: 'only a protected item fails');
          }
          final parent = Directory(
            '${Directory.systemTemp.path}${Platform.pathSeparator}'
            'mediahro-scratch',
          );
          return [
            if (parent.existsSync())
              for (final d in parent.listSync().whereType<Directory>())
                if (d.uri.pathSegments
                    .where((s) => s.isNotEmpty)
                    .last
                    .startsWith('subs-'))
                  d.path,
          ];
        }

        expect(
          await subsFolders(sensitive: true),
          isEmpty,
          reason: 'protected',
        );
        expect(
          await subsFolders(sensitive: false),
          isNotEmpty,
          reason: 'ordinary item',
        );
      },
      skip: skip,
      timeout: const Timeout(Duration(minutes: 1)),
    );
  });
}
