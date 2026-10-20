// Pigeon messages for DisplayFacade and PipFacade on Android (lane C4a,
// VID-031/036/067/070/071, CAST-004, SYS-011).
//
//   dart run pigeon --input pigeons/android/display_api.dart   (from app/)
//
// Pigeon's schema is positional; named bool parameters do not map to Kotlin.
// ignore_for_file: avoid_positional_boolean_parameters

import 'package:pigeon/pigeon.dart';

@ConfigurePigeon(
  PigeonOptions(
    dartOut: 'lib/platform/android/gen/display_api.pigeon.dart',
    kotlinOut: 'android/app/src/main/kotlin/com/mediahro/mediahro/pigeon/DisplayApi.g.kt',
    kotlinOptions: KotlinOptions(
      // Shares FlutterError and the event-channel classes of StorageApi.g.kt.
      package: 'com.mediahro.mediahro.pigeon',
      includeErrorClass: false,
    ),
    dartPackageName: 'mediahro',
  ),
)
enum OrientationLockMsg { auto, landscape, portrait, followVideo }

class DisplayInfoMsg {
  DisplayInfoMsg(
    this.id,
    this.name,
    this.refreshRate,
    this.supportedRefreshRates,
    this.hdr,
    this.peakNits,
    this.isExternal,
  );
  String id;
  String name;
  double refreshRate;
  List<double> supportedRefreshRates;
  bool hdr;
  double? peakNits;
  bool isExternal;
}

class DisplayListMsg {
  DisplayListMsg(this.displays);
  List<DisplayInfoMsg> displays;
}

class PipStateMsg {
  PipStateMsg(this.active);
  bool active;
}

@HostApi()
abstract class DisplayHostApi {
  List<DisplayInfoMsg> displays();
  bool matchFrameRate(String displayId, double fps);
  void restoreDisplayMode(String displayId);
  void keepScreenOn(bool on);

  /// 0–1, or null to follow the system brightness again.
  void setWindowBrightness(double? value);
  void setOrientationLock(OrientationLockMsg lock);
}

@HostApi()
abstract class PipHostApi {
  bool isSupported();
  bool enter(double aspectRatio);
  void exit();
  void setAutoEnter(bool enabled);

  /// ADR-028: the video's shape, for auto-PiP and followVideo.
  void setAspectRatio(double aspectRatio);
}

@EventChannelApi(
  kotlinOptions: KotlinEventChannelOptions(includeSharedClasses: false),
)
abstract class DisplayEventsApi {
  DisplayListMsg displayChanges();
  PipStateMsg pipStates();
}
