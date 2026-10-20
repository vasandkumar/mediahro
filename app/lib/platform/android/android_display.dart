import 'package:mediahro/platform/android/gen/display_api.pigeon.dart';
import 'package:mediahro/platform/display.dart';

/// [DisplayFacade] on Android (VID-031/036/070/071, CAST-004): displays,
/// refresh-rate matching through `preferredDisplayModeId`, keep-screen-on,
/// window brightness and orientation locks (`DisplayModule.kt`).
///
/// [OrientationLock.followVideo] locks to the shape of the video last given
/// to [AndroidPip.enter] (landscape until then).
final class AndroidDisplay implements DisplayFacade {
  AndroidDisplay({
    DisplayHostApi? api,
    Stream<DisplayListMsg> Function()? events,
  }) : _api = api ?? DisplayHostApi(),
       _events = events ?? displayChanges;

  final DisplayHostApi _api;
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
  late final Stream<bool> isActive = _events().map((s) => s.active);
}
