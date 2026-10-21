import 'package:mediahro/images/metadata/xmp.dart';
import 'package:meta/meta.dart';

/// What a photo's GPano XMP says about the sphere it was cut from (IMG-001).
/// The numbers are the ones Google's Photo Sphere spec defines; any may be
/// missing, and a missing crop means the picture is the whole sphere.
@immutable
final class PanoramaMeta {
  const PanoramaMeta({
    this.projection,
    this.fullWidth,
    this.fullHeight,
    this.croppedWidth,
    this.croppedHeight,
    this.croppedLeft,
    this.croppedTop,
    this.initialHeading,
    this.initialPitch,
    this.initialFov,
  });

  /// `GPano:ProjectionType`, lower-cased (usually `equirectangular`).
  final String? projection;

  /// `FullPanoWidthPixels` and `FullPanoHeightPixels`: the whole sphere.
  final int? fullWidth;
  final int? fullHeight;

  /// `CroppedArea*Pixels`: where this picture sits inside the whole sphere.
  final int? croppedWidth;
  final int? croppedHeight;
  final int? croppedLeft;
  final int? croppedTop;

  /// `InitialViewHeadingDegrees` (0 to 360 from the left edge of the whole
  /// sphere, 180 is its middle), `InitialViewPitchDegrees` (up is positive)
  /// and `InitialViewHorizontalFOVDegrees`.
  final double? initialHeading;
  final double? initialPitch;
  final double? initialFov;

  static PanoramaMeta? fromXmp(XmpPacket x) {
    int? intOf(String p) => int.tryParse(x.get('GPano:$p') ?? '');
    double? doubleOf(String p) => double.tryParse(x.get('GPano:$p') ?? '');
    final meta = PanoramaMeta(
      projection: x.get('GPano:ProjectionType')?.trim().toLowerCase(),
      fullWidth: intOf('FullPanoWidthPixels'),
      fullHeight: intOf('FullPanoHeightPixels'),
      croppedWidth: intOf('CroppedAreaImageWidthPixels'),
      croppedHeight: intOf('CroppedAreaImageHeightPixels'),
      croppedLeft: intOf('CroppedAreaLeftPixels'),
      croppedTop: intOf('CroppedAreaTopPixels'),
      initialHeading: doubleOf('InitialViewHeadingDegrees'),
      initialPitch: doubleOf('InitialViewPitchDegrees'),
      initialFov: doubleOf('InitialViewHorizontalFOVDegrees'),
    );
    final empty =
        meta.projection == null &&
        meta.fullWidth == null &&
        meta.fullHeight == null;
    return empty ? null : meta;
  }

  /// True when the picture can be looked around in: an equirectangular
  /// projection, or (when the projection is not stated) a whole sphere that
  /// is twice as wide as it is tall.
  bool get isEquirectangular {
    final p = projection;
    if (p != null) return p == 'equirectangular';
    final w = fullWidth;
    final h = fullHeight;
    if (w == null || h == null || h <= 0) return false;
    return (w / h - 2).abs() < 0.02;
  }

  @override
  bool operator ==(Object other) =>
      other is PanoramaMeta &&
      other.projection == projection &&
      other.fullWidth == fullWidth &&
      other.fullHeight == fullHeight &&
      other.croppedWidth == croppedWidth &&
      other.croppedHeight == croppedHeight &&
      other.croppedLeft == croppedLeft &&
      other.croppedTop == croppedTop &&
      other.initialHeading == initialHeading &&
      other.initialPitch == initialPitch &&
      other.initialFov == initialFov;

  @override
  int get hashCode => Object.hash(
    projection,
    fullWidth,
    fullHeight,
    croppedWidth,
    croppedHeight,
    croppedLeft,
    croppedTop,
    initialHeading,
    initialPitch,
    initialFov,
  );
}
