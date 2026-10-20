import 'package:flutter_test/flutter_test.dart';
import 'package:mediahro_engine/mediahro_engine.dart';
import 'package:mediahro_engine/src/mpv/render_mapping.dart';

/// ADR-033 filter-chain additions mapped to mpv (VID-037, VID-040, VID-041).
void main() {
  test('VID-037 default chains add no filters and clear ICC/LUT', () {
    final p = videoFilterProperties(const VideoFilterChain());
    expect(p['vf'], '');
    expect(p['icc-profile'], '');
    expect(p['icc-profile-auto'], 'no');
    expect(p['lut'], '');
    expect(p['lut-type'], 'auto');
  });

  test('VID-037 crop fractions become a lavfi crop, clamped', () {
    expect(
      cropFilter((left: 0.1, top: 0.2, right: 0.3, bottom: 0)),
      'crop=w=iw*0.6:h=ih*0.8:x=iw*0.1:y=ih*0.2',
    );
    expect(
      cropFilter((left: 0.9, top: -1, right: 0, bottom: 0)),
      'crop=w=iw*0.55:h=ih*1:x=iw*0.45:y=ih*0',
    );
    expect(cropFilter((left: 0, top: 0, right: 0, bottom: 0)), isNull);
    expect(cropFilter(null), isNull);
  });

  test('VID-041 stereo uses LGPL filters only, never stereo3d', () {
    for (final mode in StereoMode.values.skip(1)) {
      final f = stereoProjectionFilter(VideoFilterChain(stereo: mode))!;
      expect(f, isNot(contains('stereo3d')));
      expect(f, startsWith('lavfi=[setsar='));
    }
    expect(
      stereoProjectionFilter(
        const VideoFilterChain(stereo: StereoMode.sbsToLeft),
      ),
      r'lavfi=[setsar=r=if(gte(dar\,3)\,sar\,sar*2),crop=iw/2:ih:0:0]',
    );
    expect(
      stereoProjectionFilter(
        const VideoFilterChain(stereo: StereoMode.tabAnaglyph),
      ),
      contains('blend=all_mode=addition'),
    );
    expect(stereoProjectionFilter(const VideoFilterChain()), isNull);
  });

  test('VID-041 360° and VR180 views map to v360 with the view angles', () {
    final f = stereoProjectionFilter(
      const VideoFilterChain(
        projection: Projection.equirect360,
        yaw: 200,
        pitch: -30,
      ),
    )!;
    expect(f, startsWith('lavfi=[v360=input=e:output=flat:h_fov=90:'));
    expect(f, contains(':yaw=180:pitch=-30:'));
    // 16:9 view: vertical fov from the horizontal one (90° by default).
    expect(f, contains('v_fov=58.7155'));
    final vr = stereoProjectionFilter(
      const VideoFilterChain(projection: Projection.vr180),
    )!;
    expect(vr, contains('input=hequirect:output=flat:in_stereo=sbs'));
    final tab360 = stereoProjectionFilter(
      const VideoFilterChain(
        projection: Projection.equirect360,
        stereo: StereoMode.tabToLeft,
      ),
    )!;
    expect(tab360, contains('in_stereo=tb:out_stereo=2d'));
  });

  test('VID-040 ICC and LUT options; an explicit profile wins', () {
    final explicit = videoFilterProperties(
      VideoFilterChain(
        iccAuto: true,
        iccProfile: Uri.file('/p/display.icc'),
        lut3d: Uri.file('/p/film.cube'),
        lutType: Lut3dType.conversion,
      ),
      iccProfilePath: '/sys/auto.icc',
    );
    expect(explicit['icc-profile'], Uri.file('/p/display.icc').toFilePath());
    expect(explicit['icc-profile-auto'], 'no');
    expect(explicit['lut'], Uri.file('/p/film.cube').toFilePath());
    expect(explicit['lut-type'], 'conversion');
    final auto = videoFilterProperties(
      const VideoFilterChain(iccAuto: true),
      iccProfilePath: '/sys/auto.icc',
    );
    expect(auto['icc-profile'], '/sys/auto.icc');
    expect(auto['icc-profile-auto'], 'yes');
  });

  test('VID-041 filters keep their order around flips and deinterlacing', () {
    final p = videoFilterProperties(
      const VideoFilterChain(
        deinterlace: Deinterlace.bwdif,
        stereo: StereoMode.sbsToLeft,
        crop: (left: 0.1, top: 0, right: 0, bottom: 0),
        flipVertical: true,
      ),
    );
    final vf = p['vf']!;
    expect(vf.indexOf('bwdif'), lessThan(vf.indexOf('lavfi')));
    expect(vf.indexOf('lavfi'), lessThan(vf.indexOf('crop=w=')));
    expect(vf.indexOf('crop=w='), lessThan(vf.indexOf('vflip')));
  });
}
