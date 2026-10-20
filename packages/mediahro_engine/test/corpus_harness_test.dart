@Tags(['ffi'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mediahro_engine/mediahro_engine.dart';

import 'conformance/support.dart';

/// Media corpus harness (docs/11 §1), driven by `tools/corpus/run.dart`:
/// every corpus file opens, renders its first frame within 500 ms, reports
/// no decode error, seeks to 10 points and plays up to 10 s with at most
/// 1 % dropped frames. Writes a JSON report to `MEDIAHRO_CORPUS_REPORT`.
void main() {
  final reportPath = Platform.environment['MEDIAHRO_CORPUS_REPORT'];
  final skip = reportPath == null
      ? 'run through tools/corpus/run.dart'
      : ffiSkipReason;
  final results = <Map<String, Object?>>[];

  tearDownAll(() {
    if (reportPath == null) return;
    File(reportPath)
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(
        const JsonEncoder.withIndent('  ').convert({
          'platform': Platform.operatingSystem,
          'generated': DateTime.now().toUtc().toIso8601String(),
          'files': results,
          'passed': results.where((r) => r['ok'] == true).length,
          'failed': results.where((r) => r['ok'] != true).length,
        }),
      );
  });

  // Playable media files; broken inputs, discs and playlists have their
  // own conformance tests.
  bool media(CorpusItem i) {
    if (i.expect['error'] != null || i.expect['truncated'] != null) {
      return false;
    }
    if (i.category == 'disc' || i.category == 'playlists') return false;
    return (i.expect['video'] as int? ?? 0) > 0 ||
        (i.expect['audio'] as int? ?? 0) > 0;
  }

  final items = corpusItems().where(media);

  for (final item in items) {
    test(
      'corpus ${item.file}',
      () async {
        final r = <String, Object?>{'file': item.file, 'ok': false};
        results.add(r);
        final hasVideo = (item.expect['video'] as int? ?? 0) > 0;
        final e = headlessEngine(
          role: hasVideo ? EngineRole.video : EngineRole.music,
        );
        addTearDown(e.dispose);
        // Create the core first so the measurement is open → first frame.
        await e.setVolume(1);
        e.softwareRenderer?.restartClock();
        final sw = Stopwatch()..start();
        await e.open(UriSource(item.uri));
        if (hasVideo) {
          final first = await e.softwareRenderer!.firstFrame.timeout(
            const Duration(seconds: 10),
          );
          r['firstFrameMs'] = first.inMilliseconds;
        }
        final s = await waitPlaying(e, reason: item.file);
        r['openMs'] = sw.elapsedMilliseconds;
        expect(s.error, isNull, reason: '${item.file}: ${s.error}');
        if (item.expect['hdr'] case final String hdr) {
          final h = await waitFor(e, (s) => s.video.hdr != HdrType.sdr);
          r['hdr'] = h.video.hdr.name;
          expect(h.video.hdr.name, hdr);
        }
        final duration = s.duration ?? Duration.zero;
        var seeks = 0;
        if (duration > const Duration(seconds: 1)) {
          for (var i = 0; i < 10; i++) {
            final target = duration * (i / 10);
            await e.seek(target, mode: SeekMode.exact);
            await waitFor(
              e,
              (s) =>
                  (s.position - target).inMilliseconds.abs() < 100 ||
                  s.status == PlaybackStatus.ended,
              reason: 'seek $i',
            );
            seeks++;
          }
          await e.seek(Duration.zero);
        }
        r['seeks'] = seeks;
        final playFor = duration < const Duration(seconds: 10)
            ? duration
            : const Duration(seconds: 10);
        final end = await waitFor(
          e,
          (s) =>
              s.status == PlaybackStatus.ended ||
              s.error != null ||
              s.position >= playFor - const Duration(milliseconds: 100),
          timeout: playFor + const Duration(seconds: 10),
          reason: 'plays',
        );
        expect(end.error, isNull);
        if (hasVideo) {
          final fps = end.video.fps ?? 25;
          final frames = (playFor.inMilliseconds / 1000 * fps).round();
          r['droppedFrames'] = end.video.droppedFrames;
          r['frames'] = frames;
          expect(
            end.video.droppedFrames,
            lessThanOrEqualTo((frames * 0.01).ceil()),
            reason: 'drops > 1 %',
          );
          expect(
            r['firstFrameMs']! as int,
            lessThanOrEqualTo(500),
            reason: 'first frame budget (docs/11 §1)',
          );
        }
        r['ok'] = true;
      },
      skip: skip,
      timeout: const Timeout(Duration(minutes: 2)),
    );
  }
}
