import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:mediahro/features/video/player/video_render.dart';

/// Where the bundled shaders live in the app's assets (ADR-034: only
/// MIT-licensed shaders, with their licence notices next to them).
///
/// Sources (owner approved 2026-10-20; SHA-256 of the downloads):
/// - Anime4K v4.0.1, `Anime4K_v4.0.zip` from github.com/bloc97/Anime4K
///   releases (`139cd282…62d7ed7`), MIT © 2019 bloc97: only the files
///   [bundledPresets] use; `LICENSE-Anime4K.txt` is the repository's
///   LICENSE at v4.0.1 (`5bad448b…6953f5`).
/// - `FSR.glsl`, AMD FidelityFX FSR 1.0.2 ported to mpv by agyild
///   (gist 82219c54…, revision f1794d72; `56d8597f…16929b9e`), MIT
///   © 2021 Advanced Micro Devices; `LICENSE-FSR.txt` is its header
///   notice.
/// - `Mediahro_FilmGrain.glsl`: ours. `SOURCES.md` lists every file's
///   SHA-256.
const shaderAssetDir = 'assets/shaders';

/// A built-in shader preset (VID-038): the GLSL files it chains, in order.
@immutable
final class BundledPreset {
  const BundledPreset(this.key, this.files);

  /// Selects the preset's name in `videoShaderPresetName`.
  final String key;
  final List<String> files;

  String get id => 'builtin:$key';
}

/// Anime4K v4 modes (fast and high-quality strengths) and AMD FSR, the
/// MIT set ADR-034 allows, and Mediahro's own film grain. Each file list follows Anime4K's mpv
/// instructions; a preset shows only when all of its files are bundled.
const bundledPresets = <BundledPreset>[
  BundledPreset('anime4kAFast', [
    'Anime4K_Clamp_Highlights.glsl',
    'Anime4K_Restore_CNN_M.glsl',
    'Anime4K_Upscale_CNN_x2_M.glsl',
    'Anime4K_AutoDownscalePre_x2.glsl',
    'Anime4K_AutoDownscalePre_x4.glsl',
    'Anime4K_Upscale_CNN_x2_S.glsl',
  ]),
  BundledPreset('anime4kAHq', [
    'Anime4K_Clamp_Highlights.glsl',
    'Anime4K_Restore_CNN_VL.glsl',
    'Anime4K_Upscale_CNN_x2_VL.glsl',
    'Anime4K_AutoDownscalePre_x2.glsl',
    'Anime4K_AutoDownscalePre_x4.glsl',
    'Anime4K_Upscale_CNN_x2_M.glsl',
  ]),
  BundledPreset('anime4kBFast', [
    'Anime4K_Clamp_Highlights.glsl',
    'Anime4K_Restore_CNN_Soft_M.glsl',
    'Anime4K_Upscale_CNN_x2_M.glsl',
    'Anime4K_AutoDownscalePre_x2.glsl',
    'Anime4K_AutoDownscalePre_x4.glsl',
    'Anime4K_Upscale_CNN_x2_S.glsl',
  ]),
  BundledPreset('anime4kBHq', [
    'Anime4K_Clamp_Highlights.glsl',
    'Anime4K_Restore_CNN_Soft_VL.glsl',
    'Anime4K_Upscale_CNN_x2_VL.glsl',
    'Anime4K_AutoDownscalePre_x2.glsl',
    'Anime4K_AutoDownscalePre_x4.glsl',
    'Anime4K_Upscale_CNN_x2_M.glsl',
  ]),
  BundledPreset('anime4kCFast', [
    'Anime4K_Clamp_Highlights.glsl',
    'Anime4K_Upscale_Denoise_CNN_x2_M.glsl',
    'Anime4K_AutoDownscalePre_x2.glsl',
    'Anime4K_AutoDownscalePre_x4.glsl',
    'Anime4K_Upscale_CNN_x2_S.glsl',
  ]),
  BundledPreset('anime4kCHq', [
    'Anime4K_Clamp_Highlights.glsl',
    'Anime4K_Upscale_Denoise_CNN_x2_VL.glsl',
    'Anime4K_AutoDownscalePre_x2.glsl',
    'Anime4K_AutoDownscalePre_x4.glsl',
    'Anime4K_Upscale_CNN_x2_M.glsl',
  ]),
  BundledPreset('fsr', ['FSR.glsl']),
  // Our own shader (doc 04 film grain), under the app's licence.
  BundledPreset('filmGrain', ['Mediahro_FilmGrain.glsl']),
];

/// The bundled presets whose files are all in [bundle], copied into
/// [dir] (mpv reads shaders by path, and assets have none on Android).
/// Files already copied with the same size are kept.
Future<List<ShaderChoice>> bundledShaders(
  AssetBundle bundle,
  Directory dir, {
  List<BundledPreset> presets = bundledPresets,
}) async {
  final Set<String> assets;
  try {
    assets = (await AssetManifest.loadFromAssetBundle(bundle))
        .listAssets()
        .toSet();
  } on Object {
    return const [];
  }
  String asset(String file) => '$shaderAssetDir/$file';
  final available = [
    for (final p in presets)
      if (p.files.every((f) => assets.contains(asset(f)))) p,
  ];
  if (available.isEmpty) return const [];
  await dir.create(recursive: true);
  final copied = <String, Uri>{};
  for (final file in {for (final p in available) ...p.files}) {
    final data = await bundle.load(asset(file));
    final out = File('${dir.path}/$file');
    if (!out.existsSync() || out.lengthSync() != data.lengthInBytes) {
      await out.writeAsBytes(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        flush: true,
      );
    }
    copied[file] = out.uri;
  }
  return [
    for (final p in available)
      ShaderChoice(p.id, p.key, [
        for (final f in p.files) copied[f]!,
      ], builtIn: true),
  ];
}

/// Adds the bundled shaders' licence notices (`LICENSE-*.txt` next to
/// them) to the app's licence list (CORE-013). Call once at start-up.
Future<void> registerShaderLicences([AssetBundle? bundle]) async {
  final b = bundle ?? rootBundle;
  final List<String> notices;
  try {
    notices = (await AssetManifest.loadFromAssetBundle(b))
        .listAssets()
        .where(
          (a) => a.startsWith('$shaderAssetDir/LICENSE-') && a.endsWith('.txt'),
        )
        .toList();
  } on Object {
    return;
  }
  for (final notice in notices) {
    final name = notice
        .substring('$shaderAssetDir/LICENSE-'.length)
        .replaceAll('.txt', '');
    LicenseRegistry.addLicense(() async* {
      yield LicenseEntryWithLineBreaks([name], await b.loadString(notice));
    });
  }
}
