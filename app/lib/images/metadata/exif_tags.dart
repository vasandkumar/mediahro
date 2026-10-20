import 'package:mediahro/images/metadata/tiff.dart';

/// Tag names for the info sheet (EXIF 3.0, TIFF 6.0, DNG). Names are the
/// standard identifiers, shown as-is in every locale like other tools do.
const Map<int, String> exifTagNames = {
  0x000B: 'ProcessingSoftware',
  0x00FE: 'SubfileType',
  0x0100: 'ImageWidth',
  0x0101: 'ImageHeight',
  0x0102: 'BitsPerSample',
  0x0103: 'Compression',
  0x0106: 'PhotometricInterpretation',
  0x010E: 'ImageDescription',
  0x010F: 'Make',
  0x0110: 'Model',
  0x0112: 'Orientation',
  0x0115: 'SamplesPerPixel',
  0x011A: 'XResolution',
  0x011B: 'YResolution',
  0x011C: 'PlanarConfiguration',
  0x0128: 'ResolutionUnit',
  0x0131: 'Software',
  0x0132: 'DateTime',
  0x013B: 'Artist',
  0x013E: 'WhitePoint',
  0x013F: 'PrimaryChromaticities',
  0x0211: 'YCbCrCoefficients',
  0x0213: 'YCbCrPositioning',
  0x0214: 'ReferenceBlackWhite',
  0x4746: 'Rating',
  0x4749: 'RatingPercent',
  0x8298: 'Copyright',
  0x829A: 'ExposureTime',
  0x829D: 'FNumber',
  0x8822: 'ExposureProgram',
  0x8824: 'SpectralSensitivity',
  0x8827: 'ISO',
  0x8830: 'SensitivityType',
  0x8832: 'RecommendedExposureIndex',
  0x9000: 'ExifVersion',
  0x9003: 'DateTimeOriginal',
  0x9004: 'DateTimeDigitized',
  0x9010: 'OffsetTime',
  0x9011: 'OffsetTimeOriginal',
  0x9012: 'OffsetTimeDigitized',
  0x9101: 'ComponentsConfiguration',
  0x9102: 'CompressedBitsPerPixel',
  0x9201: 'ShutterSpeedValue',
  0x9202: 'ApertureValue',
  0x9203: 'BrightnessValue',
  0x9204: 'ExposureBiasValue',
  0x9205: 'MaxApertureValue',
  0x9206: 'SubjectDistance',
  0x9207: 'MeteringMode',
  0x9208: 'LightSource',
  0x9209: 'Flash',
  0x920A: 'FocalLength',
  0x9214: 'SubjectArea',
  0x927C: 'MakerNote',
  0x9286: 'UserComment',
  0x9290: 'SubSecTime',
  0x9291: 'SubSecTimeOriginal',
  0x9292: 'SubSecTimeDigitized',
  0x9C9B: 'XPTitle',
  0x9C9C: 'XPComment',
  0x9C9D: 'XPAuthor',
  0x9C9E: 'XPKeywords',
  0x9C9F: 'XPSubject',
  0xA000: 'FlashpixVersion',
  0xA001: 'ColorSpace',
  0xA002: 'PixelXDimension',
  0xA003: 'PixelYDimension',
  0xA20E: 'FocalPlaneXResolution',
  0xA20F: 'FocalPlaneYResolution',
  0xA210: 'FocalPlaneResolutionUnit',
  0xA215: 'ExposureIndex',
  0xA217: 'SensingMethod',
  0xA300: 'FileSource',
  0xA301: 'SceneType',
  0xA401: 'CustomRendered',
  0xA402: 'ExposureMode',
  0xA403: 'WhiteBalance',
  0xA404: 'DigitalZoomRatio',
  0xA405: 'FocalLengthIn35mmFilm',
  0xA406: 'SceneCaptureType',
  0xA407: 'GainControl',
  0xA408: 'Contrast',
  0xA409: 'Saturation',
  0xA40A: 'Sharpness',
  0xA40C: 'SubjectDistanceRange',
  0xA420: 'ImageUniqueID',
  0xA430: 'CameraOwnerName',
  0xA431: 'BodySerialNumber',
  0xA432: 'LensSpecification',
  0xA433: 'LensMake',
  0xA434: 'LensModel',
  0xA435: 'LensSerialNumber',
  0xA460: 'CompositeImage',
  0xC612: 'DNGVersion',
  0xC614: 'UniqueCameraModel',
};

const Map<int, String> gpsTagNames = {
  0x0000: 'GPSVersionID',
  0x0001: 'GPSLatitudeRef',
  0x0002: 'GPSLatitude',
  0x0003: 'GPSLongitudeRef',
  0x0004: 'GPSLongitude',
  0x0005: 'GPSAltitudeRef',
  0x0006: 'GPSAltitude',
  0x0007: 'GPSTimeStamp',
  0x0008: 'GPSSatellites',
  0x000C: 'GPSSpeedRef',
  0x000D: 'GPSSpeed',
  0x0010: 'GPSImgDirectionRef',
  0x0011: 'GPSImgDirection',
  0x0012: 'GPSMapDatum',
  0x001B: 'GPSProcessingMethod',
  0x001D: 'GPSDateStamp',
  0x001F: 'GPSHPositioningError',
};

