import 'dart:async';

import 'package:flutter/services.dart';
import 'package:meta/meta.dart';

/// A video surface created by the native render bridge.
@immutable
final class RenderSurface {
  const RenderSurface({
    required this.textureId,
    this.androidSurface,
    this.backend = 'unknown',
  });

  /// Flutter external texture id for the `Texture` widget.
  final int textureId;

  /// Android only: JNI global reference to the `android.view.Surface` that
  /// mpv draws into (`wid`). Null on platforms where the bridge owns an
  /// `mpv_render_context`.
  final int? androidSurface;

  /// Render path, shown in the stats overlay (VID-072), e.g. `d3d11`,
  /// `opengl-iosurface`, `android-surface`.
  final String backend;
}

/// Native half of the engine (docs/05 §4.3): registers the platform texture
/// that mpv renders into and hands its id to Dart.
///
/// This file and the plugin's `android/`, `ios/`, `macos/`, `windows/`
/// folders are the engine's platform module (ADR-011); feature code never
/// reaches the channel directly.
///
/// - Windows: D3D11 render API into a shared `ID3D11Texture2D`, registered as
///   a `FlutterDesktopGpuSurfaceDescriptor` (DXGI shared handle).
/// - iOS/macOS: OpenGL (ES) render API into an IOSurface-backed
///   `CVPixelBuffer` registered as a `FlutterTexture`.
/// - Android: a `SurfaceProducer` whose `Surface` mpv draws into with
///   `vo=gpu-next` (MediaCodec frames stay on the GPU).
final class RenderBridge {
  RenderBridge({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('com.mediahro.engine/bridge') {
    _channel.setMethodCallHandler(_onNativeCall);
  }

  final MethodChannel _channel;
  final _surfaceChanges = StreamController<(int, int?)>.broadcast();

  /// `(textureId, androidSurface)` when Android recreates the surface (app
  /// returned from background); the engine re-attaches mpv to it.
  Stream<(int, int?)> get surfaceChanges => _surfaceChanges.stream;

  Future<Object?> _onNativeCall(MethodCall call) async {
    if (call.method == 'surfaceChanged') {
      final args = call.arguments as Map<Object?, Object?>;
      _surfaceChanges.add((
        args['textureId']! as int,
        args['androidSurface'] as int?,
      ));
    }
    return null;
  }

  /// Platform description from the native side; used by the M0 smoke test to
  /// prove the plugin is linked on every platform.
  Future<String> bridgeInfo() async =>
      await _channel.invokeMethod<String>('bridgeInfo') ?? 'unknown';

  /// Creates a video surface for the core at [mpvHandle] (an `mpv_handle*`).
  ///
  /// [libmpvPath] is the library the Dart side opened, so the native side
  /// resolves the render API from the same binary.
  Future<RenderSurface> create({
    required int mpvHandle,
    required String libmpvPath,
  }) async {
    final r = await _channel.invokeMapMethod<String, Object?>('create', {
      'handle': mpvHandle,
      'libmpv': libmpvPath,
    });
    if (r == null) throw StateError('render bridge returned no surface');
    return RenderSurface(
      textureId: r['textureId']! as int,
      androidSurface: r['androidSurface'] as int?,
      backend: r['backend'] as String? ?? 'unknown',
    );
  }

  /// Sets the render size in pixels (the video's display size).
  Future<void> resize(int textureId, int width, int height) =>
      _channel.invokeMethod<void>('resize', {
        'textureId': textureId,
        'width': width,
        'height': height,
      });

  /// Frames rendered into [textureId] and the render path (tests, VID-072).
  Future<({int frames, String backend})> stats(int textureId) async {
    final r = await _channel.invokeMapMethod<String, Object?>('stats', {
      'textureId': textureId,
    });
    return (
      frames: (r?['frames'] as int?) ?? 0,
      backend: (r?['backend'] as String?) ?? 'unknown',
    );
  }

  /// Releases the surface. Must be called before the mpv core is destroyed.
  Future<void> dispose(int textureId) =>
      _channel.invokeMethod<void>('dispose', {'textureId': textureId});
}
