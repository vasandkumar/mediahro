import 'package:flutter_test/flutter_test.dart';
import 'package:mediahro_engine/mediahro_engine.dart';

import 'support.dart';

/// VID-002 / VID-005: seeking to the start while playing must not freeze
/// playback (the Exynos MediaCodec stall), and a frozen hardware decoder is
/// rebuilt in software.
void decoderStallSuite() {
  final skip = ffiSkipReason;
  prepareCorpus();

  group('VID-002 decoder stalls', () {
    test(
      'VID-002 seeking to the start while playing keeps playing',
      () async {
        final e = headlessEngine(extraOptions: {'loop-file': 'inf'});
        addTearDown(e.dispose);
        await e.open(UriSource(Uri.file(corpusPath('mp4_h264_aac.mp4'))));
        await waitFor(
          e,
          (s) => s.position > const Duration(milliseconds: 1500),
          reason: 'playing past 1.5 s',
        );
        for (var i = 0; i < 3; i++) {
          await e.seek(const Duration(milliseconds: 400), mode: SeekMode.exact);
          // Within the stall threshold plus a rebuilt decoder's start.
          await waitFor(
            e,
            (s) =>
                s.status == PlaybackStatus.playing &&
                s.position > const Duration(milliseconds: 1200),
            timeout: const Duration(seconds: 8),
            reason: 'position advances after seeking to the start',
          );
        }
      },
      skip: skip,
      timeout: const Timeout(Duration(minutes: 1)),
    );

    test(
      'VID-002 a stalled decoder continues in software from where it was',
      () async {
        // A hardware decoder (copy-back works with the headless renderer).
        final e = headlessEngine(
          extraOptions: {'loop-file': 'inf', 'hwdec': 'auto-copy'},
        );
        addTearDown(e.dispose);
        await e.open(UriSource(Uri.file(corpusPath('mp4_h264_aac.mp4'))));
        final before = await waitFor(
          e,
          (s) => s.position > const Duration(seconds: 1),
          reason: 'playing',
        );
        final hardware = before.video.hwdec != HwdecPath.none;
        await e.recoverStalledDecoder();
        final after = await waitFor(
          e,
          (s) =>
              s.notices.contains(EngineNotice.softwareDecodeFallback) &&
              s.position > before.position + const Duration(milliseconds: 500),
          reason: 'playback continues after the rebuild',
        );
        expect(after.video.hwdec, HwdecPath.none);
        expect(after.error, isNull);
        // The next item starts with the configured decoder and no notice.
        await e.open(UriSource(Uri.file(corpusPath('mp4_h264_aac.mp4'))));
        final next = await waitFor(
          e,
          (s) =>
              s.position > const Duration(milliseconds: 500) &&
              (!hardware || s.video.hwdec != HwdecPath.none),
          reason: 'the next item plays on the hardware decoder again',
        );
        expect(
          next.notices,
          isNot(contains(EngineNotice.softwareDecodeFallback)),
        );
      },
      skip: skip,
      timeout: const Timeout(Duration(minutes: 1)),
    );
  });
}
