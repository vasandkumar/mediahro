import 'package:mediahro/platform/android/gen/display_api.pigeon.dart';
import 'package:mediahro/platform/android/gen/presentation_api.pigeon.dart';
import 'package:mediahro/platform/android/presentation_codec.dart';
import 'package:mediahro/platform/display.dart';

/// [DisplayFacade] on Android (VID-031/036/070/071, CAST-004): displays,
/// refresh-rate matching through `preferredDisplayModeId`, keep-screen-on,
/// window brightness and orientation locks (`DisplayModule.kt`).
///
/// [OrientationLock.followVideo] locks to the video's shape from
/// [AndroidPip.setAspectRatio] (ADR-028) or [AndroidPip.enter], landscape
/// until either is called.
final class AndroidDisplay implements DisplayFacade {
  AndroidDisplay({
    DisplayHostApi? api,
    Stream<DisplayListMsg> Function()? events,
    PresentationHostApi? presentation,
  }) : _api = api ?? DisplayHostApi(),
       _events = events ?? displayChanges,
       _presentation = presentation ?? PresentationHostApi();

  final DisplayHostApi _api;
  final PresentationHostApi _presentation;
  final Stream<DisplayListMsg> Function() _events;

  @override
  Future<List<DisplayInfo>> displays() async =>
      (await _api.displays()).map(_info).toList();

  @override
  late final Stream<List<DisplayInfo>> changes = _events().map(
    (l) => l.displays.map(_info).toList(),
  );

  @override
  Future<bool> matchFrameRate(String displayId, double fps) =>
      _api.matchFrameRate(displayId, fps);

  @override
  Future<void> restoreDisplayMode(String displayId) =>
      _api.restoreDisplayMode(displayId);

  @override
  Future<void> keepScreenOn({required bool on}) => _api.keepScreenOn(on);

  @override
  Future<void> setWindowBrightness(double? value) =>
      _api.setWindowBrightness(value?.clamp(0, 1).toDouble());

  @override
  Future<void> setOrientationLock(OrientationLock lock) =>
      _api.setOrientationLock(OrientationLockMsg.values[lock.index]);

  /// ADR-044: an `android.app.Presentation` on an external display hosting a
  /// second engine that shows only the frames [present] sends
  /// (`PresentationModule.kt`, `presentationMain`). It closes by itself when
  /// the display is removed; null for the built-in screen or a gone display.
  @override
  Future<PresentationHandle?> openPresentation(String displayId) async {
    final id = await _presentation.open(displayId);
    return id == null ? null : PresentationHandle(id: id, displayId: displayId);
  }

  @override
  Future<void> closePresentation(PresentationHandle handle) =>
      _presentation.close(handle.id);

  @override
  Future<void> present(PresentationHandle handle, PresentationFrame frame) =>
      _presentation.present(handle.id, PresentationFrameCodec.toMap(frame));

  static DisplayInfo _info(DisplayInfoMsg d) => DisplayInfo(
    id: d.id,
    name: d.name,
    refreshRate: d.refreshRate,
    supportedRefreshRates: d.supportedRefreshRates,
    hdr: d.hdr,
    peakNits: d.peakNits,
    isExternal: d.isExternal,
  );
}

/// [PipFacade] on Android (VID-067): system picture-in-picture whose
/// controls come from the Media3 session (`PipModule.kt`).
final class AndroidPip implements PipFacade {
  AndroidPip({PipHostApi? api, Stream<PipStateMsg> Function()? events})
    : _api = api ?? PipHostApi(),
      _events = events ?? pipStates;

  final PipHostApi _api;
  final Stream<PipStateMsg> Function() _events;

  @override
  Future<bool> isSupported() => _api.isSupported();

  @override
  Future<bool> enter({required double aspectRatio}) => _api.enter(aspectRatio);

  @override
  Future<void> exit() => _api.exit();

  @override
  Future<void> setAutoEnter({required bool enabled}) =>
      _api.setAutoEnter(enabled);

  @override
  Future<void> setAspectRatio(double aspectRatio) =>
      _api.setAspectRatio(aspectRatio);

  @override
  late final Stream<bool> isActive = _events().map((s) => s.active);
}
