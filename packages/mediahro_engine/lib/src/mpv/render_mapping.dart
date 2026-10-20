import 'dart:math' as math;

import 'package:mediahro_engine/src/api/models.dart';

String _n(num v) {
  if (v == v.roundToDouble()) return v.toInt().toString();
  return v
      .toStringAsFixed(4)
      .replaceFirst(RegExp(r'0+$'), '')
      .replaceFirst(RegExp(r'\.$'), '');
}

/// mpv `tone-mapping` value (VID-031).
String toneMappingName(ToneMapping t) => switch (t) {
  ToneMapping.bt2390 => 'bt.2390',
  ToneMapping.spline => 'spline',
  ToneMapping.reinhard => 'reinhard',
  ToneMapping.hable => 'hable',
  ToneMapping.mobius => 'mobius',
  ToneMapping.clip => 'clip',
};

/// mpv properties for [chain] (VID-031, VID-037, VID-039, VID-040, VID-041).
///
/// Deinterlacing and sharpening use mpv's own `deinterlace` and the
/// libplacebo `sharpen`/`deband` options, so no GPL video filter (pp, yadif
/// GPL parts) is ever inserted. Crop, stereo and 360° views use LGPL
/// libavfilter filters only (`crop`, `setsar`, `split`, `lutrgb`, `blend`,
/// `v360`); FFmpeg's `stereo3d` is GPL and never used. [iccProfilePath] is
/// the display profile resolved for [VideoFilterChain.iccAuto] where the
/// render API cannot find it itself (Windows, macOS).
Map<String, String> videoFilterProperties(
  VideoFilterChain chain, {
  String? iccProfilePath,
}) => {
  'tone-mapping': toneMappingName(chain.toneMapping),
  'scale': switch (chain.scaler) {
    Scaler.bilinear => 'bilinear',
    Scaler.spline36 => 'spline36',
    Scaler.ewaLanczos => 'ewa_lanczos',
  },
  'deband': chain.deband ? 'yes' : 'no',
  'deinterlace': switch (chain.deinterlace) {
    Deinterlace.off => 'no',
    Deinterlace.auto => 'auto',
    Deinterlace.yadif || Deinterlace.bwdif => 'yes',
  },
  'deinterlace-field-parity': 'auto',
  'sharpen': _n(chain.sharpen),
  'brightness': _n(chain.brightness.clamp(-100, 100)),
  'contrast': _n(chain.contrast.clamp(-100, 100)),
  'saturation': _n(chain.saturation.clamp(-100, 100)),
  'gamma': _n(chain.gamma.clamp(-100, 100)),
  'hue': _n(chain.hue.clamp(-100, 100)),
  'video-rotate': '${((chain.rotate % 360) + 360) % 360}',
  'vf': [
    if (chain.deinterlace == Deinterlace.bwdif) 'bwdif',
    ?stereoProjectionFilter(chain),
    ?cropFilter(chain.crop),
    if (chain.flipHorizontal) 'hflip',
    if (chain.flipVertical) 'vflip',
  ].join(','),
  'icc-profile-auto': chain.iccAuto && chain.iccProfile == null ? 'yes' : 'no',
  'icc-profile':
      chain.iccProfile?.toFilePath() ??
      (chain.iccAuto ? iccProfilePath : null) ??
      '',
  'lut': chain.lut3d?.toFilePath() ?? '',
  'lut-type': chain.lutType.name,
  'video-aspect-override': chain.aspectOverride == null
      ? 'no'
      : _n(chain.aspectOverride!),
  'video-zoom': _n(chain.zoom),
  'video-pan-x': _n(chain.panX),
  'video-pan-y': _n(chain.panY),
  'interpolation': chain.interpolation ? 'yes' : 'no',
  'tscale': chain.interpolation ? 'oversample' : 'linear',
};

/// `crop` for [crop] fractions (VID-037), or null for none. Each edge is
/// clamped to 0…0.45 so something always remains.
String? cropFilter(
  ({double left, double top, double right, double bottom})? crop,
) {
  if (crop == null) return null;
  double c(double v) => v.isNaN ? 0 : v.clamp(0, 0.45).toDouble();
  final (l, t, r, b) = (
    c(crop.left),
    c(crop.top),
    c(crop.right),
    c(crop.bottom),
  );
  if (l == 0 && t == 0 && r == 0 && b == 0) return null;
  return 'crop=w=iw*${_n(1 - l - r)}:h=ih*${_n(1 - t - b)}'
      ':x=iw*${_n(l)}:y=ih*${_n(t)}';
}

