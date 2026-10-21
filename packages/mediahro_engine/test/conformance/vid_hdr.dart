import 'package:flutter_test/flutter_test.dart';
import 'package:mediahro_engine/mediahro_engine.dart';

import 'support.dart';

/// VID-030…035: renderer, HDR detection and tone mapping on the platform's
/// libmpv. Dolby Vision and HDR10+ streams come from the LFS corpus
/// (test-media/corpus) when present; the classification logic is unit
/// tested in test/unit/mapping_test.dart.
void vidHdrSuite() {
  final skip = ffiSkipReason;
  prepareCorpus();

  group('VID-031 HDR10 / HLG', () {
    for (final item in corpusItems(category: 'hdr')) {
      test(
        'VID-031 ${item.file} is detected as ${item.expect['hdr']}',
        () async {
          final e = await openItem(item.file);
          await waitPlaying(e);
          final s = await waitFor(
            e,
            (s) => s.video.hdr != HdrType.sdr,
            reason: 'HDR detected',
          );
          expect(s.video.hdr.name, item.expect['hdr']);
          final params =
              await prop(e, 'video-params') as Map<Object?, Object?>?;
          expect(params?['primaries'], 'bt.2020');
        },
        skip: skip,
      );
    }

    test('VID-031 tone mapping is applied and selectable', () async {
      final e = await openItem('mkv_ffv1_pq.mkv');
      await waitPlaying(e);
      expect(await prop(e, 'tone-mapping'), 'bt.2390');
      expect(await prop(e, 'hdr-compute-peak'), isTrue);
      for (final t in ToneMapping.values) {
        await e.setVideoFilters(VideoFilterChain(toneMapping: t));
        expect(await prop(e, 'tone-mapping'), switch (t) {
          ToneMapping.bt2390 => 'bt.2390',
          _ => t.name,
        });
      }
    }, skip: skip);

    test('VID-031 tone-mapped output is not washed out', () async {
      // A PQ stream rendered for an SDR target must keep its contrast: the
      // testsrc2 pattern has near-black and near-white regions after
      // mapping, rather than everything collapsing into mid-grey.
      final e = await openItem('mkv_ffv1_pq.mkv');
      await waitPlaying(e);
      final frame = await e.softwareRenderer!.frames.first;
      var min = 255;
      var max = 0;
      for (var y = 10; y < frame.height; y += 10) {
        for (var x = 10; x < frame.width; x += 10) {
          final (r, g, b) = frame.pixel(x, y);
          final l = (r * 299 + g * 587 + b * 114) ~/ 1000;
          if (l < min) min = l;
          if (l > max) max = l;
        }
      }
      expect(max - min, greaterThan(120), reason: 'contrast $min..$max');
    }, skip: skip);
  });

  group('VID-030 renderer', () {
    test('VID-030 video renders frames with the configured renderer', () async {
      final e = await openItem('mkv_av1_10bit.mkv');
      await waitPlaying(e);
      final frames = <int>[];
      await for (final f in e.softwareRenderer!.frames) {
        frames.add(f.index);
        if (frames.length >= 5) break;
      }
      expect(frames, hasLength(5));
      expect(await prop(e, 'vd-lavc-dr'), anyOf(isTrue, 'yes', 'auto'));
      // The info overlay (VID-072) shows the render path.
      expect(e.current.video.renderBackend, 'software');
    }, skip: skip);
  });

  group('VID-032…035 dynamic metadata and Dolby Vision', () {
    final lfs = corpusItems(category: 'hdr-lfs');
    for (final item in lfs) {
      test('${item.ids.first} ${item.file}', () async {
        final e = await openItem(item.file);
        final s = await waitPlaying(e);
        expect(s.error, isNull);
        final hdr = await waitFor(e, (s) => s.video.hdr != HdrType.sdr);
        expect(hdr.video.hdr.name, item.expect['hdr']);
        if (item.expect['dvProfile'] case final int p) {
          expect(hdr.video.dolbyVisionProfile, p);
        }
        if (item.expect['dvProfile'] == 7) {
          expect(hdr.notices, contains(EngineNotice.enhancementLayerIgnored));
        }
        // Never a black screen.
        // The clip is short: take the frame already drawn, not a new one.
        await e.softwareRenderer!.firstFrame.timeout(
          const Duration(seconds: 10),
        );
        final frame = e.softwareRenderer!.latest!;
        expect(frame.pixels.any((b) => b > 16), isTrue);
      }, skip: skip);
    }
    if (lfs.isEmpty) {
      test(
        'VID-032…035 samples',
        () {},
        skip:
            'blocked: STATUS §3 — no Dolby Vision / HDR10+ samples in '
            'test-media/corpus (VID-032…035)',
      );
    }
  });
}
