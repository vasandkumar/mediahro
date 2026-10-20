import 'dart:typed_data';
import 'dart:ui' show Rect;

import 'package:meta/meta.dart';

/// OS imaging (docs/05 §5 "OS first", IMG-001/002/003/005/010/015/018,
/// IMG-011 backup exclusion; ADR-037): ImageIO + Vision (I M), ImageDecoder +
/// WallpaperManager + android.media.FaceDetector (A, no ML Kit per ADR-034),
/// WIC + FaceAnalysis (W). Slideshow on an external display uses
/// DisplayFacade (CAST-004), not this facade.
abstract interface class ImagingFacade {
  /// What this device and flavour can do; cached by the caller.
  Future<ImagingSupport> support();

  /// Decodes [uri] (file:// or content:// / ph:// asset URI). [maxEdge]
  /// lets the OS subsample on load; [region] is in full-image pixels.
  /// With [keepHdr] false a gain map / PQ / HLG image is returned as its
  /// SDR rendition in RGBA8888; with true as RGBA F16 extended-linear.
  Future<PlatformImage> decode(
    Uri uri, {
    int? maxEdge,
    Rect? region,
    int frame = 0,
    bool keepHdr = false,
  });

  /// The OS thumbnail cache entry, or null when the OS has none yet.
  Future<PlatformImage?> thumbnail(Uri uri, int size);

  /// [format]: 'heic' or 'avif' (only those in support().encodable).
  /// [exif] is copied into the output when given.
  Future<Uint8List> encode(
    PlatformImage image,
    String format, {
    int quality = 90,
    Uint8List? exif,
  });

  /// Native HDR still view (ADR-022 for images). Returns null when the
  /// current display is SDR. A/I/M: [HdrImageView.viewType] is a registered
  /// platform view taking {'uri': String}; W: the view is a child HWND
  /// positioned with [HdrImageView.setFrame] in logical pixels.
  Future<HdrImageView?> openHdrView(Uri uri);

  Future<void> setWallpaper(Uri image, WallpaperTarget target);

  /// System print dialog with [layout]; false when cancelled.
  Future<bool> printImages(List<Uri> images, PrintLayout layout);

  Future<void> copyImage(Uri image);

  /// Faces in [image] (opt-in, IMG-005). Rects are normalised 0–1.
  Future<List<DetectedFace>> detectFaces(Uri image);

  /// Writes the screensaver configuration the native module reads (M W)
  /// and opens the system screensaver settings when [openSettings].
  Future<void> configureScreensaver(
    ScreensaverConfig config, {
    bool openSettings = false,
  });

  /// A directory the OS never backs up (vault, ADR-008), created if missing.
  Future<Uri> noBackupDirectory(String name);
}

@immutable
final class ImagingSupport {
  const ImagingSupport({
    this.decodable = const {},
    this.encodable = const {},
    this.hdrDisplay = false,
    this.wallpaperTargets = const {},
    this.print = false,
    this.faces = false,
    this.screensaver = false,
  });

  /// Lower-case short names: heic, heif, avif, jxl, …
  final Set<String> decodable;
  final Set<String> encodable;
  final bool hdrDisplay;
  final Set<WallpaperTarget> wallpaperTargets;
  final bool print;
  final bool faces;
  final bool screensaver;
}

enum WallpaperTarget { home, lock, both, desktop }

@immutable
final class PlatformImage {
  const PlatformImage({
    required this.width,
    required this.height,
    required this.pixels,
    this.f16 = false,
    this.frames = 1,
    this.hdr = false,
  });

  final int width;
  final int height;

  /// Row-major, no padding: RGBA8888, or RGBA F16 when [f16].
  final Uint8List pixels;
  final bool f16;
  final int frames;

  /// The source has HDR content (gain map, PQ, HLG).
  final bool hdr;
}

abstract interface class HdrImageView {
  /// Platform view type (A I M); null on W.
  String? get viewType;
  Future<void> setFrame(Rect logicalRect);
  Future<void> close();
}

@immutable
final class PrintLayout {
  const PrintLayout({
    this.perPage = 1,
    this.fill = false,
    this.captions = false,
  });
  final int perPage;
  final bool fill;
  final bool captions;
}

@immutable
final class DetectedFace {
  const DetectedFace(this.bounds, {this.featurePrint});

  /// Normalised 0–1 in the oriented image.
  final Rect bounds;

  /// Platform feature print where the OS has one (Vision); C3 computes its
  /// own descriptor otherwise.
  final Float32List? featurePrint;
}

@immutable
final class ScreensaverConfig {
  const ScreensaverConfig({
    required this.images,
    this.interval = const Duration(seconds: 8),
    this.transition = 'crossfade',
    this.shuffle = true,
    this.kenBurns = false,
  });

  /// Absolute file paths (desktop only), already resolved by C3.
  final List<String> images;
  final Duration interval;
  final String transition;
  final bool shuffle;
  final bool kenBurns;
}