/// The lavfi graph for [VideoFilterChain.stereo] and
/// [VideoFilterChain.projection] (VID-041), or null for flat 2D video.
///
/// - One eye: the left (or top) half; a half-resolution layout (an SBS frame
///   narrower than 3:1, a TAB frame wider than 1:1) gets its pixel aspect
///   doubled back.
/// - Anaglyph: the left eye's red with the right eye's green and blue.
/// - 360°/180°: `v360` to a 1280×720 flat view; stereo layouts are read by
///   `v360` itself (left eye), and VR180 is half-equirect side by side.
String? stereoProjectionFilter(VideoFilterChain chain) {
  final sbs =
      chain.stereo == StereoMode.sbsToLeft ||
      chain.stereo == StereoMode.sbsAnaglyph;
  final tab =
      chain.stereo == StereoMode.tabToLeft ||
      chain.stereo == StereoMode.tabAnaglyph;
  if (chain.projection != Projection.flat) {
    final h = chain.fov.clamp(30, 150).toDouble();
    final v =
        2 * math.atan(math.tan(h * math.pi / 360) * 9 / 16) * 180 / math.pi;
    final input = chain.projection == Projection.equirect360
        ? 'e'
        : 'hequirect';
    final stereo = chain.projection == Projection.vr180 || sbs
        ? 'sbs'
        : (tab ? 'tb' : null);
    return 'lavfi=[v360=input=$input:output=flat'
        '${stereo == null ? '' : ':in_stereo=$stereo:out_stereo=2d'}'
        ':h_fov=${_n(h)}:v_fov=${_n(v)}'
        ':yaw=${_n(chain.yaw.clamp(-180, 180))}'
        ':pitch=${_n(chain.pitch.clamp(-90, 90))}'
        ':w=1280:h=720:interp=linear]';
  }
  if (!sbs && !tab) return null;
  // Half-resolution layouts squeeze each eye; restore its shape.
  final sar = sbs
      ? r'setsar=r=if(gte(dar\,3)\,sar\,sar*2)'
      : r'setsar=r=if(lte(dar\,1)\,sar\,sar/2)';
  final (left, right) = sbs
      ? ('crop=iw/2:ih:0:0', 'crop=iw/2:ih:iw/2:0')
      : ('crop=iw:ih/2:0:0', 'crop=iw:ih/2:0:ih/2');
  final anaglyph =
      chain.stereo == StereoMode.sbsAnaglyph ||
      chain.stereo == StereoMode.tabAnaglyph;
  if (!anaglyph) return 'lavfi=[$sar,$left]';
  return 'lavfi=[$sar,split[a][b];[a]$left,lutrgb=g=0:b=0[l];'
      '[b]$right,lutrgb=r=0[r];[l][r]blend=all_mode=addition]';
}

/// mpv `glsl-shaders` list for [preset] (VID-038). Paths are platform file
/// paths; the list separator is `;` on Windows and `:` elsewhere.
String shaderListValue(ShaderPreset preset, {required bool windows}) => preset
    .shaders
    .map((u) => u.toFilePath(windows: windows))
    .join(windows ? ';' : ':');

/// `#AARRGGBB` → mpv color `#AARRGGBB` (mpv reads alpha first as well).
String _color(int argb) =>
    '#${(argb & 0xFFFFFFFF).toRadixString(16).padLeft(8, '0').toUpperCase()}';

/// mpv properties for [style] in [slot] (SUB-014, SUB-016).
///
/// Unset fields map to the system caption preferences, which the platform
/// module resolves into a concrete [SubtitleStyle] before calling the engine.
/// The secondary slot only has position and ASS-override controls in mpv; its
/// text is exposed as `PlaybackState.secondarySubtitleText` so the UI can
/// draw it at an independent size.
Map<String, String> subtitleStyleProperties(
  SubtitleStyle style, {
  SubtitleSlot slot = SubtitleSlot.primary,
}) {
  final pos = style.verticalPosition == null
      ? null
      : _n((100 - style.verticalPosition!.clamp(0, 100)).round());
  if (slot == SubtitleSlot.secondary) {
    return {
      'secondary-sub-pos': ?pos,
      'secondary-sub-ass-override': style.overrideAssStyles ? 'force' : 'yes',
    };
  }
  return {
    'sub-font': ?style.font,
    if (style.scale != null) 'sub-scale': _n(style.scale!.clamp(0, 100)),
    if (style.colorArgb != null) 'sub-color': _color(style.colorArgb!),
    if (style.outlineColorArgb != null)
      'sub-outline-color': _color(style.outlineColorArgb!),
    if (style.outlineWidth != null) 'sub-outline-size': _n(style.outlineWidth!),
    if (style.shadowOffset != null)
      'sub-shadow-offset': _n(style.shadowOffset!),
    if (style.backgroundArgb != null)
      'sub-back-color': _color(style.backgroundArgb!),
    'sub-border-style': switch (style.borderStyle) {
      SubtitleBorderStyle.outlineAndShadow => 'outline-and-shadow',
      SubtitleBorderStyle.opaqueBox => 'opaque-box',
      SubtitleBorderStyle.backgroundBox => 'background-box',
    },
    'sub-pos': ?pos,
    if (style.alignX != null) 'sub-align-x': style.alignX!.name,
    if (style.marginX != null) 'sub-margin-x': _n(style.marginX!),
    if (style.marginY != null) 'sub-margin-y': _n(style.marginY!),
    'sub-ass-override': style.overrideAssStyles ? 'force' : 'scale',
  };
}

/// Delay range and step (SUB-015): ±60 s in 50 ms steps.
const Duration maxSubtitleDelay = Duration(seconds: 60);
const Duration subtitleDelayStep = Duration(milliseconds: 50);

/// Clamps and snaps a subtitle delay to the SUB-015 grid.
Duration snapSubtitleDelay(Duration d) {
  final ms = d.inMilliseconds.clamp(
    -maxSubtitleDelay.inMilliseconds,
    maxSubtitleDelay.inMilliseconds,
  );
  final step = subtitleDelayStep.inMilliseconds;
  return Duration(milliseconds: (ms / step).round() * step);
}

/// Speed factor converting subtitles timed for [from] fps to video at [to]
/// fps (SUB-015, e.g. 23.976 → 25).
double subtitleFpsFactor({required double from, required double to}) =>
    from / to;

/// mpv seconds string for a [Duration].
String secondsValue(Duration d) => _n(d.inMicroseconds / 1e6);
