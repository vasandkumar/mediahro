import 'dart:io';

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mediahro_engine/mediahro_engine.dart';
import 'package:mediahro_engine_example/main.dart';

// The conformance suites live with the engine's own tests so desktop FFI
// runs and device runs share every test body.
import '../../test/conformance/suites.dart';
import '../../test/conformance/support.dart';
import 'corpus_manifest.dart';

/// Engine proof on Android, iOS, macOS and Windows (docs/10 §8 rule 4):
/// the render bridge delivers frames to a Flutter texture, and every
/// conformance suite passes against the platform's libmpv.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final dir = '${Directory.systemTemp.path}/mediahro_corpus';
  ConformanceEnv.current = ConformanceEnv(
    corpusDir: dir,
    manifestJson: corpusManifest.isEmpty ? null : corpusManifest,
    prepare: () => _copyCorpus(dir),
    platformName: Platform.operatingSystem,
  );

  renderBridgeSuite();
  runConformanceSuites();
}

Future<void> _copyCorpus(String dir) async {
  final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
  const prefix = 'assets/corpus/';
  for (final key in manifest.listAssets()) {
    if (!key.startsWith(prefix) || key.endsWith('.keep')) continue;
    final out = File('$dir/${key.substring(prefix.length)}');
    if (out.existsSync()) continue;
    out.parent.createSync(recursive: true);
    final data = await rootBundle.load(key);
    out.writeAsBytesSync(
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
    );
  }
}

void renderBridgeSuite() {
  final skip = ffiSkipReason;
  prepareCorpus();

  testWidgets('AUD-040/041 OS output preference answers truthfully', (
    tester,
  ) async {
    final r = await AudioBridge().prefer(bitPerfect: true, sampleRate: 48000);
    if (Platform.isIOS) {
      expect(r.applied, isTrue, reason: 'AVAudioSession accepts the rate');
      expect(r.sampleRate, isNotNull);
    } else {
      // Emulators and CI desktops have no USB DAC; mpv handles macOS and
      // Windows exclusive modes itself.
      expect(r.bitPerfect, isFalse);
    }
    await AudioBridge().prefer(bitPerfect: false);
  });

  group('VID-030 render bridge', () {
    testWidgets('VID-030 frames reach a Flutter texture', (tester) async {
      final bridge = RenderBridge();
      final engine = MpvEngine(
        EngineRole.video,
        config: MpvEngineConfig(renderBridge: bridge, nullAudio: true),
      );
      final boundary = GlobalKey();
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: RepaintBoundary(
            key: boundary,
            child: ColoredBox(
              color: const Color(0xFF000000),
              child: EnginePlayer(file: '', engine: engine),
            ),
          ),
        ),
      );
      await engine.open(UriSource(Uri.file(corpusPath('mkv_multitrack.mkv'))));
      final id = engine.textureId;
      expect(
        id,
        isNotNull,
        reason:
            'bridge created a texture (surface: ${engine.surfaceError}, '
            'engine: ${engine.current.error})',
      );
      final backend = engine.renderBackend;
      expect(backend, isNot('unknown'));
      // GL readback exists only for the iOS Simulator (the bridge reports
      // it at compile time); every device and macOS renders zero-copy.
      if (backend == 'opengl-readback') {
        expect(
          engine.renderOnSimulator,
          isTrue,
          reason: 'readback outside the iOS Simulator',
        );
      }
      // The info overlay (VID-072) reads the same backend from the state.
      final shown = await waitFor(
        engine,
        (s) => s.video.renderBackend == backend,
        reason: 'renderBackend in VideoStats',
      );
      expect(shown.video.renderBackend, backend);

      var frames = 0;
      for (var i = 0; i < 100 && frames >= 0 && frames < 5; i++) {
        await tester.pump(const Duration(milliseconds: 50));
        frames = (await bridge.stats(id!)).frames;
      }
      // -1: the platform cannot count frames (Android draws in mpv); the
      // composited-pixel check below proves the path.
      if (frames >= 0) {
        expect(frames, greaterThanOrEqualTo(5), reason: 'frames rendered');
      }
      expect(engine.current.error, isNull);

      // The composited texture is not black (testsrc2 is colourful). The
      // compositor may pick up the first shared frame a little later.
      final render =
          boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      var lit = 0;
      for (var attempt = 0; attempt < 30 && lit <= 1000; attempt++) {
        await tester.pump(const Duration(milliseconds: 100));
        final image = await render.toImage();
        final bytes = await image.toByteData();
        image.dispose();
        lit = 0;
        for (var i = 0; i < bytes!.lengthInBytes; i += 4) {
          if (bytes.getUint8(i) > 40 || bytes.getUint8(i + 1) > 40) lit++;
        }
      }
      expect(lit, greaterThan(1000), reason: 'video pixels composited');

      await tester.pumpWidget(const SizedBox.shrink());
      await engine.dispose();
    }, skip: skip != null);
  });
}
