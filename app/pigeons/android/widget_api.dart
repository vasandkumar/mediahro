// Pigeon messages for HomeWidgetsFacade on Android (lane C4a, MUS-012).
//
//   dart run pigeon --input pigeons/android/widget_api.dart   (from app/)
//
// Pigeon's schema is positional; named bool parameters do not map to Kotlin.
// ignore_for_file: avoid_positional_boolean_parameters

import 'package:pigeon/pigeon.dart';

@ConfigurePigeon(
  PigeonOptions(
    dartOut: 'lib/platform/android/gen/widget_api.pigeon.dart',
    kotlinOut: 'android/app/src/main/kotlin/com/mediahro/mediahro/pigeon/WidgetApi.g.kt',
    kotlinOptions: KotlinOptions(
      // Shares FlutterError with StorageApi.g.kt.
      package: 'com.mediahro.mediahro.pigeon',
      includeErrorClass: false,
    ),
    dartPackageName: 'mediahro',
  ),
)
class WidgetStateMsg {
  WidgetStateMsg(this.title, this.artist, this.artwork, this.playing);
  String title;
  String? artist;

  /// Encoded PNG/JPEG, already downscaled by the caller.
  Uint8List? artwork;
  bool playing;
}

@HostApi()
abstract class HomeWidgetsHostApi {
  /// Null: nothing playing.
  void update(WidgetStateMsg? state);
}