/// Tags whose values are binary blobs or offsets, not worth showing.
const _hidden = {
  0x0111, 0x0117, 0x0144, 0x0145, 0x0201, 0x0202, 0x02BC, 0x83BB, 0x8773,
  0x8769, 0x8825, 0xA005, 0x927C, 0x014A, 0xC634,
};

/// Every displayable tag of [s] as `Group:Name → value`.
Map<String, String> exifDisplayMap(TiffStructure s) {
  final out = <String, String>{};
  void dump(IfdKind k, String group, Map<int, String> names) {
    final ifd = s.ifd(k);
    if (ifd == null) return;
    for (final e in ifd.entries.values) {
      if (_hidden.contains(e.tag)) continue;
      final name =
          names[e.tag] ??
          'Tag0x${e.tag.toRadixString(16).padLeft(4, '0').toUpperCase()}';
      final v = _display(s, e);
      if (v.isNotEmpty) out['$group:$name'] = v;
    }
  }

  dump(IfdKind.ifd0, 'EXIF', exifTagNames);
  dump(IfdKind.exif, 'EXIF', exifTagNames);
  dump(IfdKind.gps, 'GPS', gpsTagNames);
  dump(IfdKind.interop, 'Interop', const {0x0001: 'InteropIndex'});
  return out;
}

String _display(TiffStructure s, TiffEntry e) {
  if (e.type == TiffType.ascii || (e.tag >= 0x9C9B && e.tag <= 0x9C9F)) {
    return s.stringOf(e);
  }
  if (e.tag == TiffTag.userComment && e.raw.length > 8) {
    final body = e.raw.sublist(8);
    final prefix = String.fromCharCodes(e.raw.sublist(0, 5));
    if (prefix == 'ASCII' || prefix == 'UNICO') {
      return String.fromCharCodes(
        body.where((c) => c != 0),
      ).trim();
    }
    return '';
  }
  if (e.type == TiffType.undefined) {
    if (e.raw.length <= 8 && e.raw.every((c) => c >= 0x20 && c < 0x7f)) {
      return String.fromCharCodes(e.raw);
    }
    return e.raw.length > 16 ? '' : e.raw.join(' ');
  }
  final names = _enums[e.tag];
  if (names != null) {
    final v = s.ints(e).firstOrNull;
    return names[v] ?? '$v';
  }
  switch (e.tag) {
    case 0x829A:
      final t = s.doubles(e).firstOrNull ?? 0;
      return t >= 1 || t <= 0
          ? '${_trim(t)} s'
          : '1/${(1 / t).round()} s';
    case 0x829D:
      return 'f/${_trim(s.doubles(e).firstOrNull ?? 0)}';
    case 0x920A:
      return '${_trim(s.doubles(e).firstOrNull ?? 0)} mm';
  }
  if (e.type == TiffType.rational ||
      e.type == TiffType.srational ||
      e.type == TiffType.float ||
      e.type == TiffType.double) {
    return s.doubles(e).take(16).map(_trim).join(' ');
  }
  return s.ints(e).take(16).join(' ');
}

String _trim(double d) {
  final r = (d * 1000).roundToDouble() / 1000;
  return r == r.roundToDouble() ? r.toInt().toString() : r.toString();
}

const Map<int, Map<int, String>> _enums = {
  0x0112: {
    1: 'Horizontal (normal)',
    2: 'Mirror horizontal',
    3: 'Rotate 180',
    4: 'Mirror vertical',
    5: 'Mirror horizontal and rotate 270 CW',
    6: 'Rotate 90 CW',
    7: 'Mirror horizontal and rotate 90 CW',
    8: 'Rotate 270 CW',
  },
  0x8822: {
    0: 'Not defined',
    1: 'Manual',
    2: 'Program AE',
    3: 'Aperture-priority AE',
    4: 'Shutter speed priority AE',
    5: 'Creative (slow speed)',
    6: 'Action (high speed)',
    7: 'Portrait',
    8: 'Landscape',
  },
  0x9207: {
    0: 'Unknown',
    1: 'Average',
    2: 'Center-weighted average',
    3: 'Spot',
    4: 'Multi-spot',
    5: 'Multi-segment',
    6: 'Partial',
    255: 'Other',
  },
  0xA001: {1: 'sRGB', 2: 'Adobe RGB', 0xFFFF: 'Uncalibrated'},
  0xA402: {0: 'Auto', 1: 'Manual', 2: 'Auto bracket'},
  0xA403: {0: 'Auto', 1: 'Manual'},
  0xA406: {0: 'Standard', 1: 'Landscape', 2: 'Portrait', 3: 'Night'},
  0x0128: {1: 'None', 2: 'inches', 3: 'cm'},
};
