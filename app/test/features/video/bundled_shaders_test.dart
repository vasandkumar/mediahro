import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediahro/features/video/player/bundled_shaders.dart';

/// Serves [files] (asset path → text) and the manifest Flutter builds.
final class _Bundle extends CachingAssetBundle {
  _Bundle(this.files);

  final Map<String, String> files;
  int loads = 0;

  @override
  Future<ByteData> load(String key) async {
    if (key == 'AssetManifest.bin') {
      final manifest = {
        for (final a in files.keys)
          a: [
            <String, Object>{'asset': a},
          ],
      };
      return const StandardMessageCodec().encodeMessage(manifest)!;
    }
    final text = files[key];
    if (text == null) throw FlutterError('missing $key');
    loads++;
    return ByteData.sublistView(Uint8List.fromList(utf8.encode(text)));
  }
}

void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('c1-builtin');
  });

  tearDown(() => dir.delete(recursive: true));

  test('VID-038 no bundled shaders: no built-in presets', () async {
    expect(await bundledShaders(_Bundle({}), dir), isEmpty);
  });

  test('VID-038 a preset shows only when all its files are bundled, and '
      'they are copied to a file path for mpv', () async {
    const presets = [
      BundledPreset('fsr', ['FSR.glsl']),
      BundledPreset('anime4kAFast', ['A.glsl', 'B.glsl']),
    ];
    final bundle = _Bundle({
      '$shaderAssetDir/FSR.glsl': '//!HOOK MAIN fsr',
      '$shaderAssetDir/A.glsl': '//!HOOK MAIN a',
    });
    final list = await bundledShaders(bundle, dir, presets: presets);
    expect(list.map((x) => x.id), ['builtin:fsr']);
    final choice = list.single;
    expect(choice.builtIn, isTrue);
    expect(choice.name, 'fsr');
    final file = File.fromUri(choice.files.single);
    expect(file.readAsStringSync(), '//!HOOK MAIN fsr');
    expect(choice.preset.shaders.single.scheme, 'file');
  });

  test('VID-038 shared files are copied once and kept between runs', () async {
    const presets = [
      BundledPreset('anime4kAFast', ['A.glsl', 'S.glsl']),
      BundledPreset('anime4kAHq', ['A.glsl', 'M.glsl']),
    ];
    final bundle = _Bundle({
      for (final f in ['A', 'S', 'M']) '$shaderAssetDir/$f.glsl': '// $f',
    });
    final first = await bundledShaders(bundle, dir, presets: presets);
    expect(first, hasLength(2));
    expect(bundle.loads, 3);
    expect(first[0].files.first, first[1].files.first);
    final stamp = File('${dir.path}/A.glsl').lastModifiedSync();
    await bundledShaders(bundle, dir, presets: presets);
    expect(File('${dir.path}/A.glsl').lastModifiedSync(), stamp);
  });

  test('VID-038 the bundled folder holds exactly the files the presets use, '
      'and their licences', () {
    final dir = Directory(shaderAssetDir);
    final present = {
      for (final f in dir.listSync().whereType<File>()) f.uri.pathSegments.last,
    };
    final needed = {for (final p in bundledPresets) ...p.files};
    expect(present, {
      ...needed,
      'LICENSE-Anime4K.txt',
      'LICENSE-FSR.txt',
      'SOURCES.md',
    });
    // SOURCES.md records the SHA-256 of every file as bundled.
    final sources = File('${dir.path}/SOURCES.md').readAsStringSync();
    for (final f in present.where((f) => f != 'SOURCES.md')) {
      final hash = sha256
          .convert(File('${dir.path}/$f').readAsBytesSync())
          .toString();
      expect(sources, contains('| $f | `$hash` |'), reason: f);
      expect(
        File('${dir.path}/$f').readAsStringSync(),
        isNot(contains('\r\n')),
        reason: '$f: stored with LF, so the hash holds on every checkout',
      );
    }
    for (final f in needed) {
      expect(
        File('${dir.path}/$f').readAsStringSync(),
        contains('//!HOOK'),
        reason: f,
      );
    }
    expect(
      File('${dir.path}/LICENSE-Anime4K.txt').readAsStringSync(),
      startsWith('MIT License'),
    );
    expect(
      File('${dir.path}/LICENSE-FSR.txt').readAsStringSync(),
      contains('Advanced Micro Devices'),
    );
  });

  test('VID-038 every built-in preset uses only MIT shaders (ADR-034)', () {
    for (final p in bundledPresets) {
      for (final f in p.files) {
        expect(
          f.startsWith('Anime4K_') ||
              f == 'FSR.glsl' ||
              f.startsWith('Mediahro_'),
          isTrue,
          reason: '${p.key}: $f',
        );
      }
      expect(p.files.any((f) => f.toLowerCase().contains('nnedi')), isFalse);
      expect(p.files.any((f) => f.toLowerCase().contains('ssim')), isFalse);
    }
  });

  testWidgets("CORE-013 the shaders' licence notices are registered", (
    tester,
  ) async {
    final bundle = _Bundle({
      '$shaderAssetDir/LICENSE-Anime4K.txt': 'MIT License\n\nAnime4K',
      '$shaderAssetDir/FSR.glsl': '//',
    });
    await tester.runAsync(() => registerShaderLicences(bundle));
    final entries = (await tester.runAsync(
      () => LicenseRegistry.licenses.toList(),
    ))!;
    final ours = entries.where((e) => e.packages.contains('Anime4K'));
    expect(ours, hasLength(1));
    expect(
      ours.single.paragraphs.map((p) => p.text).join('\n'),
      contains('MIT License'),
    );
  });
}
