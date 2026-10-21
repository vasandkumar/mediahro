// Pigeon messages for the external-display presentation on Android (lane C4a,
// ADR-044 amendment 1, IMG-012, CAST-004): an android.app.Presentation hosting a
// spawned Flutter engine that shows what the app sends.
//
//   dart run pigeon --input pigeons/android/presentation_api.dart   (from app/)

import 'package:pigeon/pigeon.dart';

@ConfigurePigeon(
  PigeonOptions(
    dartOut: 'lib/platform/android/gen/presentation_api.pigeon.dart',
    kotlinOut: 'android/app/src/main/kotlin/com/mediahro/mediahro/pigeon/PresentationApi.g.kt',
    kotlinOptions: KotlinOptions(
      // Shares FlutterError and the event-channel classes of StorageApi.g.kt.
      package: 'com.mediahro.mediahro.pigeon',
      includeErrorClass: false,
    ),
    dartPackageName: 'mediahro',
  ),
)
@HostApi()
abstract class PresentationHostApi {
  /// Opens a presentation on the external display (a DisplayInfo id); returns
  /// its id, or null when that display is not external or is gone.
  @async
  int? open(String displayId);

  @async
  void close(int id);

  /// [frame] is `PresentationFrameCodec.toMap` of a frame.
  @async
  void present(int id, Map<String, Object?> frame);
}
