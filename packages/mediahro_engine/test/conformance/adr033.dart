import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mediahro_engine/mediahro_engine.dart';

import 'support.dart';

/// ADR-033 on real libmpv: crop (VID-037), ICC/LUT (VID-040), stereo 3D
/// and 360° views (VID-041), checked by pixels of the software renderer on
/// `quad_colors.mkv` (red | green over blue | white).

void adr033Suite() {
  final skip = ffiSkipReason;
  // Crop and one-eye stereo use lavfi crop/setsar, which every mediahro-deps
  // build has; the Apple bootstrap libmpv lacks lavfi filters.
  final lavfi = blockedOn(appleBootstrap, appleBootstrapBlocker);
  // Anaglyph and 360° need lutrgb, blend and v360, which mediahro-deps
  // v2026.10.5 builds on every platform.
  prepareCorpus();

  const red = (255, 0, 0);
  const green = (0, 255, 0);
  const blue = (0, 0, 255);
  const white = (255, 255, 255);
  const yellow = (255, 255, 0);
  const cyan = (0, 255, 255);

  Future<MpvEngine> quad() async {
    final e = headlessEngine(extraOptions: {'loop-file': 'inf'});
    addTearDown(e.dispose);
    await e.open(UriSource(Uri.file(corpusPath('quad_colors.mkv'))));
    await waitPlaying(e);
    return e;
  }

  /// Waits until the corners of the 320×180 output show [tl], [tr], [bl],
  /// [br] (within a codec's tolerance).
  Future<void> expectCorners(
    MpvEngine e,
    (int, int, int) tl,
    (int, int, int) tr,
    (int, int, int) bl,
    (int, int, int) br, {
    required String reason,
  }) async {
    bool near((int, int, int) a, (int, int, int) b) =>
        (a.$1 - b.$1).abs() < 48 &&
        (a.$2 - b.$2).abs() < 48 &&
        (a.$3 - b.$3).abs() < 48;
    final points = [(80, 45), (240, 45), (80, 135), (240, 135)];
    final want = [tl, tr, bl, br];
    var got = <(int, int, int)>[];
    final deadline = DateTime.now().add(const Duration(seconds: 8));
    while (DateTime.now().isBefore(deadline)) {
      final f = e.softwareRenderer!.latest;
      if (f != null) {
        got = [for (final (x, y) in points) f.pixel(x, y)];
        if ([for (var i = 0; i < 4; i++) near(got[i], want[i])]
            .every((b) => b)) {
          return;
        }
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    fail('$reason: corners $got, want $want');
  }

  group('VID-037 crop', () {
    test(
      'VID-037 crop keeps the chosen part of the frame',
      () async {
        final e = await quad();
        await expectCorners(e, red, green, blue, white, reason: 'plain');
        await e.setVideoFilters(
          const VideoFilterChain(
            crop: (left: 0, top: 0, right: 0.45, bottom: 0.45),
          ),
        );
        await expectCorners(e, red, red, red, red, reason: 'top left kept');
        await e.setVideoFilters(
          const VideoFilterChain(
            crop: (left: 0.45, top: 0.45, right: 0, bottom: 0),
          ),
        );
        await expectCorners(
          e,
          white,
          white,
          white,
          white,
          reason: 'bottom right kept',
        );
        await e.setVideoFilters(const VideoFilterChain());
        await expectCorners(e, red, green, blue, white, reason: 'uncropped');
      },
      skip: lavfi,
      timeout: const Timeout(Duration(minutes: 1)),
    );
  });

  group('VID-041 stereo and 360°', () {
    test(
      'VID-041 side-by-side and top-and-bottom 3D show one eye at full shape',
      () async {
        final e = await quad();
        await e.setVideoFilters(
          const VideoFilterChain(stereo: StereoMode.sbsToLeft),
        );
        await expectCorners(e, red, red, blue, blue, reason: 'SBS left eye');
        await e.setVideoFilters(
          const VideoFilterChain(stereo: StereoMode.tabToLeft),
        );
        await expectCorners(e, red, green, red, green, reason: 'TAB top eye');
      },
      skip: lavfi,
      timeout: const Timeout(Duration(minutes: 1)),
    );

    test(
      'VID-041 anaglyph takes red from the left eye, green and blue from '
      'the right',
      () async {
        final e = await quad();
        await e.setVideoFilters(
          const VideoFilterChain(stereo: StereoMode.sbsAnaglyph),
        );
        // Left eye red / blue, right eye green / white.
        await expectCorners(
          e,
          yellow,
          yellow,
          cyan,
          cyan,
          reason: 'SBS anaglyph',
        );
        await e.setVideoFilters(
          const VideoFilterChain(stereo: StereoMode.tabAnaglyph),
        );
        // Top eye red | green, bottom eye blue | white: magenta | cyan.
        await expectCorners(
          e,
          (255, 0, 255),
          cyan,
          (255, 0, 255),
          cyan,
          reason: 'TAB anaglyph',
        );
      },
      skip: lavfi,
      timeout: const Timeout(Duration(minutes: 1)),
    );

    test(
      'VID-041 a 360° view turns with yaw and pitch, coalescing head moves',
      () async {
        final e = await quad();
        for (final (yaw, pitch, colour, name) in [
          (-90.0, 45.0, red, 'left and up'),
          (90.0, 45.0, green, 'right and up'),
          (90.0, -45.0, white, 'right and down'),
          (-90.0, -45.0, blue, 'left and down'),
        ]) {
          await e.setVideoFilters(
            VideoFilterChain(
              projection: Projection.equirect360,
              yaw: yaw,
              pitch: pitch,
              fov: 60,
            ),
          );
          await expectCorners(e, colour, colour, colour, colour, reason: name);
        }
        // A gyro burst: only the last view matters.
        await Future.wait([
          for (var i = 0; i <= 30; i++)
            e.setVideoFilters(
              VideoFilterChain(
                projection: Projection.equirect360,
                yaw: -90 + i * 6,
                pitch: 45,
                fov: 60,
              ),
            ),
        ]);
        await expectCorners(e, green, green, green, green, reason: 'burst');
      },
      skip: lavfi,
      timeout: const Timeout(Duration(minutes: 1)),
    );
  });

  group('VID-040 colour management', () {
    test(
      'VID-040 an ICC profile and a 3D LUT are accepted without an error',
      () async {
        final e = await quad();
        final dir = await Directory.systemTemp.createTemp('mh-lut');
        addTearDown(() => dir.delete(recursive: true));
        // An identity 2×2×2 LUT.
        final lut = File('${dir.path}${Platform.pathSeparator}id.cube')
          ..writeAsStringSync(
            'LUT_3D_SIZE 2\n'
            '${[for (var b = 0; b < 2; b++)
              for (var g = 0; g < 2; g++)
                for (var r = 0; r < 2; r++) '$r $g $b'].join('\n')}\n',
          );
        await e.setVideoFilters(
          VideoFilterChain(iccAuto: true, lut3d: lut.uri),
        );
        await e.setVideoFilters(const VideoFilterChain());
        await expectCorners(e, red, green, blue, white, reason: 'still plays');
        expect(e.current.error, isNull);
      },
      skip: skip,
      timeout: const Timeout(Duration(minutes: 1)),
    );
  });
}
