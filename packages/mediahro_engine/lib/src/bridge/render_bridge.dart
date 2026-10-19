import 'package:flutter/services.dart';

/// Native half of the engine (docs/05 §4.3): registers the platform texture
/// that `mpv_render_context` renders into and hands its id to Dart.
///
/// This file and the plugin's `android/`, `ios/`, `macos/`, `windows/`
/// folders are the engine's platform module (ADR-011); feature code never
/// reaches the channel directly.
final class RenderBridge {
  RenderBridge({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('com.mediahro.engine/bridge');

  final MethodChannel _channel;

  /// Platform description from the native side; used by the M0 smoke test to
  /// prove the plugin is linked on every platform.
  Future<String> bridgeInfo() async =>
      await _channel.invokeMethod<String>('bridgeInfo') ?? 'unknown';
}
