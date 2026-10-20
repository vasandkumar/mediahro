import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mediahro/features/settings/settings_store.dart';
import 'package:mediahro/features/video/player/video_memory.dart';
import 'package:mediahro_engine/mediahro_engine.dart';

/// Picture settings that apply to every video (VID-031, VID-037, VID-039):
/// quality, colour, tone mapping and motion. Per-video rotation, flip,
/// aspect and zoom live in [VideoView].
abstract final class RenderSettings {
  static final SettingKey<Scaler> scaler = SettingKey.enumeration(
    'video.render.scaler',
    Scaler.values,
    defaultValue: Scaler.spline36,
  );
  static final SettingKey<bool> deband = SettingKey.boolean(
    'video.render.deband',
    defaultValue: false,
  );
  static final SettingKey<Deinterlace> deinterlace = SettingKey.enumeration(
    'video.render.deinterlace',
    Deinterlace.values,
    defaultValue: Deinterlace.auto,
  );

  /// 0…1.
  static final SettingKey<double> sharpen = SettingKey.decimal(
    'video.render.sharpen',
    defaultValue: 0,
    min: 0,
    max: 1,
  );

  /// −100…100 each, 0 = unchanged.
  static final SettingKey<double> brightness = _colour('brightness');
  static final SettingKey<double> contrast = _colour('contrast');
  static final SettingKey<double> saturation = _colour('saturation');
  static final SettingKey<double> gamma = _colour('gamma');
  static final SettingKey<double> hue = _colour('hue');

  static SettingKey<double> _colour(String name) => SettingKey.decimal(
    'video.render.$name',
    defaultValue: 0,
    min: -100,
    max: 100,
  );

  static final SettingKey<ToneMapping> toneMapping = SettingKey.enumeration(
    'video.render.toneMapping',
    ToneMapping.values,
    defaultValue: ToneMapping.bt2390,
  );

  /// Smooth motion (VID-039). Off by default; the player suggests it on
  /// desktop and warns about battery on phones and tablets.
  static final SettingKey<bool> interpolation = SettingKey.boolean(
    'video.render.interpolation',
    defaultValue: false,
  );

  /// The user shader preset (VID-038): `none` or a preset id.
  static final SettingKey<String> shaderPreset = SettingKey.text(
    'video.render.shader',
    defaultValue: 'none',
  );

  /// A folder of the user's own `.glsl` shaders (VID-038), as a URI.
  static final SettingKey<String> shaderFolder = SettingKey.text(
    'video.render.shaderFolder',
    defaultValue: '',
  );

  static final List<SettingKey<Object>> chainKeys = [
    scaler,
    deband,
    deinterlace,
    sharpen,
    brightness,
    contrast,
    saturation,
    gamma,
    hue,
    toneMapping,
    interpolation,
  ];

  static final List<SettingKey<double>> colourKeys = [
    brightness,
    contrast,
    saturation,
    gamma,
    hue,
  ];
}

/// The engine filter chain for the settings and this video's [view].
VideoFilterChain filterChainFor(SettingsSnapshot s, VideoView? view) {
  final v = view ?? const VideoView();
  return VideoFilterChain(
    toneMapping: s.get(RenderSettings.toneMapping),
    scaler: s.get(RenderSettings.scaler),
    deband: s.get(RenderSettings.deband),
    deinterlace: s.get(RenderSettings.deinterlace),
    sharpen: s.get(RenderSettings.sharpen),
    brightness: s.get(RenderSettings.brightness),
    contrast: s.get(RenderSettings.contrast),
    saturation: s.get(RenderSettings.saturation),
    gamma: s.get(RenderSettings.gamma),
    hue: s.get(RenderSettings.hue),
    rotate: v.rotate,
    flipHorizontal: v.flipH,
    flipVertical: v.flipV,
    aspectOverride: v.aspect,
    zoom: v.zoom,
    panX: v.panX,
    panY: v.panY,
    interpolation: s.get(RenderSettings.interpolation),
  );
}

/// Aspect choices for the Video sheet (VID-037): null is the file's own.
const List<double?> aspectChoices = [
  null,
  16 / 9,
  4 / 3,
  21 / 9,
  2.35,
  1.85,
  1,
];

/// A user-shader preset (VID-038): a name and the GLSL files it chains.
@immutable
final class ShaderChoice {
  const ShaderChoice(this.id, this.name, this.files);

  final String id;

  /// Display name: the file name for custom shaders.
  final String name;
  final List<Uri> files;

  ShaderPreset get preset => ShaderPreset(id: id, shaders: files);
}

/// Shader presets available on this device: the bundled set (once its
/// assets are approved; see the ADR request) plus every `.glsl` in the
/// user's shader folder.
final shaderLibraryProvider =
    Provider<Future<List<ShaderChoice>> Function(String folder)>(
      (ref) => listCustomShaders,
    );

Future<List<ShaderChoice>> listCustomShaders(String folder) async {
  if (folder.isEmpty) return const [];
  final uri = Uri.tryParse(folder);
  if (uri == null || uri.scheme != 'file') return const [];
  final dir = Directory.fromUri(uri);
  if (!dir.existsSync()) return const [];
  final files = await dir
      .list()
      .where((e) => e is File && e.path.toLowerCase().endsWith('.glsl'))
      .toList();
  files.sort((a, b) => a.path.compareTo(b.path));
  return [
    for (final f in files)
      ShaderChoice(
        'custom:${f.uri.pathSegments.last}',
        f.uri.pathSegments.last,
        [f.uri],
      ),
  ];
}
