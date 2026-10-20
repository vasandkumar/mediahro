// Pigeon messages for ImagingFacade on Android (lane C4a, ADR-037, IMG-001/
// 002/003/005/010/011/015). ImageDecoder, ContentResolver.loadThumbnail,
// HeifWriter, WallpaperManager, PrintManager, ClipboardManager and
// android.media.FaceDetector (no ML Kit, ADR-034).
//
//   dart run pigeon --input pigeons/android/imaging_api.dart   (from app/)
// Pigeon's schema is positional; named bool parameters do not map to Kotlin.
// ignore_for_file: avoid_positional_boolean_parameters

import 'package:pigeon/pigeon.dart';

@ConfigurePigeon(
  PigeonOptions(
    dartOut: 'lib/platform/android/gen/imaging_api.pigeon.dart',
    kotlinOut:
        'android/app/src/main/kotlin/com/mediahro/mediahro/pigeon/ImagingApi.g.kt',
    kotlinOptions: KotlinOptions(
      // Shares FlutterError with StorageApi.g.kt.
      package: 'com.mediahro.mediahro.pigeon',
      includeErrorClass: false,
    ),
    dartPackageName: 'mediahro',
  ),
)
enum WallpaperTargetMsg { home, lock, both }

class ImagingSupportMsg {
  ImagingSupportMsg(
    this.decodable,
    this.encodable,
    this.hdrDisplay,
    this.wallpaperTargets,
    this.print,
    this.faces,
  );
  List<String> decodable;
  List<String> encodable;
  bool hdrDisplay;
  List<WallpaperTargetMsg> wallpaperTargets;
  bool print;
  bool faces;
}

/// A region in full-image pixels; all four set or none.
class ImageRegionMsg {
  ImageRegionMsg(this.left, this.top, this.right, this.bottom);
  double left;
  double top;
  double right;
  double bottom;
}

class DecodeRequestMsg {
  DecodeRequestMsg(
    this.uri,
    this.maxEdge,
    this.region,
    this.frame,
    this.keepHdr,
  );
  String uri;
  int? maxEdge;
  ImageRegionMsg? region;
  int frame;
  bool keepHdr;
}

class PlatformImageMsg {
  PlatformImageMsg(
    this.width,
    this.height,
    this.pixels,
    this.f16,
    this.frames,
    this.hdr,
  );
  int width;
  int height;
  Uint8List pixels;
  bool f16;
  int frames;
  bool hdr;
}

class PrintLayoutMsg {
  PrintLayoutMsg(this.perPage, this.fill, this.captions);
  int perPage;
  bool fill;
  bool captions;
}

/// Normalised 0–1 in the oriented image.
class DetectedFaceMsg {
  DetectedFaceMsg(this.left, this.top, this.right, this.bottom);
  double left;
  double top;
  double right;
  double bottom;
}

@HostApi()
abstract class ImagingHostApi {
  ImagingSupportMsg support();

  @async
  PlatformImageMsg decode(DecodeRequestMsg request);

  @async
  PlatformImageMsg? thumbnail(String uri, int size);

  @async
  Uint8List encode(
    PlatformImageMsg image,
    String format,
    int quality,
    Uint8List? exif,
  );

  /// The platform-view type registered for the HDR still view
  /// (creation params: {'uri': String}), or null on an SDR display or when
  /// the image is unreadable. Opening switches the window to HDR colour mode
  /// until [closeHdrView].
  @async
  String? openHdrView(String uri);

  void closeHdrView();

  @async
  void setWallpaper(String uri, WallpaperTargetMsg target);

  @async
  bool printImages(List<String> images, PrintLayoutMsg layout);

  @async
  void copyImage(String uri);

  @async
  List<DetectedFaceMsg> detectFaces(String uri);

  String noBackupDirectory(String name);
}
