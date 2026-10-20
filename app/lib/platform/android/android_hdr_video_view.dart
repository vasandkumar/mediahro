import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

/// The native HDR video view on Android (VID-031, ADR-022): a `SurfaceView`
/// platform view whose `Surface` the engine draws into, so an HDR display
/// shows HDR instead of the 8-bit Flutter texture. The player (C1) shows it
/// when the display is HDR-capable and the item is HDR, and keeps the
/// `Texture` path otherwise.
///
/// Flow: pick a `handle` (any unique int), build [AndroidHdrVideoView], wait
/// for [AndroidHdrVideoSurface.ready], then call
/// `engine.setVideoTarget(VideoTarget.platformView(handle))`. When
/// [AndroidHdrVideoSurface.destroyed] fires (the app went to the background)
/// the engine detaches; call `ready` again after coming back.
class AndroidHdrVideoSurface {
  AndroidHdrVideoSurface(this.handle, {BinaryMessenger? messenger})
    : _channel = MethodChannel(
        'mediahro/hdr_video/$handle',
        const StandardMethodCodec(),
        messenger,
      ) {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'surfaceDestroyed') _destroyed.add(null);
      return null;
    });
  }

  /// The id passed as `VideoTarget.platformView(handle)`.
  final int handle;

  final MethodChannel _channel;
  final _destroyed = StreamController<void>.broadcast();

  /// Completes true once the view's surface exists; false if the view was
  /// disposed first.
  Future<bool> ready() async => (await _channel.invokeMethod<bool>('ready'))!;

  /// The surface went away; the engine must detach.
  Stream<void> get destroyed => _destroyed.stream;

  void dispose() {
    _channel.setMethodCallHandler(null);
    unawaited(_destroyed.close());
  }
}

/// Places the native HDR video view; use with [AndroidHdrVideoSurface].
class AndroidHdrVideoView extends StatelessWidget {
  const AndroidHdrVideoView({required this.handle, super.key});

  static const viewType = 'mediahro/hdr_video';

  final int handle;

  @override
  Widget build(BuildContext context) => PlatformViewLink(
    viewType: viewType,
    surfaceFactory: (context, controller) => AndroidViewSurface(
      controller: controller as AndroidViewController,
      gestureRecognizers: const <Factory<OneSequenceGestureRecognizer>>{},
      hitTestBehavior: PlatformViewHitTestBehavior.transparent,
    ),
    onCreatePlatformView: (params) {
      // Hybrid composition: a SurfaceView cannot live in a texture layer.
      final controller = PlatformViewsService.initExpensiveAndroidView(
        id: params.id,
        viewType: viewType,
        layoutDirection: TextDirection.ltr,
        creationParams: <String, Object?>{'handle': handle},
        creationParamsCodec: const StandardMessageCodec(),
        onFocus: () => params.onFocusChanged(true),
      )..addOnPlatformViewCreatedListener(params.onPlatformViewCreated);
      unawaited(controller.create());
      return controller;
    },
  );
}
