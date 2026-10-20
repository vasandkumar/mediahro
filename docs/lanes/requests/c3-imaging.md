# C3 ADR request: `ImagingFacade` (2026-10-20, updated for ADR-034)

Lane C3 (Photos). Proposal for the orchestrator to decide as an ADR. Android is the first target (owner, 2026-10-20); the other columns say what C4b/C4c would implement later.

## Why

The frozen facades (ADR-025) have no member for these doc 04 rows, which C3 needs from C4a/b/c:

| Need | Doc 04 / docs/05 | A | I | M | W |
|---|---|---|---|---|---|
| OS decode (HEIC/HEIF incl. sequences, gain maps; AVIF/JXL where the OS has them) | IMG-001, IMG-002, docs/05 §5 "OS first" | `ImageDecoder` | ImageIO | ImageIO | WIC |
| OS thumbnail cache first | IMG-003 | `ContentResolver.loadThumbnail` | PhotoKit / QuickLook thumbnails | QLThumbnailGenerator | `IShellItemImageFactory` |
| OS encode (HEIC "where OS can encode", also AVIF if the OS has it) | IMG-010, IMG-015 | `HeifWriter` | ImageIO | ImageIO | WIC (HEVC ext.) |
| HDR image view (ADR-022 for stills) | IMG-002 | `ImageView`/`SurfaceView` with `COLOR_MODE_HDR` | EDR `CALayer`/`UIImageView` with `preferredImageDynamicRange` | same (NSImageView) | child HWND, FP16 swap chain |
| Set wallpaper / lock screen (A), desktop (M W) | IMG-015 | `WallpaperManager` | — (not allowed) | `NSWorkspace.setDesktopImageURL` | `IDesktopWallpaper` |
| Print with layout | IMG-015 | `PrintHelper` | `UIPrintInteractionController` | `NSPrintOperation` | `PrintManager` |
| Copy image to clipboard | IMG-015 | `ClipData` + content URI | `UIPasteboard` | `NSPasteboard` | `Clipboard` (bitmap + file) |
| On-device face detection (+ feature print where available) | IMG-005 people | `android.media.FaceDetector` (platform, no ML Kit per ADR-034) | Vision | Vision | `Windows.Media.FaceAnalysis` |
| Screensaver module from chosen albums | IMG-018 (M W) | — (1.1 TV) | — | `.saver` bundle (ScreenSaverView) | `.scr` |
| Vault directory excluded from backup | IMG-011 / PRIV-007 (ADR-008) | `noBackupFilesDir` | `isExcludedFromBackup` | `isExcludedFromBackup` / TM exclusion | not backed up (LocalState) |
| Slideshow on an external display | IMG-012 | `Presentation` | external `UIScene` | second window | second window |

(The external-display row may already be planned for CAST-004 by C4d; if so C3 reuses that and the member is not needed here.)

## Proposed file `app/lib/platform/imaging.dart` (+ `imagingProvider` in platform_facades.dart)

```dart
import 'dart:typed_data';
import 'dart:ui' show Rect;

import 'package:meta/meta.dart';

/// OS imaging (docs/05 §5 "OS first", IMG-001/002/003/005/010/015/018,
/// IMG-011 backup exclusion): ImageIO + Vision (I M), ImageDecoder +
/// WallpaperManager + ML Kit (A), WIC + FaceAnalysis (W).
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
  const PrintLayout({this.perPage = 1, this.fill = false, this.captions = false});
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
```

`PlatformCapabilityUnavailable` stays the signal for "not on this device"
(e.g. setWallpaper on iOS, configureScreensaver on A/I).

## C3 meanwhile

C3 builds against a fake `ImagingFacade` in its own tests (overriding `imagingProvider`) as soon as the file exists; until then it defines a private
adapter in `app/lib/images/` that the real provider replaces. Cells that need the native half stay ☐ until C4a/b/c land.

## Notes for the decision (2026-10-20)

- **Android HEIC until the facade lands:** C3 decodes HEIC/HEIF through `dart:ui` `instantiateImageCodec`, which on Android hands formats Skia lacks to the platform `ImageDecoder`. That covers SDR display and thumbnails without native code; gain maps, sequences beyond the first frame, region decode and the OS thumbnail cache still need `ImagingFacade.decode` / `thumbnail`.
- **AVIF encode (IMG-010) has no encoder on Android:** the pinned mediahro-deps ships libavif + dav1d (decode only) and no AV1 encoder; Android has no OS AVIF encoder. Request for B4a: build libaom (BSD-2-Clause) or rav1e (BSD-2-Clause) into libavif. Until then the AVIF convert test is skipped with that blocker.
- **Other native libraries C3 opens on Android** (orchestrator change, `app/android/gradle.properties`): `mediahroNativeLibs=libvips.so,libjxl.so,libjxl_threads.so,libavif.so,libraw.so` so their DT_NEEDED closure is packaged.
