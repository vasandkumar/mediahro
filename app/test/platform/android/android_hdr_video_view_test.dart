import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediahro/platform/android/android_hdr_video_view.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  test('VID-031 ready waits for the native surface', () async {
    const channel = MethodChannel('mediahro/hdr_video/7');
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'ready');
      return true;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    final surface = AndroidHdrVideoSurface(7);
    addTearDown(surface.dispose);
    expect(surface.handle, 7);
    expect(await surface.ready(), isTrue);
  });

  test('VID-031 a view disposed before its surface reports false', () async {
    const channel = MethodChannel('mediahro/hdr_video/8');
    messenger.setMockMethodCallHandler(channel, (call) async => false);
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    final surface = AndroidHdrVideoSurface(8);
    addTearDown(surface.dispose);
    expect(await surface.ready(), isFalse);
  });

  test('VID-031 surfaceDestroyed from native reaches destroyed', () async {
    final surface = AndroidHdrVideoSurface(9);
    addTearDown(surface.dispose);
    final seen = surface.destroyed.first;
    await messenger.handlePlatformMessage(
      'mediahro/hdr_video/9',
      const StandardMethodCodec().encodeMethodCall(
        const MethodCall('surfaceDestroyed'),
      ),
      (_) {},
    );
    await seen;
  });

  test('VID-031 ready retries until the native view exists', () async {
    const channel = MethodChannel('mediahro/hdr_video/10');
    final surface = AndroidHdrVideoSurface(10);
    addTearDown(surface.dispose);
    final result = surface.ready(retryEvery: const Duration(milliseconds: 10));
    // The view appears after a few attempts.
    await Future<void>.delayed(const Duration(milliseconds: 60));
    messenger.setMockMethodCallHandler(channel, (call) async => true);
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    expect(await result, isTrue);
  });

  test('VID-031 ready gives up when no view is ever created', () async {
    final surface = AndroidHdrVideoSurface(11);
    addTearDown(surface.dispose);
    await expectLater(
      surface.ready(
        timeout: const Duration(milliseconds: 80),
        retryEvery: const Duration(milliseconds: 10),
      ),
      throwsA(isA<TimeoutException>()),
    );
  });

  test('VID-031 the view type is the one the native factory registers', () {
    expect(AndroidHdrVideoView.viewType, 'mediahro/hdr_video');
  });
}
