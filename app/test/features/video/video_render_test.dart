import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mediahro/features/settings/settings_store.dart';
import 'package:mediahro/features/video/player/play_request.dart';
import 'package:mediahro/features/video/player/video_memory.dart';
import 'package:mediahro/features/video/player/video_player_controller.dart';
import 'package:mediahro/features/video/player/video_render.dart';
import 'package:mediahro_engine/mediahro_engine.dart';

import '../../../integration_test/support/c1_engine.dart';
import '../../helpers.dart';

void main() {
  group('VID-037 filter chain', () {
    test('VID-037 defaults leave the picture unchanged', () async {
      final s = await memoryStore();
      final chain = filterChainFor(s.snapshot, null);
      expect(chain.rotate, 0);
      expect(chain.flipHorizontal, isFalse);
      expect(chain.aspectOverride, isNull);
      expect(chain.zoom, 0);
      expect(chain.brightness, 0);
      expect(chain.scaler, Scaler.spline36);
      expect(chain.toneMapping, ToneMapping.bt2390);
      expect(chain.interpolation, isFalse);
    });

    test('VID-037 settings and the view map onto the chain', () async {
      final s = await memoryStore()
        ..set(RenderSettings.scaler, Scaler.ewaLanczos)
        ..set(RenderSettings.deband, true)
        ..set(RenderSettings.sharpen, 0.4)
        ..set<double>(RenderSettings.brightness, 20)
        ..set<double>(RenderSettings.hue, -30)
        ..set(RenderSettings.toneMapping, ToneMapping.hable)
        ..set(RenderSettings.interpolation, true);
      final chain = filterChainFor(
        s.snapshot,
        const VideoView(
          rotate: 90,
          flipH: true,
          aspect: 4 / 3,
          zoom: 0.5,
          panX: 0.1,
        ),
      );
      expect(chain.scaler, Scaler.ewaLanczos);
      expect(chain.deband, isTrue);
      expect(chain.sharpen, 0.4);
      expect(chain.brightness, 20);
      expect(chain.hue, -30);
      expect(chain.toneMapping, ToneMapping.hable);
      expect(chain.interpolation, isTrue);
      expect(chain.rotate, 90);
      expect(chain.flipHorizontal, isTrue);
      expect(chain.flipVertical, isFalse);
      expect(chain.aspectOverride, 4 / 3);
      expect(chain.zoom, 0.5);
      expect(chain.panX, 0.1);
    });
  });

  group('VID-037 per-video view', () {
    late RecordingEngine engine;
    late VideoMemory memory;
    late SettingsStore settings;
    late VideoPlayerController c;

    PlayRequest req(String name) =>
        PlayRequest.uri(Uri.parse('file:///v/$name.mkv'));

    setUp(() async {
      engine = RecordingEngine(mediaDuration: const Duration(minutes: 10));
      memory = await VideoMemory.open(MemoryVideoMemoryPersistence());
      settings = await memoryStore();
      c = VideoPlayerController(
        engine: engine,
        memory: memory,
        settings: settings,
        onClose: () {},
      );
    });

    tearDown(() async {
      c.dispose();
      await engine.dispose();
    });

    test('VID-037 rotation and aspect are remembered per video', () async {
      await c.open(req('a'));
      await c.setView(const VideoView(rotate: 270, aspect: 21 / 9));
      expect(engine.filterChains.last.rotate, 270);
      expect(engine.filterChains.last.aspectOverride, 21 / 9);
      await c.open(req('b'));
      expect(c.view.isDefault, isTrue);
      expect(engine.filterChains.last.rotate, 0);
      await c.open(req('a'));
      expect(c.view.rotate, 270);
      expect(engine.filterChains.last.rotate, 270);
    });

    test('VID-037 the view survives a JSON round trip', () {
      const v = VideoView(
        fit: VideoFit.stretch,
        rotate: 180,
        flipH: true,
        flipV: true,
        aspect: 2.35,
        zoom: -0.5,
        panX: 0.2,
        panY: -0.3,
      );
      expect(VideoView.fromJson(v.toJson()), v);
      expect(const VideoView().isDefault, isTrue);
      expect(v.isDefault, isFalse);
    });

    test('VID-038 VID-039 a hot device pauses shaders and smooth motion, '
        'then restores them', () async {
      settings.set(RenderSettings.interpolation, true);
      await c.open(req('a'));
      final preset = ShaderPreset(
        id: 'custom:x.glsl',
        shaders: [Uri.parse('file:///s/x.glsl')],
      );
      await c.setShader(preset);
      expect(c.steppedDown, isFalse);
      await c.setThrottled(throttled: true);
      expect(c.steppedDown, isTrue);
      expect(engine.shaderPresets.last, ShaderPreset.none);
      expect(engine.filterChains.last.interpolation, isFalse);
      final other = ShaderPreset(
        id: 'custom:y.glsl',
        shaders: [Uri.parse('file:///s/y.glsl')],
      );
      await c.setShader(other);
      expect(
        engine.shaderPresets.last,
        ShaderPreset.none,
        reason: 'remembered, not applied, while hot',
      );
      await c.open(req('b'));
      expect(engine.filterChains.last.interpolation, isFalse);
      await c.setThrottled(throttled: false);
      expect(engine.shaderPresets.last, other);
      expect(engine.filterChains.last.interpolation, isTrue);
    });

    test('VID-038 nothing to pause: throttling sends no shader', () async {
      await c.open(req('a'));
      await c.setThrottled(throttled: true);
      expect(c.steppedDown, isFalse);
      expect(engine.shaderPresets, isEmpty);
    });

    test('VID-038 setShader sends the preset; none clears it', () async {
      await c.open(req('a'));
      final preset = ShaderPreset(
        id: 'custom:x.glsl',
        shaders: [Uri.parse('file:///s/x.glsl')],
      );
      await c.setShader(preset);
      await c.setShader(ShaderPreset.none);
      expect(engine.shaderPresets, [preset, ShaderPreset.none]);
    });
  });

  group('VID-038 custom shaders', () {
    late Directory dir;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('c1-shaders');
    });

    tearDown(() => dir.delete(recursive: true));

    test('VID-038 lists .glsl files in a file folder, sorted', () async {
      File('${dir.path}/b.glsl').writeAsStringSync('//!HOOK MAIN');
      File('${dir.path}/A.GLSL').writeAsStringSync('//!HOOK MAIN');
      File('${dir.path}/notes.txt').writeAsStringSync('x');
      Directory('${dir.path}/sub.glsl').createSync();
      final list = await listCustomShaders(dir.uri.toString());
      expect(list.map((x) => x.name), ['A.GLSL', 'b.glsl']);
      expect(list.first.id, 'custom:A.GLSL');
      expect(list.first.preset.shaders.single.scheme, 'file');
    });

    test('VID-038 no folder, a missing one or a content URI: none', () async {
      expect(await listCustomShaders(''), isEmpty);
      expect(
        await listCustomShaders(dir.uri.resolve('missing/').toString()),
        isEmpty,
      );
      expect(
        await listCustomShaders('content://com.android.externalstorage/x'),
        isEmpty,
      );
    });
  });
}
