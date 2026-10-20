// Pigeon messages for CaptionStyleFacade on Android (lane C4a, ADR-030,
// SUB-014): the system caption settings from CaptioningManager.
//
//   dart run pigeon --input pigeons/android/caption_api.dart   (from app/)
//
// Pigeon's schema is positional; named bool parameters do not map to Kotlin.
// ignore_for_file: avoid_positional_boolean_parameters

import 'package:pigeon/pigeon.dart';

@ConfigurePigeon(
  PigeonOptions(
    dartOut: 'lib/platform/android/gen/caption_api.pigeon.dart',
    kotlinOut: 'android/app/src/main/kotlin/com/mediahro/mediahro/pigeon/CaptionApi.g.kt',
    kotlinOptions: KotlinOptions(
      // Shares FlutterError and the event-channel classes of StorageApi.g.kt.
      package: 'com.mediahro.mediahro.pigeon',
      includeErrorClass: false,
    ),
    dartPackageName: 'mediahro',
  ),
)
enum CaptionEdgeMsg { none, outline, dropShadow, raised, depressed }

class CaptionStyleMsg {
  CaptionStyleMsg(
    this.enabled,
    this.fontFamily,
    this.scale,
    this.foregroundArgb,
    this.backgroundArgb,
    this.windowArgb,
    this.edge,
    this.edgeArgb,
  );
  bool enabled;
  String? fontFamily;
  double scale;
  int? foregroundArgb;
  int? backgroundArgb;
  int? windowArgb;
  CaptionEdgeMsg edge;
  int? edgeArgb;
}

@HostApi()
abstract class CaptionStyleHostApi {
  CaptionStyleMsg? current();
}

@EventChannelApi(
  kotlinOptions: KotlinEventChannelOptions(includeSharedClasses: false),
)
abstract class CaptionEventsApi {
  CaptionStyleMsg captionStyleChanges();
}
