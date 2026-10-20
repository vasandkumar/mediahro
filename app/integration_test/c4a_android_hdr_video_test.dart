import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mediahro/platform/android/android_hdr_video_view.dart';
import 'package:mediahro_engine/mediahro_engine.dart';

/// Lane C4a: the native HDR video view (VID-031, ADR-022) on an Android
/// device: the SurfaceView platform view comes up, registers its Surface
/// with the engine under the handle, and takes it away when it is removed.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final android = Platform.isAndroid;

  testWidgets('VID-031 the HDR view registers its surface with the engine', (
    tester,
  ) async {
    const handle = 4242;
    final surface = AndroidHdrVideoSurface(handle);
    addTearDown(surface.dispose);
    final bridge = RenderBridge();

    await tester.pumpWidget(
      const MaterialApp(
        home: SizedBox.expand(child: AndroidHdrVideoView(handle: handle)),
      ),
    );
    final ready = await tester.runAsync(
      () => surface.ready().timeout(const Duration(seconds: 15)),
    );
    expect(ready, isTrue);

    // The engine plugin finds the surface by handle (a JNI reference for mpv).
    final ref = await tester.runAsync(() => bridge.viewSurface(handle));
    expect(ref, isNotNull);
    await tester.runAsync(() => bridge.releaseViewSurface(ref!));

    // Removing the view unregisters it.
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await tester.pump(const Duration(milliseconds: 500));
    final gone = await tester.runAsync(() => bridge.viewSurface(handle));
    expect(gone, isNull);
  }, skip: !android);

  testWidgets('VID-031 an unknown handle has no surface', (tester) async {
    final ref = await tester.runAsync(() => RenderBridge().viewSurface(999999));
    expect(ref, isNull);
  }, skip: !android);
}
