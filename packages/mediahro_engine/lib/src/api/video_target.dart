import 'package:meta/meta.dart';

/// Where the engine draws video (VID-030, VID-031).
@immutable
sealed class VideoTarget {
  const VideoTarget();

  /// The Flutter external texture (`PlaybackEngine.textureId`); SDR, with
  /// HDR tone mapped. The default.
  const factory VideoTarget.texture() = TextureVideoTarget;

  /// A native platform view that shows HDR natively on HDR displays
  /// (ADR-022).
  ///
  /// [handle] is an opaque id, not a native pointer: the platform view (lane
  /// C4) registers its drawing surface with the engine plugin under this id
  /// before it is passed here: on Android the view's `Surface`
  /// (`MediahroEngineViews.register(handle, surface)`), on Apple its
  /// native view (once ADR-022's Apple view exists; until then
  /// `notSupported`), on Windows its `HWND`. The engine looks the
  /// surface up by id; an unknown id is an `invalidArgument` error.
  const factory VideoTarget.platformView(int handle) = PlatformViewVideoTarget;
}

final class TextureVideoTarget extends VideoTarget {
  const TextureVideoTarget();

  @override
  bool operator ==(Object other) => other is TextureVideoTarget;

  @override
  int get hashCode => (TextureVideoTarget).hashCode;
}

final class PlatformViewVideoTarget extends VideoTarget {
  const PlatformViewVideoTarget(this.handle);

  final int handle;

  @override
  bool operator ==(Object other) =>
      other is PlatformViewVideoTarget && other.handle == handle;

  @override
  int get hashCode => handle.hashCode;
}
