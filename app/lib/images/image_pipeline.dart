import 'dart:typed_data';

import 'package:mediahro_ffi/mediahro_ffi.dart';
import 'package:meta/meta.dart';

/// Image engine contract (docs/05 §5). Decoder order: OS first (ImageIO,
/// `ImageDecoder`, WIC) → libvips → libjxl / libavif / LibRaw / small
/// decoders. All work runs on the image isolate pool, never the UI isolate.
abstract interface class ImagePipeline {
  /// Thumbnail of the longest edge [size] (256/512 px), served from the OS
  /// cache, then the disk LRU, then generated (IMG-003).
  Future<DecodedImage> thumbnail(
    ImageSource src,
    int size, {
    ThumbnailPriority priority = ThumbnailPriority.visible,
  });

  /// Decodes [region] (full image when null) at [scale] (1.0 = 1:1), for
  /// tiled pyramid rendering of 100 MP+ images (IMG-004).
  Future<DecodedImage> decode(
    ImageSource src, {
    ImageRegion? region,
    double scale = 1,
    int frame = 0,
  });

  Future<ImageInfo> info(ImageSource src);

  /// EXIF / IPTC / XMP / ICC (IMG-006). Never via Exiv2 (ADR-002).
  Future<ImageMetadata> metadata(ImageSource src);

  /// Atomic metadata write (temp + rename), or XMP sidecar for RAW.
  Future<void> writeMetadata(ImageSource src, ImageMetadataEdit edit);

  Future<Uint8List> encode(DecodedImage image, EncodeOptions options);

  /// Applies a non-destructive op stack and writes the result (IMG-009/010).
  Future<void> export(
    ImageSource src,
    List<EditOp> ops,
    Uri destination,
    EncodeOptions options,
  );

  /// Cancels queued work for sources no longer near the viewport.
  void cancelBelow(ThumbnailPriority priority);
}

enum ThumbnailPriority { prefetch, nearby, visible }

@immutable
final class ImageSource {
  const ImageSource(this.file, {this.mtime, this.orientationHint});

  final VirtualFile file;
  final DateTime? mtime;
  final int? orientationHint;

  /// Disk LRU key component (path, mtime, size, orientation), docs/05 §5.
  Uri get uri => file.uri;
}

@immutable
final class ImageRegion {
  const ImageRegion(this.left, this.top, this.width, this.height);

  final int left;
  final int top;
  final int width;
  final int height;
}

enum PixelFormat { rgba8888, bgra8888, rgbaF16 }

enum ImageDynamicRange { sdr, hdrGainMap, hdrPq, hdrHlg }

@immutable
final class DecodedImage {
  const DecodedImage({
    required this.width,
    required this.height,
    required this.pixels,
    this.format = PixelFormat.rgba8888,
    this.range = ImageDynamicRange.sdr,
  });

  final int width;
  final int height;
  final Uint8List pixels;
  final PixelFormat format;
  final ImageDynamicRange range;
}

@immutable
final class ImageInfo {
  const ImageInfo({
    required this.width,
    required this.height,
    required this.format,
    this.frames = 1,
    this.pages = 1,
    this.range = ImageDynamicRange.sdr,
    this.isLivePhoto = false,
    this.isMotionPhoto = false,
    this.isPanorama = false,
  });

  final int width;
  final int height;

  /// Lower-case short name: jpeg, heic, jxl, avif, cr3, …
  final String format;
  final int frames;
  final int pages;
  final ImageDynamicRange range;
  final bool isLivePhoto;
  final bool isMotionPhoto;
  final bool isPanorama;
}

@immutable
final class ImageMetadata {
  const ImageMetadata({
    this.captured,
    this.latitude,
    this.longitude,
    this.title,
    this.description,
    this.keywords = const [],
    this.rating,
    this.cameraMake,
    this.cameraModel,
    this.lens,
    this.exif = const {},
    this.iccProfileName,
  });

  final DateTime? captured;
  final double? latitude;
  final double? longitude;
  final String? title;
  final String? description;
  final List<String> keywords;
  final int? rating;
  final String? cameraMake;
  final String? cameraModel;
  final String? lens;

  /// Full tag dump for the info sheet, tag name → display value.
  final Map<String, String> exif;
  final String? iccProfileName;
}

@immutable
final class ImageMetadataEdit {
  const ImageMetadataEdit({
    this.captured,
    this.location,
    this.clearLocation = false,
    this.title,
    this.description,
    this.keywords,
    this.rating,
  });

  final DateTime? captured;
  final (double lat, double lon)? location;
  final bool clearLocation;
  final String? title;
  final String? description;
  final List<String>? keywords;
  final int? rating;
}

enum EncodeFormat { jpeg, png, webp, avif, jxl, heic }

@immutable
final class EncodeOptions {
  const EncodeOptions({
    required this.format,
    this.quality = 90,
    this.maxEdge,
    this.stripMetadata = false,
  });

  final EncodeFormat format;
  final int quality;
  final int? maxEdge;
  final bool stripMetadata;
}

/// Non-destructive edit operations (IMG-009).
@immutable
sealed class EditOp {
  const EditOp();
}

final class CropOp extends EditOp {
  const CropOp(this.region);
  final ImageRegion region;
}

final class RotateOp extends EditOp {
  const RotateOp(this.degrees);
  final double degrees;
}

final class FlipOp extends EditOp {
  const FlipOp({this.horizontal = false, this.vertical = false});
  final bool horizontal;
  final bool vertical;
}

enum AdjustKind {
  exposure,
  contrast,
  highlights,
  shadows,
  whites,
  blacks,
  saturation,
  vibrance,
  temperature,
  tint,
  sharpen,
  vignette,
}

final class AdjustOp extends EditOp {
  const AdjustOp(this.kind, this.amount);
  final AdjustKind kind;

  /// −1.0 … 1.0.
  final double amount;
}

final class CurvesOp extends EditOp {
  const CurvesOp(this.points);

  /// Control points in 0–1 space, x ascending.
  final List<(double x, double y)> points;
}

final class BlurRegionOp extends EditOp {
  const BlurRegionOp(this.region, {this.radius = 24});
  final ImageRegion region;
  final double radius;
}

final class StrokeOp extends EditOp {
  const StrokeOp(this.points, {required this.colorArgb, required this.width});
  final List<(double x, double y)> points;
  final int colorArgb;
  final double width;
}
