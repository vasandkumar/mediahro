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

/// mpv properties for [chain] (VID-031, VID-037, VID-039, VID-041).
///
/// Deinterlacing and sharpening use mpv's own `deinterlace` and the
/// libplacebo `sharpen`/`deband` options, so no GPL video filter (pp, yadif
/// GPL parts) is ever inserted.
Map<String, String> videoFilterProperties(VideoFilterChain chain) => {
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
    if (chain.flipHorizontal) 'hflip',
    if (chain.flipVertical) 'vflip',
    if (chain.deinterlace == Deinterlace.bwdif) 'bwdif',
  ].join(','),
  'video-aspect-override': chain.aspectOverride == null
      ? 'no'
      : _n(chain.aspectOverride!),
  'video-zoom': _n(chain.zoom),
  'video-pan-x': _n(chain.panX),
  'video-pan-y': _n(chain.panY),
  'interpolation': chain.interpolation ? 'yes' : 'no',
  'tscale': chain.interpolation ? 'oversample' : 'linear',
};

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
